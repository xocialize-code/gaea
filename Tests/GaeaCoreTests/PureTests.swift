import Foundation
import GaeaProtocol
import Testing
@testable import GaeaCore

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Suite struct SemVerTests {
    @Test func ordersReleasesAndPrereleases() throws {
        let order = ["0.1.0-alpha", "0.1.0-alpha.2", "0.1.0-beta", "0.1.0", "v0.2.0", "0.10.0", "1.0.0"].map { SemVer($0)! }
        #expect(order == order.sorted())
        #expect(SemVer("v0.2.1")?.description == "0.2.1")
        #expect(SemVer("0.2") == nil)
        #expect(SemVer("latest") == nil)
    }
}

@Suite struct PluginRepositoryTests {
    @Test func readsTheSpellingsOperatorsUse() {
        for text in ["https://github.com/xocialize-code/gaea-plugin-demo", "https://github.com/xocialize-code/gaea-plugin-demo.git",
                     "https://github.com/xocialize-code/gaea-plugin-demo/", "xocialize-code/gaea-plugin-demo"] {
            #expect(PluginRepository(text)?.description == "xocialize-code/gaea-plugin-demo", "\(text)")
        }
        #expect(PluginRepository("https://gitlab.com/a/b") == nil)
        #expect(PluginRepository("https://github.com/a") == nil)
        #expect(PluginRepository("Xocialize-Code/Gaea-Plugin-Demo")!.matches(PluginRepository("xocialize-code/gaea-plugin-demo")!))
    }
}

/// A lane that declares an ActivationScaling on output pixels is charged per job (Klein's latent upscale, AB-T-0464): the
/// line through 11.2 GB at 1024² and 27.0 GB at 4096², as flux2-klein-swift 0.11.0 declares it.
@Suite struct WorkloadChargeTests {
    let model: PluginManifest.Model

    init() throws {
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repoRoot.appending(path: "examples/v1/manifest/z-image.json"))) as? [String: Any])
        var models = try #require(json["models"] as? [[String: Any]])
        var lanes = try #require(models[0]["lanes"] as? [[String: Any]])
        let small = 1024.0 * 1024, big = 4096.0 * 4096
        let slope = (27.0e9 - 11.2e9) / (big - small), base = 11.2e9 - slope * small
        for i in lanes.indices {
            var resolved = try #require(lanes[i]["resolved"] as? [String: Any])
            resolved["persistentBytes"] = 13_650_000_000
            resolved["peakTransientBytes"] = 11_200_000_000
            resolved["activationScaling"] = ["axis": "outputPixels", "baseBytes": UInt64(base), "bytesPerUnit": slope, "measuredCeiling": big]
            lanes[i]["resolved"] = resolved
        }
        models[0]["lanes"] = lanes
        json["models"] = models
        model = try JSONDecoder().decode(PluginManifest.self, from: JSONSerialization.data(withJSONObject: json)).models[0]
    }

    func size(_ w: Int, _ h: Int) -> [String: JSONValue] { ["size": ["width": .int(Int64(w)), "height": .int(Int64(h))]] }

    @Test func aJobIsChargedOnTheLineAtItsSize() throws {
        let lane = model.lanes[0]
        #expect(LaneChoice.workload(lane, params: size(2048, 1024)) == Double(2048 * 1024))
        let at1k = LaneChoice.transient(lane, params: size(1024, 1024)), at4k = LaneChoice.transient(lane, params: size(4096, 4096))
        #expect(abs(Double(at1k) - 11.2e9) < 1e6 && abs(Double(at4k) - 27.0e9) < 1e6)
        #expect(LaneChoice.transient(lane, params: size(2048, 2048)) > at1k)
        // No size (an edit the model sizes itself) and a lane with no scaling charge the scalar.
        #expect(LaneChoice.transient(lane, params: [:]) == 11_200_000_000)
        #expect(LaneChoice.need(lane, params: size(4096, 4096)) == 13_650_000_000 + at4k)
    }

    @Test func aLargeJobFallsBackOrIsRefusedWhereASmallOneFits() throws {
        // 30 GB free: every lane fits a 1024² job (24.85 GB) and none a 4096² one (40.65 GB).
        let small = try LaneChoice.choose(model, named: nil, preferred: nil, available: 30_000_000_000, params: size(1024, 1024))
        #expect(small.fellBackFrom == nil)
        #expect(throws: LaneChoice.Refusal.self) {
            try LaneChoice.choose(model, named: nil, preferred: nil, available: 30_000_000_000, params: size(4096, 4096))
        }
        #expect(throws: LaneChoice.Refusal.self) {
            try LaneChoice.choose(model, named: model.lanes[0].id, preferred: nil, available: 30_000_000_000, params: size(4096, 4096))
        }
    }

    @Test func aScaledLaneLearnsNoSinglePeak() throws {
        // The unscaled rule still raises a lane to what it held; a scaled lane is admitted on its line instead, so
        // learnPeak skips it (Scheduler.learnPeak). Here: the line already covers 4096²'s measured 40.7 GB within 1 GB.
        let lane = model.lanes[0]
        #expect(Double(LaneChoice.need(lane, params: size(4096, 4096))) > 40.6e9)
    }
}

