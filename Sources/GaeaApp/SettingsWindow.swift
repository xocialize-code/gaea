import AppKit
import GaeaCore
import SwiftUI

/// Gaea's own settings (G-17: a server is configured in its own UI). For now, the shared weights folder (G-9, MEM-8):
/// the same setting as `gaea models root`, kept in gaea.sqlite.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(host: GaeaHost) {
        let view = SettingsView(host: host)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 220), styleMask: [.titled, .closable],
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
