import Foundation
@testable import GaeaCore
import GaeaProtocol
import MESCore
import MESEngineCore
import Testing

/// `image.locate` (Image §3.4, RFC 0010; AB-T-0483): an Image operation the normalizer has no table entry for, served
/// from MESKit's table with each plugin offer run as itself.
@Suite("Locate")
struct LocateTests {
    let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Two image.locate offers on the z-image manifest's model: one returns up to 16 scored boxes, one a single box
    /// without a score, named-only.
    func routes() throws -> [PluginRoute] {
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repoRoot.appending(path: "examples/v1/manifest/z-image.json"))) as? [String: Any])
        let base = try #require((json["offers"] as? [[String: Any]])?.first)
        var model = try #require(base["model"] as? [String: Any])
        model["id"] = "z-image-turbo"
        model["supports"] = ["seed": false]
        model["limits"] = ["max_count": 16]
        model["default"] = nil
        var many = base
        many["operation"] = "image.locate"
        many["model"] = model
        many["params"] = nil
        many["limits"] = nil
        many["defaults"] = nil
        many["adapter_support"] = nil
        many["adapters_meta"] = nil
        var pointer = many
        var other = model
        other["id"] = "z-image-base"
        other["supports"] = ["scores": false]
        other["limits"] = ["max_count": 1]
        other["named_only"] = true
        pointer["model"] = other
        var models = try #require(json["models"] as? [[String: Any]])
        var second = models[0]
        second["id"] = "z-image-base"
        models.append(second)
        json["models"] = models
        json["offers"] = [many, pointer]
        let data = try JSONSerialization.data(withJSONObject: json)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        let plugin = InstalledPlugin(id: manifest.id, version: manifest.version, title: manifest.title, repo: manifest.repo, enabled: true, trusted: true,
                                     bundle: URL(fileURLWithPath: "/nonexistent"), manifest: manifest, manifestData: data)
        return try manifest.offers.map { offer in
            let id = try #require(offer.modelID)
            let model = try #require(plugin.model(id))
            let mes = try JSONDecoder().decode(ModelOffer.self, from: JSONEncoder().encode(offer.model))
            return PluginRoute(plugin: plugin, model: model, manifestOffer: offer, offer: mes)
        }
    }

    @Test func theDescriptorIsMESKitsTableWithTheOffersLimits() throws {
        let descriptor = try #require(GaeaEngine.ownImageDescriptor(ImageProfile.locate, routes: try routes()))
        #expect(descriptor.profile == ImageProfile.id && descriptor.title == "Locate")
        #expect(descriptor.inputs.map(\.name) == ["image", "prompt"] && descriptor.inputs.allSatisfy(\.required))
        #expect(descriptor.inputs[0].kind == .image && descriptor.inputs[0].max == 1 && descriptor.inputs[1].kind == .text)
        #expect(descriptor.outputs.map(\.name) == ["boxes"] && descriptor.outputs[0].kind == .data)
        // The most boxes any offer returns is the descriptor's limit and `count`'s maximum.
        #expect(descriptor.limits?.maxCount == 16)
        let count = descriptor.params["properties"]?["count"]
        #expect(count?["maximum"]?.numberValue == 16 && count?["minimum"]?.numberValue == 1 && count?["default"]?.numberValue == 1)
        #expect(descriptor.params["properties"]?["seed"] != nil)
        // The first offer that isn't named-only is the default; a named-only one never is.
        #expect(descriptor.models.map(\.id) == ["z-image-turbo", "z-image-base"])
        #expect(descriptor.models[0].isDefault == true && descriptor.models[1].isDefault == nil && descriptor.models[1].namedOnly == true)
        #expect(descriptor.models[1].limits?.maxCount == 1)
    }

    @Test func onlyLocateIsServedHereAndOnlyWhenOffered() throws {
        #expect(GaeaEngine.ownImageOperations == [ImageProfile.locate])
        #expect(GaeaEngine.ownImageDescriptor(ImageProfile.locate, routes: []) == nil)
        #expect(GaeaEngine.ownImageDescriptor("image.nonesuch", routes: try routes()) == nil)
    }

    @Test func aRequestIsCheckedByTheImageProfilesRules() throws {
        let descriptor = try #require(GaeaEngine.ownImageDescriptor(ImageProfile.locate, routes: try routes()))
        let inputs: [String: RequestInput] = ["image": .one(.inline(mediaType: "image/png", data: Data())),
                                            "prompt": .one(.inline(mediaType: "text/plain", data: Data("the fox".utf8)))]
        try ImageProfileRules.validate(JobRequest(operation: ImageProfile.locate, inputs: inputs, params: ["count": 2]), descriptor: descriptor)
        // What any Image request can't do, it can't do here either.
        let both = JobRequest(operation: ImageProfile.locate, inputs: inputs,
                              params: ["size": ["width": 512, "height": 512], "aspect": "1:1"])
        #expect(throws: MESError.self) { try ImageProfileRules.validate(both, descriptor: descriptor) }
    }
}
