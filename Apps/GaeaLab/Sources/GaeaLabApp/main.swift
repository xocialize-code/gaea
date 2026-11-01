import AppKit
import Foundation
import GaeaLabCore
import MESCore
import MESFormsUI
import PixelAgencyRun
import SwiftUI

// Gaea Lab.
//
//   GaeaLab                                   the app
//   GaeaLab --snapshot <dir> --engine <url>… [--operation image.generate | audio.speak | audio.compose | video.generate]
//                                             add those servers, choose the operation with a preset (image.generate on
//                                             Qwen-Image Flash with a LoRA; audio.speak on Kokoro with a voice, streamed;
//                                             audio.compose on ACE-Step with lyrics and timestamps; video.generate on
//                                             LTX 2.5 compact24, its terms shown, then accepted for this run only), run it
//                                             on "Every server", and render the window before and after to PNGs (light
//                                             and dark), then quit
let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
    let directory = URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
    let engines = arguments.indices.filter { arguments[$0] == "--engine" && $0 + 1 < arguments.count }.compactMap { URL(string: arguments[$0 + 1]) }
    let operation = arguments.firstIndex(of: "--operation").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } ?? "image.generate"
    MainActor.assumeIsolated {
        LabModel.acceptances = LicenseAcceptances()
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            await Snapshot.render(to: directory, engines: engines, operation: operation)
            exit(0)
        }
        app.run()
    }
} else {
    GaeaLabApp.main()
}

@MainActor
enum Snapshot {
    static func render(to directory: URL, engines: [URL], operation: String) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lab = LabModel.shared
        for url in engines { _ = try? await lab.directory.add(url: url) }
        await lab.refreshPool()
        guard let run = lab.workflow.operations.first(where: { $0.operation == operation }).map({ descriptor -> RunSession? in
            lab.workflow.choose(descriptor)
            return lab.workflow.current
        }) ?? nil else {
            print("no \(operation) on the pool")
            return
        }
        switch operation {
        case "audio.speak":
            run.form.model = "kokoro-82m"
            run.streamByDefault()
            run.form.text["text"] = "Gaea Lab speaks through Kokoro, streamed as it is made. [pause 0.5s] Then the whole take plays back."
            run.form.setValue(.string("af_heart"), at: ["voice"])
            run.form.setValue(.number(1), at: ["seed"])
        case "audio.compose":
            run.form.model = "ace-step-1.5"
            run.form.text["caption"] = "Upbeat synth-pop with a bright female vocal and a driving beat."
            run.form.text["lyrics"] = "[verse]\nLights on the water\nWe follow the line\n[chorus]\nRun all night"
            run.form.setValue(.number(10), at: ["duration_s"])
            run.form.setValue(.string("en"), at: ["language"])
            run.form.setValue(.bool(true), at: ["timestamps"])
            run.form.setValue(.number(5), at: ["seed"])
        case "video.generate":
            run.form.model = "ltx-2.5-compact24"
            run.form.text["prompt"] = "A red kite flies over a green hill on a sunny day, the camera slowly following it."
            run.form.setValue(.number(1), at: ["duration_s"])
            run.form.setValue(.object(["width": .number(256), "height": .number(256)]), at: ["size"])
            run.form.setValue(.number(7), at: ["seed"])
        default:
            run.form.model = "qwen-image-flash"
            run.form.text["prompt"] = "a lighthouse on a cliff at dusk"
            run.form.setValue(.number(7), at: ["seed"])
            if let adapter = AdapterChoices.offered(by: run.descriptor, model: "qwen-image-flash").first?.adapter {
                lab.choices.choose(adapter.id, strength: 0.8, on: true, for: "image.generate")
            }
        }
        let save = directory.appending(path: "saved", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        await capture(lab, save: save, to: directory, name: "\(operation)-before")
        if !run.needsAcceptance.isEmpty {
            print("needs acceptance: \(run.needsAcceptance.map(\.spdx).joined(separator: ", "))")
            for license in run.needsAcceptance { run.acceptances.accept(license) }
        }
        lab.workflow.start()
        while run.phase.isActive || run.phase == .editing { try? await Task.sleep(for: .milliseconds(500)) }
        print("run: \(run.phase); route: \(lab.currentRoute.map { "\($0.engineName)" } ?? "none")")
        if let s = run.streamed {
            print("streamed \(s.chunks) chunks, \(String(format: "%.2f", s.seconds)) s; first after \(s.firstChunkAfter.map { "\(Int($0 * 1000)) ms" } ?? "-")")
        }
        print("results: \(run.results.map { $0.output.name + ($0.isVideo ? " (video \($0.videoFacts?.line ?? ""))" : $0.isAudio ? " (audio)" : $0.isText ? " (text)" : "") }.joined(separator: ", "))")
        await capture(lab, save: save, to: directory, name: "\(operation)-after")
        lab.end()
    }

    static func capture(_ lab: LabModel, save: URL, to directory: URL, name: String) async {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let view = NSHostingView(rootView: LabRoot(lab: lab, saveFolder: save).background(Color(nsColor: .windowBackgroundColor)))
            view.appearance = NSAppearance(named: appearance)
            view.frame = NSRect(x: 0, y: 0, width: 1500, height: 900)
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(1500))
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let file = directory.appendingPathComponent("lab-\(name)-\(appearance == .aqua ? "light" : "dark").png")
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
            print("wrote \(file.path)")
        }
    }
}
