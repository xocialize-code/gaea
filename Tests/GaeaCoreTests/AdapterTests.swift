import Foundation
import GaeaProtocol
import MESCore
import MESEngineCore
import PixelAgencyNormalizer
import Testing
@testable import GaeaCore

/// AB-T-0378: adapters a plugin ships and adapters the operator adds by Hugging Face URL (GPP-1 §3.3, §4.3, §4.8).
@Suite struct AdapterTests {
    static let revision = "a60485ca35e32b69c2d71930c2ef3d3745271411"

    @Test func hubURLsParse() {
        let plain = HuggingFaceAdapter.Reference("https://huggingface.co/xocialize/qwen-image-flash-loras")
        #expect(plain?.repo == "xocialize/qwen-image-flash-loras" && plain?.revision == nil && plain?.file == nil)
        let blob = HuggingFaceAdapter.Reference("https://huggingface.co/xocialize/qwen-image-flash-loras/blob/main/loras/martha.safetensors")
        #expect(blob?.repo == "xocialize/qwen-image-flash-loras" && blob?.revision == "main" && blob?.file == "loras/martha.safetensors")
        #expect(HuggingFaceAdapter.Reference("owner/repo")?.repo == "owner/repo")
        #expect(HuggingFaceAdapter.Reference("https://github.com/owner/repo") == nil)
        #expect(HuggingFaceAdapter.Reference("https://huggingface.co/owner") == nil)
    }

    @Test func theFormatComesFromTheTensorNames() {
        #expect(HuggingFaceAdapter.format(tensorNames: ["transformer.transformer_blocks.0.attn.to_q.lora_A.weight"]) == "diffusers-peft")
        #expect(HuggingFaceAdapter.format(tensorNames: ["lora_unet_transformer_blocks_0_attn_to_q.lora_down.weight", "x.alpha"]) == "kohya")
        #expect(HuggingFaceAdapter.format(tensorNames: ["transformer.blocks.0.attn.to_q.lora.down.weight"]) == "diffusers-legacy")
        #expect(HuggingFaceAdapter.format(tensorNames: ["diffusion_model.double_blocks.0.img_attn.qkv.lora_A.weight"]) == "bfl-fused")
        #expect(HuggingFaceAdapter.format(tensorNames: ["model.weight"]) == nil)
    }

    @Test func hubLicencesMapToSPDXAndCommercialUse() {
        #expect(HuggingFaceAdapter.license(hub: "apache-2.0", name: nil) == ("Apache-2.0", "allowed"))
        #expect(HuggingFaceAdapter.license(hub: "creativeml-openrail-m", name: nil) == ("CreativeML-OpenRAIL-M", "conditional"))
        #expect(HuggingFaceAdapter.license(hub: "cc-by-nc-4.0", name: nil) == ("CC-BY-NC-4.0", "prohibited"))
        #expect(HuggingFaceAdapter.license(hub: "other", name: "my licence") == ("NOASSERTION", "unknown"))
        #expect(HuggingFaceAdapter.license(hub: nil, name: nil) == ("NOASSERTION", "unknown"))
    }

