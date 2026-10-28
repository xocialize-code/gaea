import Foundation
import LightweightCodeRequirements

/// Headless validation matrix: `GaeaPluginHost --selftest <catalog-url>`.
enum SelfTest {
    static let team = "CFZS6RXUCP"
    static var failures = 0

    static func check(_ ok: Bool, _ label: String, _ detail: String = "") {
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    }

    static func gb(_ b: UInt64) -> String { String(format: "%.2f GB", Double(b) / 1_073_741_824) }

    static func launchRequirement(team: String) throws -> LaunchCodeRequirement {
        try LaunchCodeRequirement.allOf {
            TeamIdentifier(team)
            ValidationCategory(.developerID)
        }
    }

    static func launch(_ plugin: InstalledPlugin, enforce: Bool = true) async throws -> (PluginProcess, Double) {
        let p = PluginProcess(executable: plugin.executableURL)
        p.process.currentDirectoryURL = FileManager.default.temporaryDirectory
        if enforce { p.process.launchRequirement = try launchRequirement(team: plugin.entry.teamID) }
        let (_, seconds) = try await p.start()
        return (p, seconds)
    }

    static func run(catalogURL: URL, includeQuarantineBlock: Bool) async -> Int32 {
        let installer = PluginInstaller()
        print("host: \(Bundle.main.bundlePath)  plugins → \(installer.root.path)\n")

        // 1. Discovery
        guard let catalog = try? await installer.fetchCatalog(catalogURL) else { check(false, "catalog fetch"); return 1 }
        check(catalog.plugins.count == 3, "catalog lists \(catalog.plugins.count) plugins")
        let good = catalog.plugins.first { $0.id == "com.xocialize.gaea.demo" }!
        let adhoc = catalog.plugins.first { $0.id.hasSuffix(".adhoc") }!
        let tampered = catalog.plugins.first { $0.id.hasSuffix(".tampered") }!

        // 2. Install as Gaea would: URLSession download, sha256, own signature check
        do {
            let (plugin, report) = try await installer.install(good, quarantine: .asDownloaded)
            check(!report.downloadQuarantined, "URLSession download not quarantined (no LSFileQuarantineEnabled)")
            check(true, "signature accepted", report.signature)

            // 3. Launch under a kernel-enforced launch requirement, then a real GPU job
            let (p, helloSeconds) = try await launch(plugin)
            check(true, "worker launched and said hello", String(format: "%.0f ms, pid %d", helloSeconds * 1000, p.pid))
            print("      hello: mainResources=\(p.hello?["mainResources"] ?? "?")")
            let idle = p.footprintBytes
            var peak: UInt64 = 0
            let sampler = Task { while !Task.isCancelled { peak = max(peak, p.footprintBytes); try? await Task.sleep(nanoseconds: 50_000_000) } }
            var progress = 0
            p.onEvent = { if $0["type"] as? String == "progress" { progress += 1 } }
            let t0 = Date()
            let result = await p.run(id: "j1", op: "demo.matmul", params: ["n": 4096, "iterations": 30, "holdBytes": 2_147_483_648])
            sampler.cancel()
            let out = result["output"] as? [String: Any] ?? [:]
            check(result["type"] as? String == "result" && (out["device"] as? String ?? "").contains("gpu"),
                  "MLX job ran on the GPU from the installed plugin",
                  String(format: "%@, %.2f s first job (incl. metallib load), %d progress events", out["device"] as? String ?? "?", Date().timeIntervalSince(t0), progress))
            check(peak > idle + 1_500_000_000, "host sees worker footprint", "idle \(gb(idle)) → peak \(gb(peak))")

            // 4. Warm second job: the process stays resident, so no relaunch cost
            let t1 = Date()
            let warm = await p.run(id: "j2", op: "demo.matmul", params: ["n": 4096, "iterations": 30])
            check(warm["type"] as? String == "result", "warm second job", String(format: "%.2f s", Date().timeIntervalSince(t1)))

            // 5. Cooperative cancel reaches the model loop
            let t2 = Date()
            let long = Task { await p.run(id: "j3", op: "demo.matmul", params: ["n": 8192, "iterations": 500]) }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            p.cancel("j3")
            let cancelled = await long.value
            check(cancelled["code"] as? String == "cancelled", "cancel", "\(cancelled["message"] ?? "?"), \(String(format: "%.2f s", Date().timeIntervalSince(t2))) total")

            // 6. Clean shutdown frees everything (the process is gone)
            p.shutdown()
            check(p.process.terminationStatus == 0, "shutdown exit 0")

            // 7. Hard kill mid-job: Gaea's last resort against a hung or runaway model
            let (k, _) = try await launch(plugin)
            _ = Task { await k.run(id: "k1", op: "demo.matmul", params: ["n": 8192, "iterations": 500, "holdBytes": 4_294_967_296]) }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let before = k.footprintBytes
            let t3 = Date()
            kill(k.pid, SIGKILL); k.process.waitUntilExit()
            check(k.process.terminationReason == .uncaughtSignal, "SIGKILL mid-job reclaims the worker",
                  "\(gb(before)) resident → exited in \(String(format: "%.0f ms", Date().timeIntervalSince(t3) * 1000))")
        } catch {
            check(false, "install/launch good plugin", "\(error)")
        }

        // 8. Refusals: wrong signer, broken seal, kernel launch requirement
        do { _ = try await installer.install(adhoc, quarantine: .asDownloaded); check(false, "ad-hoc plugin refused") }
        catch { check("\(error)".contains("signature"), "ad-hoc plugin refused", "\(error)") }
        do { _ = try await installer.install(tampered, quarantine: .asDownloaded); check(false, "tampered plugin refused") }
        catch { check("\(error)".contains("signature"), "tampered plugin refused", "\(error)") }

        // Bypass our own check and launch the ad-hoc worker directly: the kernel must refuse it.
        let adhocDir = installer.root.appendingPathComponent("\(adhoc.id)/\(adhoc.version)")
        let adhocPlugin = InstalledPlugin(entry: adhoc, bundleURL: adhocDir.appendingPathComponent(adhoc.bundleName))
        if FileManager.default.fileExists(atPath: adhocPlugin.executableURL.path) {
            do { let (p, _) = try await launch(adhocPlugin); p.process.terminate(); check(false, "launchRequirement blocks ad-hoc worker") }
            catch { check(true, "launchRequirement blocks ad-hoc worker at exec", "\(error.localizedDescription)") }
        }

        // 9. A zip the user fetched with a browser (quarantined): strip only after our check passes
        do {
            let (plugin, report) = try await installer.install(good, quarantine: .simulateBrowserThenStrip)
            let (p, _) = try await launch(plugin)
            let r = await p.run(id: "q1", op: "demo.matmul", params: ["n": 1024, "iterations": 3])
            p.shutdown()
            check(!report.bundleQuarantined && r["type"] as? String == "result", "browser-downloaded zip runs after verify-then-strip")
        } catch { check(false, "browser-downloaded zip after strip", "\(error)") }

        if includeQuarantineBlock {
            // Without notarization a quarantined worker is held by Gatekeeper (shows a dialog).
            do {
                let (plugin, _) = try await installer.install(good, quarantine: .simulateBrowser)
                let (p, _) = try await launch(plugin)
                p.shutdown(); check(true, "quarantined, un-notarized worker launched (notarized?)")
            } catch { check(true, "quarantined, un-notarized worker held by Gatekeeper (expected)", "\(error.localizedDescription)") }
        }

        // 10. Update check against a real GitHub repo
        do {
            let latest = try await UpdateChecker.latestRelease("ml-explore/mlx-swift")
            check(!latest.tag.isEmpty && latest.tag != "?", "GitHub latest-release lookup", "ml-explore/mlx-swift \(latest.tag), \(latest.assets.count) assets")
        } catch { check(false, "GitHub latest-release lookup", "\(error)") }

        print("\n\(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")")
        return failures == 0 ? 0 : 1
    }
}
