import Foundation
import ImageLibrary
import MESCore
import PixelAgencyCore
import PixelAgencyRun

// desktop-gaea-check <photo.png> <server-url>…: Desktop's TicketRunner over the given Gaea servers, as Desktop sends work
// (D-38, G-20): scaling through MESClientKit's engine picker, and any operation to an engine that offers it. Prints each
// ticket, the server it was dispatched to, and its output; exits 1 when a ticket fails.
@MainActor
func check() async throws -> Bool {
    let args = Array(CommandLine.arguments.dropFirst())
    let photo = URL(fileURLWithPath: args[0])
    let folder = FileManager.default.temporaryDirectory.appending(path: "desktop-gaea-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let drop = folder.appending(path: "drop", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: photo, to: drop.appending(path: "photo.png"))
    let library = try Library(workingFolder: folder, cacheRoot: folder.appending(path: "cache"))
    guard let asset = library.importFiles([drop], filing: Library.Filing(project: nil)).added.first else {
        print("couldn't import the photo"); return false
    }
    let directory = EngineDirectory(credentials: MemoryCredentialStore(), clientName: "Desktop check (AB-T-0375)",
                                    defaults: UserDefaults(suiteName: "desktop-gaea-\(UUID().uuidString)")!)
    for url in args.dropFirst() {
        let entry = try await directory.add(url: URL(string: url)!)
        print("server \(entry.id) \(url)")
    }
    let runner = TicketRunner(library: library, directory: directory)
    runner.engineWait = .seconds(10)
    print("scaling engines, best first: \(await runner.scalingEngines().map(\.id))")

    let photoInputs = ["image": [asset]]
    let prompt: [String: RequestInput] = ["prompt": .text("a lighthouse on a cliff at dusk")]
    let jobs = [
        ("scale x2, the picker's choice", "image.upscale", JobRequest(operation: "image.upscale", params: ["scale": 2]), photoInputs),
        ("scale x4 on NERVE", "image.upscale", JobRequest(operation: "image.upscale", params: ["scale": 4], model: "nerve-upscale"), photoInputs),
        ("generate on Z-Image Turbo", "image.generate",
         JobRequest(operation: "image.generate", inputs: prompt, params: ["seed": 7], model: "z-image-turbo"), [:]),
        ("generate on Qwen-Image Flash", "image.generate",
         JobRequest(operation: "image.generate", inputs: prompt, params: ["seed": 7], model: "qwen-image-flash"), [:]),
    ]
    var ok = true
    for (name, operation, request, inputs) in jobs {
        let ticket = try runner.submit(operation: operation, request: request, inputs: inputs, engineID: nil, requester: "optimizer")
        guard let done = await runner.finish(ticket.id) else { print("\(name): no ticket"); ok = false; continue }
        let outputs = done.outputs.count
        print("\(name): \(done.state) on \(done.dispatchedEngineID ?? "-"), \(outputs) output(s)\(done.error.map { ", \($0)" } ?? "")")
        ok = ok && done.state == TicketState.completed && outputs > 0
    }
    return ok
}

let ok = try await MainActor.run { Task { try await check() } }.value
exit(ok ? 0 : 1)
