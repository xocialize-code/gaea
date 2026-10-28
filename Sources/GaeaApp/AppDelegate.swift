import AppKit
import Foundation
import GaeaConsole
import GaeaCore
import MESEngineUI
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launch: Launch
    private let console = EngineConsoleModel(info: EngineConsoleInfo(name: "Gaea", profile: "Image · Audio · Video",
                                                                     symbol: "square.stack.3d.up", version: Gaea.version))
    private let system = SystemMonitorStore()
    private let menuBar = MenuBarPreferences()
    private var window: EngineConsoleWindowController?
    private var statusItem: EngineStatusItemController?
    private var host: GaeaHost?
    private var serving: Task<Void, Never>?

    init(launch: Launch) {
        self.launch = launch
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.mainMenu()
        var options = launch.options
        if options.paired, !launch.approvePairings {
            // Base §5: a person on this Mac approves each pairing, comparing the code on both screens.
            options.pairingApproval = { prompt in
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Pair “\(prompt.clientName)” with Gaea?"
                    alert.informativeText = "Its screen should show \(prompt.code). Only approve if it does."
                    alert.addButton(withTitle: "Pair")
                    alert.addButton(withTitle: "Don’t Pair")
                    NSApp.activate()
                    return alert.runModal() == .alertFirstButtonReturn
                }
            }
        }
        let host: GaeaHost
        do {
            host = try GaeaHost(options: options)
        } catch {
            console.status = .failed("\(error)")
            fail("\(error)")
            return
        }
        self.host = host
        system.processSource = host.processSource
        if launch.snapshot == nil {
            let window = EngineConsoleWindowController(console: console, system: system, menuBar: menuBar)
            self.window = window
            statusItem = EngineStatusItemController(console: console, system: system, menuBar: menuBar) { window.show($0) }
            window.show(.plugins)
        }
        let console = self.console
        let backend = GaeaConsoleBackend(host: host)
        let plugins = GaeaPluginBackend(host: host)
        let paired = launch.options.paired
        let snapshot = launch.snapshot
        serving = Task {
            do {
                try await host.run { _ in
                    await MainActor.run {
                        console.endpoint = host.endpoint
                        console.modeSummary = paired ? "Paired mode · any Mac on the network" : "Open mode · this Mac only"
                        console.attach(backend, plugins: plugins)
                    }
                    if let snapshot {
                        Task { @MainActor in await self.renderSnapshots(to: snapshot) }
                    }
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run { self.fail("\(error)") }
            }
        }
    }

    private func fail(_ message: String) {
        FileHandle.standardError.write(Data("Gaea: \(message)\n".utf8))
        if launch.snapshot != nil { exit(1) }
        console.status = .failed(message)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let host, let serving else { return .terminateNow }
        Task {
            serving.cancel()
            await host.scheduler.stopAll()
            host.operatorServer.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Renders the Plugins, Models and System pages, light and dark, the way MESKit's console gallery does.
    private func renderSnapshots(to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // One run on the first enabled plugin model, so the System page has a live worker to show.
        if let host, let first = await host.engine.catalog().first(where: { $0.plugin.enabled }) {
            let job = WorkerJob(job: "job_snapshot", pluginID: first.plugin.id, model: first.model.id, operation: first.operation,
                                params: ["n": 4096, "iterations": 20, "holdBytes": 1_000_000_000],
                                outputDir: host.paths.spool.appending(path: "snapshot"))
            _ = try? await host.scheduler.run(job) { _ in }
        }
        await host?.manager.checkForUpdates()
        await console.refreshModels()
        await console.refreshPlugins()
        await system.sampleNow()
        try? await Task.sleep(for: .seconds(1))
        await system.sampleNow()
        let pages: [(String, () -> Void)] = [
            ("plugins", { self.console.section = .plugins; self.console.selectedPluginID = self.console.plugins.first?.id }),
            ("models", { self.console.section = .models; self.console.selectedModelID = self.console.models.first?.id }),
            ("system-memory", { self.console.section = .system; self.system.tab = .memory }),
            ("system-overview", { self.console.section = .system; self.system.tab = .overview }),
        ]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for (name, select) in pages {
                select()
                let view = NSHostingView(rootView: EngineConsoleView(console: console, system: system, menuBar: menuBar)
                    .background(Color(nsColor: .windowBackgroundColor)))
                view.appearance = NSAppearance(named: appearance)
                view.frame = NSRect(x: 0, y: 0, width: 1320, height: 1000)
                let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = view
                view.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(800))
                view.layoutSubtreeIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let file = directory.appendingPathComponent("console-\(name)-\(appearance == .aqua ? "light" : "dark").png")
                try? rep.representation(using: .png, properties: [:])?.write(to: file)
                print("wrote \(file.path)")
            }
        }
        NSApp.terminate(nil)
    }

    private static func mainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Gaea", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        return main
    }
}
