import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--selftest") {
            let url = URL(string: args.count > i + 1 ? args[i + 1] : "http://127.0.0.1:8765/catalog.json")!
            let include = args.contains("--include-quarantine-block")
            Task { exit(await SelfTest.run(catalogURL: url, includeQuarantineBlock: include)) }
            dispatchMain()
        }
        GaeaPluginHostApp.main()
    }
}

struct GaeaPluginHostApp: App {
    @State private var model = HostModel()
    var body: some Scene {
        WindowGroup("Gaea Plugin Spike") { ContentView(model: model).frame(minWidth: 640, minHeight: 420) }
    }
}

@MainActor @Observable
final class HostModel {
    var catalogURL = "http://127.0.0.1:8765/catalog.json"
    var entries: [CatalogEntry] = []
    var installed: [String: InstalledPlugin] = [:]
    var log: [String] = []
    var running: PluginProcess?
    let installer = PluginInstaller()

    func say(_ s: String) { log.append(s) }

    func refresh() async {
        do { entries = try await installer.fetchCatalog(URL(string: catalogURL)!).plugins; say("catalog: \(entries.count) plugins") }
        catch { say("catalog failed: \(error)") }
    }

    func install(_ e: CatalogEntry) async {
        do {
            let (p, r) = try await installer.install(e, quarantine: .asDownloaded)
            installed[e.id] = p; say("installed \(e.id) — \(r.signature)")
        } catch { say("install \(e.id) refused: \(error)") }
    }

    func run(_ e: CatalogEntry) async {
        guard let plugin = installed[e.id] else { return }
        do {
            let p = PluginProcess(executable: plugin.executableURL)
            p.process.currentDirectoryURL = FileManager.default.temporaryDirectory
            p.process.launchRequirement = try SelfTest.launchRequirement(team: e.teamID)
            p.onEvent = { [weak self] m in
                if m["type"] as? String == "progress" { Task { @MainActor in self?.say("  step \(m["step"] ?? "?")/\(m["of"] ?? "?")") } }
            }
            let (_, s) = try await p.start(); running = p
            say(String(format: "launched pid %d in %.0f ms", p.pid, s * 1000))
            let r = await p.run(id: UUID().uuidString, op: "demo.matmul", params: ["n": 4096, "iterations": 10])
            say("result: \(r["output"] ?? r["message"] ?? "?")")
            p.shutdown(); running = nil
        } catch { say("run failed: \(error.localizedDescription)") }
    }
}

struct ContentView: View {
    @Bindable var model: HostModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Catalog URL", text: $model.catalogURL).textFieldStyle(.roundedBorder)
                Button("Refresh") { Task { await model.refresh() } }
            }
            List(model.entries) { e in
                HStack {
                    VStack(alignment: .leading) { Text(e.id).font(.headline); Text("v\(e.version) · team \(e.teamID)").font(.caption) }
                    Spacer()
                    Button("Install") { Task { await model.install(e) } }
                    Button("Run") { Task { await model.run(e) } }.disabled(model.installed[e.id] == nil)
                }
            }.frame(minHeight: 140)
            ScrollView { Text(model.log.joined(separator: "\n")).font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
        }.padding()
    }
}
