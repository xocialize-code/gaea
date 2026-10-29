import AppKit
import GaeaCore
import SwiftUI

/// Gaea's own settings (G-17: a server is configured in its own UI): the shared weights folder (G-9, MEM-8), the same
/// setting as `gaea models root`, and adapters (GPP-1 §4.8), the same as `gaea adapters`. Both are kept in gaea.sqlite.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(host: GaeaHost) {
        let view = TabView {
            SettingsView(host: host).tabItem { Label("General", systemImage: "gearshape") }
            AdaptersView(host: host).tabItem { Label("Adapters", systemImage: "square.stack.3d.up") }
        }
        .frame(minWidth: 640, minHeight: 420)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520), styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Gaea Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let host: GaeaHost
    @State private var root = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Models folder") {
                    Text(root).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                }
                HStack {
                    Button("Choose…", action: choose)
                    Button("Use MLXEngine’s Store") { apply(nil) }
                        .disabled(root == host.paths.modelsRoot.path)
                }
                Text("Where plugins find and download weights. Every plugin shares it. Workers restart when it changes; "
                     + "a running job finishes first.")
                    .font(.callout).foregroundStyle(.secondary)
                if let error {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .task { root = await host.scheduler.modelsRoot.path }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: root)
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        apply(url)
    }

    private func apply(_ url: URL?) {
        Task {
            do {
                try await host.scheduler.setModelsRoot(url)
                error = nil
            } catch {
                self.error = "\(error)"
            }
            root = await host.scheduler.modelsRoot.path
        }
    }
}

/// Adapters (LoRAs): the ones plugins ship and the ones added here by Hugging Face repo URL, each on or off for clients.
/// An opt-in adapter (unknown, research or gated terms, or not yet judged) starts off; switching it on accepts its terms.
struct AdaptersView: View {
    let host: GaeaHost
    @State private var adapters: [GaeaEngine.AdapterListing] = []
    @State private var takers: [String] = []
    @State private var url = ""
    @State private var model = ""
    @State private var file = ""
    @State private var adding = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        Form {
            Section("Add a LoRA") {
                TextField("Hugging Face repo URL", text: $url, prompt: Text("https://huggingface.co/owner/repo"))
                Picker("For model", selection: $model) {
                    ForEach(takers, id: \.self) { Text($0).tag($0) }
                }
                .disabled(takers.isEmpty)
                TextField("File (when the repo has several)", text: $file, prompt: Text("optional"))
                HStack {
                    Button("Add") { add() }
                        .disabled(adding || url.isEmpty || model.isEmpty)
                    if adding { ProgressView().controlSize(.small) }
                }
                Text(takers.isEmpty ? "No installed model takes adapters yet."
                     : "Gaea pins the repo's current commit, reads its licence from the card, and checks that the model takes "
                       + "its format. The worker downloads it into the models folder on first use.")
                    .font(.callout).foregroundStyle(.secondary)
                if let message {
                    Text(message).font(.callout).foregroundStyle(failed ? .red : .secondary).textSelection(.enabled)
                }
            }
            Section("Adapters") {
                if adapters.isEmpty {
                    Text("None: no plugin ships one, and none was added.").foregroundStyle(.secondary)
                }
                ForEach(adapters, id: \.id) { adapter in
                    HStack(alignment: .firstTextBaseline) {
                        Toggle(isOn: Binding(get: { adapter.enabled }, set: { set(adapter.id, $0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(adapter.title)
                                Text("\(adapter.id) · \(adapter.model) · \(adapter.license)\(adapter.optIn ? " · opt-in" : "")"
                                     + (adapter.trigger.map { " · trigger “\($0)”" } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                        Spacer()
                        if adapter.registered {
                            Button("Remove", role: .destructive) { remove(adapter.id) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await reload() }
    }

    private func reload() async {
        adapters = await host.engine.adapterListings()
        takers = Set(await host.engine.routes().filter { $0.manifestOffer.adapterSupport != nil }.map(\.model.id)).sorted()
        if !takers.contains(model) { model = takers.first ?? "" }
    }

    private func add() {
        adding = true
        Task {
            defer { adding = false }
            do {
                let row = try await host.engine.registerAdapter(.init(url: url, model: model, file: file.isEmpty ? nil : file))
                await host.server.reloadDescriptors()
                failed = false
                message = "Added \(row.id): \(row.repo)@\(row.revision.prefix(12)) \(row.file), \(row.license)."
                url = ""
                file = ""
            } catch {
                failed = true
                message = "\(error)"
            }
            await reload()
        }
    }

    private func set(_ id: String, _ on: Bool) {
        Task {
            do {
                try await host.engine.setAdapter(id, enabled: on)
                await host.server.reloadDescriptors()
            } catch {
                failed = true
                message = "\(error)"
            }
            await reload()
        }
    }

    private func remove(_ id: String) {
        Task {
            do {
                try host.engine.removeAdapter(id)
                await host.server.reloadDescriptors()
                failed = false
                message = "Removed \(id). Its weights stay in the models folder."
            } catch {
                failed = true
                message = "\(error)"
            }
            await reload()
        }
    }
}