/// A manifest from a plugin built on a newer engine contract must decode: AuK 0.1.0's speech-edit control lists
/// contract 1.59.0's operations (dereverberate, hum), which Gaea 1.1.0's engine (0.73.0) couldn't read (AB-T-0455).
@Suite struct ManifestDecodingTests {
    @Test func aukZeroOneZeroDecodes() throws {
        let data = try Data(contentsOf: repoRoot.appending(path: "Tests/Fixtures/manifests/auk-0.1.0.json"))
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        #expect(manifest.models.map(\.id) == ["auk-flash", "auk"])
    }

    @Test func everyExampleManifestDecodes() throws {
        let folder = repoRoot.appending(path: "examples/v1/manifest")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        #expect(!files.isEmpty)
        for file in files {
            #expect(throws: Never.self, "\(file.lastPathComponent)") { try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: file)) }
        }
    }
}

/// MEM-7 and G-23 on the z-image example manifest: int4 (39.9 GB), int8 (43 GB), bf16 (48.5 GB).
@Suite struct LaneChoiceTests {
    let model: PluginManifest.Model

    init() throws {
        let data = try Data(contentsOf: repoRoot.appending(path: "examples/v1/manifest/z-image.json"))
        model = try JSONDecoder().decode(PluginManifest.self, from: data).models[0]
    }

    @Test func theDefaultLaneWhenItFits() throws {
        let choice = try LaneChoice.choose(model, named: nil, preferred: nil, available: 100_000_000_000)
        #expect(choice.lane.id == "int4")
        #expect(choice.fellBackFrom == nil)
    }

    @Test func theLargestSmallerLaneThatFitsOtherwise() throws {
        let choice = try LaneChoice.choose(model, named: nil, preferred: "bf16", available: 45_000_000_000)
        #expect(choice.lane.id == "int8")
        #expect(choice.fellBackFrom?.id == "bf16")
    }

    @Test func aNamedLaneNeverFallsBack() {
        #expect(throws: LaneChoice.Refusal.namedDoesNotFit("bf16", need: 48_500_000_000, available: 45_000_000_000)) {
            try LaneChoice.choose(model, named: "bf16", preferred: nil, available: 45_000_000_000)
        }
        #expect(throws: LaneChoice.Refusal.unknownLane("fp8", model: "z-image-turbo")) {
            try LaneChoice.choose(model, named: "fp8", preferred: nil, available: 100_000_000_000)
        }
    }

    @Test func nothingFits() {
        #expect(throws: LaneChoice.Refusal.self) { try LaneChoice.choose(model, named: nil, preferred: nil, available: 30_000_000_000) }
    }
}
