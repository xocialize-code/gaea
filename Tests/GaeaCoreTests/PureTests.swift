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
