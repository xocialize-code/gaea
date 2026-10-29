import Foundation
import ImageLibrary
import PixelAgencyCore
import PixelAgencyRun

// autodescribe-live <engine-url> <work-dir> <image>…: imports the images into a fresh library, starts Desktop's
// AutoDescriber with the engine in the directory, and prints each image's caption, alt text and tags once described.
@MainActor func main() async throws {
    let args = CommandLine.arguments
    let url = URL(string: args[1])!, work = URL(fileURLWithPath: args[2], isDirectory: true)
    let drop = work.appendingPathComponent("drop", isDirectory: true)
    try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
    for path in args.dropFirst(3) {
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: drop.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent))
    }
    let library = try Library(workingFolder: work.appendingPathComponent("library"), cacheRoot: work.appendingPathComponent("cache"))
    let directory = EngineDirectory(credentials: MemoryCredentialStore(), clientName: "autodescribe-live",
                                    defaults: UserDefaults(suiteName: "autodescribe-live-\(UUID().uuidString)")!)
    let entry = try await directory.add(url: url)
    print("engine: \(entry.id) \(url)")
    let runner = TicketRunner(library: library, directory: directory)
    let added = library.importFiles([drop]).added
    print("imported \(added.count); pending descriptions: \(try library.pendingDescriptions(maxAttempts: 3, limit: 100).count)")
    let describer = AutoDescriber(runner: runner)
    describer.idleInterval = .milliseconds(500)
    describer.pollInterval = .milliseconds(100)
    let started = Date()
    describer.start()
    while Date().timeIntervalSince(started) < 300 {
        if try added.allSatisfy({ try library.assets.asset($0)?.caption != nil }) { break }
        if let why = describer.waitingReason { print("waiting: \(why)") }
        try await Task.sleep(for: .milliseconds(500))
    }
    describer.stop()
    print(String(format: "auto-describe: %d of %d described in %.1f s", describer.completed, added.count, Date().timeIntervalSince(started)))
    for id in added {
        let a = try library.assets.asset(id)
        print("\(id): caption: \(a?.caption ?? "-")\n  alt: \(a?.altText ?? "-")\n  tags: \(a?.autoTags ?? [])")
    }
    for t in try library.tickets() { print("ticket \(t.operation) \(t.state.rawValue) requester=\(t.requester ?? "-") engine=\(t.engineID ?? "any")") }
}
try await main()
