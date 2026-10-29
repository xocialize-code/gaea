import AppKit
import Foundation
import GaeaLabCore
import MESCore
import PixelAgencyRun
import SwiftUI

// Gaea Lab.
//
//   GaeaLab                                   the app
//   GaeaLab --snapshot <dir> --engine <url>…  add those servers, choose image.generate on Qwen-Image Flash with a LoRA,
//                                             run it on "Every server", and render the window before and after to PNGs
//                                             (light and dark), then quit
let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
    let directory = URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
    let engines = arguments.indices.filter { arguments[$0] == "--engine" && $0 + 1 < arguments.count }.compactMap { URL(string: arguments[$0 + 1]) }
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            await Snapshot.render(to: directory, engines: engines)
            exit(0)
        }
        app.run()
    }
} else {
    GaeaLabApp.main()
}

@MainActor
enum Snapshot {
    static func render(to directory: URL, engines: [URL]) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lab = LabModel.shared
        for url in engines { _ = try? await lab.directory.add(url: url) }
        await lab.refreshPool()
        guard let run = lab.workflow.operations.first(where: { $0.operation == "image.generate" }).map({ descriptor -> RunSession? in
            lab.workflow.choose(descriptor)
            return lab.workflow.current
        }) ?? nil else {
            print("no image.generate on the pool")
            return
        }
        run.form.model = "qwen-image-flash"
        run.form.text["prompt"] = "a lighthouse on a cliff at dusk"
        run.form.setValue(.number(7), at: ["seed"])
        if let adapter = AdapterChoices.offered(by: run.descriptor, model: "qwen-image-flash").first?.adapter {
            lab.choices.choose(adapter.id, strength: 0.8, on: true, for: "image.generate")
        }
        let save = directory.appending(path: "saved", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        await capture(lab, save: save, to: directory, name: "before")
        lab.workflow.start()
        while run.phase.isActive || run.phase == .editing { try? await Task.sleep(for: .milliseconds(500)) }
        print("run: \(run.phase); route: \(lab.currentRoute.map { "\($0.engineName)" } ?? "none")")
        await capture(lab, save: save, to: directory, name: "after")
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
