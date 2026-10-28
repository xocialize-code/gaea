import Foundation
import GaeaProtocol
import Testing
@testable import GaeaCore

/// The H side of GPP-1 against real processes.
@Suite(.serialized) struct WorkerProcessTests {
    static let demo = repoRoot.deletingLastPathComponent().appending(path: "gaea-plugin-demo/dist/demo.gaeaplugin")

    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "gaea-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The spike's harness fix: a worker the kernel refuses (here Apple's own `/bin/sleep`, which isn't signed by our
    /// team) is a SIGKILL at exec, and the launch fails at once through `terminationHandler`, not after the hello wait.
    @Test func aRefusedLaunchFailsAtOnce() async throws {
        let dir = try scratch()
        let bundle = dir.appending(path: "refused.gaeaplugin")
        try FileManager.default.createDirectory(at: bundle.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: bundle.appending(path: "Contents/MacOS/worker"))
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: repoRoot.appending(path: "examples/v1/manifest/demo.json")))
        var patched = manifest
        patched.executable = "worker"
        let worker = WorkerProcess(pluginID: manifest.id, version: manifest.version, bundle: bundle, manifest: patched,
                                   manifestData: Data(), cacheRoot: dir, log: dir.appending(path: "w.log"), sessions: nil)
        let clock = ContinuousClock()
        let began = clock.now
        await #expect(throws: WorkerFailure.self) { try await worker.start(helloTimeout: .seconds(10)) }
        let elapsed = clock.now - began
        #expect(elapsed < .seconds(3), "took \(elapsed): it waited out the hello timeout")
        #expect(!worker.isRunning)
    }

    /// A whole session with the demo plugin's signed bundle, when it is built next door: launch under the launch
    /// requirement, hello against the manifest, configure, prepare, a run, a cancelled run, memory, and the ladder.
    /// The recorded transcript passes `tools/validate.py --transcript`.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: demo.path)))
    func aSessionWithTheDemoPlugin() async throws {
        let dir = try scratch()
        let manifestData = try Data(contentsOf: Self.demo.appending(path: "Contents/Resources/manifest.json"))
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: manifestData)
        _ = try PluginVerifier.verify(Self.demo)
        let worker = WorkerProcess(pluginID: manifest.id, version: manifest.version, bundle: Self.demo, manifest: manifest,
                                   manifestData: manifestData, cacheRoot: dir, log: dir.appending(path: "w.log"), sessions: dir)
        _ = try await worker.start()
        try await worker.configure(budget: WorkerBudgetWire(ceilingBytes: 8_000_000_000), modelsRoot: dir, cacheRoot: dir, settings: [:])
        try await worker.prepare(model: "demo-matmul", lane: "fp32")
        let out = dir.appending(path: "spool/job_a/out")
        let result = try await worker.request("run", ["job": "job_a", "operation": "x-gaea.demo.matmul", "model": "demo-matmul",
                                                      "lane": "fp32", "inputs": [:], "params": ["n": 1024, "iterations": 3],
                                                      "output_dir": .string(out.path)], finals: ["result"])
        #expect(result["outputs"]?.arrayValue?.first?["value"]?["device"]?.stringValue?.contains("gpu") == true)

        let long = Task {
            try await worker.request("run", ["job": "job_b", "operation": "x-gaea.demo.matmul", "model": "demo-matmul", "lane": "fp32",
                                             "inputs": [:], "params": ["n": 4096, "iterations": 1000],
                                             "output_dir": .string(dir.appending(path: "spool/job_b/out").path)], finals: ["result"])
        }
        try await Task.sleep(for: .milliseconds(300))
        worker.cancel(job: "job_b")
        await #expect { _ = try await long.value } throws: { ($0 as? WorkerFailure)?.code == "cancelled" }
        let report = try await worker.memoryQuery()
        #expect(report?.budgetBytes == 8_000_000_000)
        #expect((worker.physFootprint ?? 0) > 0)

        let rung = await worker.stop(unloading: ["demo-matmul"])
        #expect(rung == .shutdown)
        #expect(!worker.isRunning)

        let transcript = try #require(worker.transcriptURL)
        let validate = Process()
        validate.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        validate.arguments = [repoRoot.appending(path: "tools/validate.py").path, "--transcript", transcript.path]
        try validate.run()
        validate.waitUntilExit()
        #expect(validate.terminationStatus == 0, "validate.py rejected \(transcript.path)")
    }

    /// A tampered bundle is refused before anything runs; an ad-hoc one too.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: demo.path)))
    func tamperedAndAdHocBundlesAreRefused() throws {
        let dir = try scratch()
        let tampered = dir.appending(path: "tampered.gaeaplugin")
        try FileManager.default.copyItem(at: Self.demo, to: tampered)
        let manifest = tampered.appending(path: "Contents/Resources/manifest.json")
        try (Data(contentsOf: manifest) + Data(" ".utf8)).write(to: manifest)
        #expect { try PluginVerifier.verify(tampered) } throws: {
            if case .invalid = $0 as? PluginVerifier.Refusal { true } else { false }
        }

        let adhoc = dir.appending(path: "adhoc.gaeaplugin")
        try FileManager.default.copyItem(at: Self.demo, to: adhoc)
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--deep", "--sign", "-", adhoc.path]
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        #expect { try PluginVerifier.verify(adhoc) } throws: {
            if case .notDeveloperID = $0 as? PluginVerifier.Refusal { true } else { false }
        }
        #expect(try PluginVerifier.verify(Self.demo).team == GPP.trustedTeam)
    }
}