    /// Z-Image's example manifest, its generate offer given adapter support, one shipped adapter, and its edit offer none.
    func routes(shipped: Bool = true) throws -> [PluginRoute] {
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repoRoot.appending(path: "examples/v1/manifest/z-image.json"))) as? [String: Any])
        var offers = try #require(json["offers"] as? [[String: Any]])
        offers[0]["adapter_support"] = ["base_model": "z-image", "formats": ["diffusers-peft"], "kinds": ["plain"], "max_count": 4,
                                        "strength": ["min": 0, "max": 2]]
        if shipped {
            var model = try #require(offers[0]["model"] as? [String: Any])
            model["adapters"] = [["id": "z-image:ink", "title": "Ink", "kind": "plain", "strength": ["min": 0, "max": 1.5, "default": 0.8],
                                  "license": ["spdx": "Apache-2.0", "commercial_use": true]]]
            offers[0]["model"] = model
            offers[0]["adapters_meta"] = ["z-image:ink": ["trigger": "inkwash", "status": "verified", "format": "diffusers-peft",
                                                          "source": ["repo": "o/ink", "revision": Self.revision, "file": "ink.safetensors",
                                                                     "sha256": String(repeating: "a", count: 64), "bytes": 1234]]]
        }
        json["offers"] = offers
        let data = try JSONSerialization.data(withJSONObject: json)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        let plugin = InstalledPlugin(id: manifest.id, version: manifest.version, title: manifest.title, repo: manifest.repo, enabled: true,
                                     bundle: URL(fileURLWithPath: "/nonexistent"), manifest: manifest, manifestData: data)
        return try manifest.offers.map { offer in
            let id = try #require(offer.modelID)
            let model = try #require(plugin.model(id))
            let mes = try JSONDecoder().decode(ModelOffer.self, from: JSONEncoder().encode(offer.model))
            return PluginRoute(plugin: plugin, model: model, manifestOffer: offer, offer: mes)
        }
    }

    func registration(_ id: String, model: String = "z-image-turbo", format: String = "diffusers-peft",
                      license: String = "NOASSERTION", use: String = "unknown") -> GaeaDatabase.AdapterRow {
        GaeaDatabase.AdapterRow(id: id, modelID: model, title: id, format: format, repo: "o/\(id)", revision: Self.revision,
                                file: "\(id).safetensors", sha256: String(repeating: "b", count: 64), bytes: 99, trigger: "tok",
                                license: license, commercialUse: use, strengthMin: 0, strengthMax: 2)
    }

    @Test func shippedAndRegisteredAdaptersGoWhereTheOfferTakesThem() throws {
        let routes = try routes()
        let adapters = PluginOffers.adapters(routes, registrations: [
            registration("z-image:mine"),                                   // taken by generate
            registration("z-image:kohya", format: "kohya"),                 // a format no offer takes
            registration("qwen-image:other", model: "qwen-image-flash"),    // another model's
        ])
        #expect(adapters.map(\.card.id) == ["z-image:ink", "z-image:mine"])
        let ink = try #require(adapters.first)
        #expect(ink.card.capabilities == [.textToImage] && ink.card.trigger == "inkwash" && ink.card.strengthMax == 1.5)
        #expect(!ink.registered && ink.source.revision == Self.revision && !Adapters.isOptIn(ink.card))
        let mine = adapters[1]
        #expect(mine.registered && mine.card.status == "operator" && Adapters.isOptIn(mine.card))  // NOASSERTION: opt-in

        // The edit offer declares no adapter_support: nothing applies to it.
        #expect(PluginOffers.adapters([routes[1]], registrations: [registration("z-image:mine")]).isEmpty)
        #expect(GaeaModelHost.adapterSupport(routes[0])?.maxCount == 4 && GaeaModelHost.adapterSupport(routes[1]) == nil)

        // The card the normalizer offers from.
        let card = GaeaModelHost.card(routes[0], all: routes, adapters: adapters)
        #expect(card.adapters.map(\.id) == ["z-image:ink", "z-image:mine"])
    }

    @Test func aRunItemCarriesWhatTheWorkerFetches() throws {
        let adapter = try #require(PluginOffers.adapters(try routes(), registrations: []).first)
        let item = adapter.runItem(strength: 0.6, inputs: ["pose": "/spool/adapter0.pose-0.png"])
        #expect(item["id"]?.stringValue == "z-image:ink" && item["strength"]?.doubleValue == 0.6)
        #expect(item["kind"]?.stringValue == "plain" && item["format"]?.stringValue == "diffusers-peft")
        #expect(item["source"]?["revision"]?.stringValue == Self.revision && item["source"]?["bytes"]?.intValue == 1234)
        #expect(item["inputs"]?["pose"]?.stringValue == "/spool/adapter0.pose-0.png")
    }

    @Test func registrationsPersistAndRemovalForgetsTheirEnablement() throws {
        let db = try GaeaDatabase()
        try db.saveAdapter(registration("z-image:mine", license: "Apache-2.0", use: "allowed"))
        #expect(try db.adapter("z-image:mine")?.repo == "o/z-image:mine")
        #expect(try db.adapters().count == 1)
        try db.deleteAdapter("z-image:mine")
        #expect(try db.adapters().isEmpty)
    }

    /// The hub's answer for an adapter v0.9.1 pins: the same revision, file, sha256 and size. Hits huggingface.co.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GAEA_LIVE_HF"] == "1"))
    func theHubGivesTheSamePinsAsV091() async throws {
        let reference = try #require(HuggingFaceAdapter.Reference(
            "https://huggingface.co/xocialize/qwen-image-flash-loras/blob/\(Self.revision)/loras/peter-chan-s-concept-art.safetensors"))
        let hub = try await HuggingFaceAdapter.resolve(reference)
        #expect(hub.revision == Self.revision)
        #expect(hub.sha256 == "5d5a7d2fa1b83f6aa9d6dfb7dc8178138b677ff5249aac30e1a9a6dce9dd3ee0")
        #expect(hub.bytes == 590_058_848)
        #expect(hub.format == "diffusers-peft")
        print("hub: \(hub)")
    }
}
