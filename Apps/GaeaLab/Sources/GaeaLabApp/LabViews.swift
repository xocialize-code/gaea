import AppKit
import DesignScaffold
import GaeaLabCore
import MESCore
import PixelAgencyRun
import PixelAgencyRunUI
import SwiftUI

/// Gaea Lab (G-14): a thin app around the open run workflow, like Lite, with every server as one engine and a LoRA
/// panel, which MESFormsUI's controls don't cover.
struct GaeaLabApp: App {
    @NSApplicationDelegateAdaptor(LabAppDelegate.self) var appDelegate
    @State private var lab = LabModel.shared

    var body: some Scene {
        Window("Gaea Lab", id: "main") {
            LabRoot(lab: lab)
                .task { lab.start() }
        }
        .defaultSize(width: 1500, height: 880)
        .windowToolbarStyle(.unifiedCompact)
        Settings {
            LabSettings(lab: lab)
        }
    }
}

final class LabAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { LabModel.shared.end() }
    }
}

struct LabRoot: View {
    let lab: LabModel
    /// A folder to save to without asking (the snapshot).
    var saveFolder: URL?

    var body: some View {
        if let url = saveFolder ?? lab.folder.url {
            HStack(spacing: 0) {
                RunWorkflowView(workflow: lab.workflow, saveFolder: url)
                Divider()
                LoRAPanel(lab: lab)
                    .frame(width: 300)
            }
            .frame(minWidth: Tokens.Layout.minWindowWidth, minHeight: Tokens.Layout.minWindowHeight)
        } else {
            WorkingFolderOnboarding(folder: lab.folder, appName: "Gaea Lab",
                                    purpose: "Results you save go there; everything else from a session is cleared when you quit.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The current run's adapters (Base §6.3): those its model's offer lists, or every model's when the engine chooses the
/// model. An adapter implies its model, so choosing one with the model on automatic sends the job to that model.
struct LoRAPanel: View {
    let lab: LabModel
    /// Strength by adapter id, for the current operation; mirrors `lab.choices`.
    @State private var chosen: [String: Double] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                Text("LoRAs").font(Tokens.Font.headline)
                if let run = lab.workflow.current {
                    let offered = AdapterChoices.offered(by: run.descriptor, model: run.form.model)
                    if offered.isEmpty {
                        Text(run.form.model == nil ? "No model for this operation takes adapters."
                             : "\(run.form.model ?? "") takes no adapters here.")
                            .font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel)
                    }
                    ForEach(offered, id: \.adapter.id) { item in
                        row(item.adapter, model: item.model, operation: run.descriptor.operation)
                    }
                    if let route = lab.currentRoute {
                        Divider()
                        Text("Ran on \(route.engineName)").font(Tokens.Font.caption)
                        Text(route.resident ? "Its model was loaded there." : "Its model loaded for this job.")
                            .font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel)
                    }
                } else {
                    Text("Choose an operation.").font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel)
                }
                Divider()
                Text(lab.members.isEmpty ? "No server yet: Gaea Lab finds them on the network, or add one by address."
                     : "Every server: \(lab.members.map(\.name).joined(separator: ", "))")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel)
            }
            .padding(Tokens.Space.l)
        }
        .onChange(of: lab.workflow.current?.descriptor.operation, initial: true) { _, operation in
            chosen = Dictionary(uniqueKeysWithValues: (operation.map { lab.choices.adapters(for: $0) } ?? [])
                .map { ($0.id, $0.strength ?? 1) })
        }
    }

    func row(_ adapter: AdapterOffer, model: String, operation: String) -> some View {
        let isOn = Binding(get: { chosen[adapter.id] != nil }, set: { on in
            chosen[adapter.id] = on ? adapter.strength.defaultValue : nil
            lab.choices.choose(adapter.id, strength: chosen[adapter.id], on: on, for: operation)
        })
        let strength = Binding(get: { chosen[adapter.id] ?? adapter.strength.defaultValue }, set: { value in
            chosen[adapter.id] = value
            lab.choices.choose(adapter.id, strength: value, on: true, for: operation)
        })
        return VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Toggle(adapter.title, isOn: isOn)
            if isOn.wrappedValue {
                HStack {
                    Slider(value: strength, in: adapter.strength.min...adapter.strength.max)
                    Text(strength.wrappedValue.formatted(.number.precision(.fractionLength(2)))).font(Tokens.Font.mono)
                }
            }
            Text("\(model) · \(adapter.license.spdx)" + (adapter.kind == .ic ? " · reference images first" : ""))
                .font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel)
            if let notes = adapter.notes {
                Text(notes).font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel).lineLimit(3)
            }
        }
    }
}

struct LabSettings: View {
    let lab: LabModel
    @State private var changing = false
    @State private var address = ""
    @State private var problem: String?

    var body: some View {
        Form {
            Section("Servers") {
                ForEach(lab.directory.entries.filter { $0.id != lab.pool.id }) { entry in
                    LabeledContent(entry.name, value: entry.needsPairing ? "needs pairing" : (entry.url?.absoluteString ?? ""))
                }
                HStack {
                    TextField("Add by address", text: $address, prompt: Text("http://host:17761/mes/v0"))
                    Button("Add") {
                        guard let url = URL(string: address) else { return }
                        Task {
                            do { try await lab.directory.add(url: url); address = ""; problem = nil } catch { problem = "\(error)" }
                        }
                    }
                }
                if let problem { Text(problem).font(Tokens.Font.caption).foregroundStyle(Tokens.Color.failure) }
                Text("Gaea Lab finds servers on the network itself. Choose \"Every server\" to let each job go to the one that has its model.")
                    .font(Tokens.Font.caption).foregroundStyle(Tokens.Color.secondaryLabel)
            }
            Section("Working folder") {
                LabeledContent("Results are saved to") {
                    Text(lab.folder.url?.path ?? "Not chosen").font(Tokens.Font.mono).lineLimit(1).truncationMode(.middle)
                }
                Button("Change…") { changing = true }
            }
            Section("About") {
                LabeledContent("Gaea Lab", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                LabeledContent("Licence", value: "Apache-2.0, open source")
                LabeledContent("Speaks", value: "Media Engine Specification · Base 0.1, Image 0.1")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fileImporter(isPresented: $changing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                try? lab.folder.choose(url)
            }
        }
    }
}
