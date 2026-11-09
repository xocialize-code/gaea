import Foundation
import GaeaProtocol
import MESCore
import Testing
@testable import GaeaCore

/// What an operator narrows on a server (Gaea 1.5.0): the budget, lanes switched off, caps on offers.
@Suite struct OperatorControlsTests {
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "gaea-controls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func zImage() throws -> PluginManifest {
        try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: repoRoot.appending(path: "examples/v1/manifest/z-image.json")))
    }

    @Test func capsNarrowBothLimitsAndNeverWiden() throws {
        let manifestOffer = PluginManifest.Offer(operation: "image.generate", profile: "image", model: ["id": "k", "limits": ["max_megapixels": 16.78, "max_count": 4]],
                                                 limits: PluginManifest.Limits(maxPixels: 16_777_216, sizeMultiple: 16))
        let offer = try JSONDecoder().decode(ModelOffer.self, from: JSONEncoder().encode(
            ["id": "k", "title": "K", "license": ["spdx": "Apache-2.0", "commercial_use": true], "memory_class": "large", "speed_class": "fast",
             "quality_tiers": ["standard"], "limits": ["max_megapixels": 16.78, "max_count": 4]] as MESValue))
        let (m, o) = OperatorControls.applying(["max_megapixels": 4.2, "max_count": 8, "max_side": 2048, "max_faces": 50_000], to: manifestOffer, offer: offer)
        #expect(o.limits?.maxMegapixels == 4.2)
        #expect(o.limits?.maxCount == 4, "a cap never widens the plugin's own limit")
        #expect(o.limits?.maxWidth == 2048 && o.limits?.maxHeight == 2048)
        #expect(o.limits?.profile["max_faces"] == 50_000)
        #expect(m.limits?.maxPixels == 4_200_000 && m.limits?.maxSide == 2048 && m.limits?.sizeMultiple == 16)
        #expect(m.model["limits"]?["max_megapixels"]?.doubleValue == 4.2)
        // No caps: untouched.
        let (same, sameOffer) = OperatorControls.applying([:], to: manifestOffer, offer: offer)
        #expect(same.limits == manifestOffer.limits && sameOffer.limits == offer.limits)
    }

    @Test func lanesOffMoveTheDefaultAndAllOffLeavesNone() throws {
        let model = try zImage().models[0]
        let defaultLane = model.lanes.first { $0.default }?.id ?? ""
        let off = OperatorControls.applying(lanesOff: [defaultLane], to: model)
        #expect(!off.lanes.contains { $0.id == defaultLane })
        #expect(off.lanes.filter(\.default).count == 1 && off.lanes.first?.default == true)
        #expect(OperatorControls.applying(lanesOff: Set(model.lanes.map(\.id)), to: model).lanes.isEmpty)
    }

    @Test func settingsAreKeptPerModel() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = try TrustTests().manager(dir, ownTeamTrusted: true)
        let controls = OperatorControls(database: await manager.database)
        try controls.setLane(plugin: "p", model: "m", lane: "bf16", on: false)
        try controls.setLane(plugin: "p", model: "m", lane: "int8", on: false)
        try controls.setLane(plugin: "p", model: "m", lane: "int8", on: true)
        #expect(controls.lanesOff(plugin: "p", model: "m") == ["bf16"])
        #expect(controls.lanesOff(plugin: "p", model: "other").isEmpty)
        try controls.setCap(plugin: "p", model: "m", field: "max_megapixels", value: 4.2)
        try controls.setCap(plugin: "p", model: "m", field: "max_duration_s", value: 5)
        try controls.setCap(plugin: "p", model: "m", field: "max_duration_s", value: nil)
        #expect(controls.caps(plugin: "p", model: "m") == ["max_megapixels": 4.2])
    }

    @Test func theBudgetIsKeptAndAppliesNowUnlessALaunchSetIt() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = try TrustTests().manager(dir, ownTeamTrusted: true)
        let database = await manager.database
        let paths = await manager.paths
        let scheduler = Scheduler(manager: manager, database: database, paths: paths, log: await manager.log)
        #expect(scheduler.budgetBytes == Scheduler.defaultBudget)
        try await scheduler.setBudget(40_000_000_000)
        #expect(scheduler.budgetBytes == 40_000_000_000)
        #expect(await scheduler.policy.budgetBytes == 40_000_000_000)
        #expect(await scheduler.budgetSource == "set by the operator")
        // Kept for the next launch.
        let next = Scheduler(manager: manager, database: database, paths: paths, log: await manager.log)
        #expect(next.budgetBytes == 40_000_000_000)
        // --budget-bytes wins for its launch; the setting is still kept.
        let launched = Scheduler(manager: manager, database: database, paths: paths, log: await manager.log, budgetBytes: 20_000_000_000)
        try await launched.setBudget(30_000_000_000)
        #expect(launched.budgetBytes == 20_000_000_000)
        #expect(OperatorControls(database: database).storedBudget == 30_000_000_000)
        try await scheduler.setBudget(nil)
        #expect(scheduler.budgetBytes == Scheduler.defaultBudget)
    }

    @Test func aNamedImageModelsCapRefusesALargerSize() throws {
        let request = try JSONDecoder().decode(JobRequest.self, from: Data(#"{"operation":"image.generate","model":"klein-4b","inputs":{"prompt":"x"},"params":{"size":{"width":4096,"height":4096}}}"#.utf8))
        let capped = Descriptor.Limits(maxMegapixels: 4.2)
        #expect(GaeaEngine.sizeRefusal(request, limits: capped, title: "Klein")?.code == MESErrorCode.outOfLimits.rawValue)
        #expect(GaeaEngine.sizeRefusal(request, limits: Descriptor.Limits(maxMegapixels: 16.78), title: "Klein") == nil)
        #expect(GaeaEngine.sizeRefusal(request, limits: Descriptor.Limits(maxWidth: 2048), title: "Klein")?.code == MESErrorCode.outOfLimits.rawValue)
        #expect(GaeaEngine.sizeRefusal(request, limits: nil, title: "Klein") == nil)
        let merged = GaeaEngine.narrower(Descriptor.Limits(maxMegapixels: 16.78, maxCount: 4), Descriptor.Limits(maxMegapixels: 4.2, profile: ["max_faces": 10]))
        #expect(merged.maxMegapixels == 4.2 && merged.maxCount == 4 && merged.profile["max_faces"] == 10)
    }
}
