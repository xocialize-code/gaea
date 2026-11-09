import Foundation
import GaeaProtocol
import Testing
@testable import GaeaCore

/// What a client and an operator see the first time a model is used (AB-A-0259): the preparing messages, the weights a
/// lane would download, and the idle-unload setting.
@Suite struct FirstUseTests {
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "gaea-first-use-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func preparingMessagesNameTheDownloadAndTheLoad() {
        #expect(GaeaEngine.preparingMessage(["stage": "downloading", "fraction": 0.2, "bytes_done": 4_200_000_000, "bytes_total": 19_000_000_000])
            == "downloading the weights (first use): 4.2 of 19.0 GB")
        #expect(GaeaEngine.preparingMessage(["stage": "downloading", "fraction": 0.2]) == "downloading the weights (first use)")
        #expect(GaeaEngine.preparingMessage(["stage": "loading", "message": "loading kokoro-82m (bf16)"]) == "loading kokoro-82m (bf16)")
        #expect(GaeaEngine.preparingMessage(["stage": "loading"]) == "loading the model")
        #expect(GaeaEngine.preparingMessage(["stage": "denoise", "step": 3]) == nil)
    }

    @Test func aLaneWhoseWeightsAreNotUnderTheRootIsNamed() throws {
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: repoRoot.appending(path: "examples/v1/manifest/z-image.json")))
        let lane = manifest.models[0].lanes[0]
        let repos = lane.resolved.weightSources.map(\.repo)
        #expect(!repos.isEmpty)
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(GaeaHost.missingWeights(lane, root: root) == repos.uniqued())
        // A snapshot folder in the MLXEngine store's layout counts as there.
        for repo in repos {
            try FileManager.default.createDirectory(at: root.appending(path: "models--" + repo.replacingOccurrences(of: "/", with: "--")),
                                                    withIntermediateDirectories: true)
        }
        #expect(GaeaHost.missingWeights(lane, root: root).isEmpty)
    }

    @Test func theIdleTimeoutIsAnOperatorSettingALaunchOptionOverrides() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = try TrustTests().manager(dir, ownTeamTrusted: true)
        let database = await manager.database
        let paths = await manager.paths
        let scheduler = Scheduler(manager: manager, database: database, paths: paths, log: await manager.log)
        #expect(await scheduler.idleSeconds == 900)
        try await scheduler.setIdleSeconds(120)
        #expect(await scheduler.idleSeconds == 120)
        // Kept: a scheduler built later reads it.
        let next = Scheduler(manager: manager, database: database, paths: paths, log: await manager.log)
        #expect(await next.idleSeconds == 120)
        // A launch option wins for that launch, and the setting is still stored for the next.
        let launched = Scheduler(manager: manager, database: database, paths: paths, log: await manager.log, idleTimeout: .seconds(45))
        #expect(await launched.idleSeconds == 45)
        try await launched.setIdleSeconds(300)
        #expect(await launched.idleSeconds == 45)
        #expect(try database.setting(Scheduler.idleSetting) == "300")
        try await scheduler.setIdleSeconds(nil)
        #expect(await scheduler.idleSeconds == 900)
    }
}
