import Foundation
import MESCore
import Testing
@testable import GaeaCore

/// Which models fill, extend and erase are offered with (AB-A-0267): only what this server can finish.
@Suite struct FillOfferTests {
    func offer(_ id: String, tiers: [QualityTier] = [.standard], namedOnly: Bool = false) -> ModelOffer {
        var offer = ModelOffer(id: id, title: id, license: License(spdx: "Apache-2.0", commercialUse: .yes), memoryClass: .large,
                               speedClass: .fast, qualityTiers: tiers)
        offer.namedOnly = namedOnly ? true : nil
        return offer
    }

    func descriptor(_ operation: String, _ models: [ModelOffer]) -> Descriptor {
        Descriptor(operation: operation, profile: ImageProfile.id, profileVersion: ImageProfile.version, title: operation, summary: nil,
                   inputs: [], params: ["type": "object"], outputs: [],
                   limits: nil, qualityTiers: QualityTier.allCases, models: models, remote: .init(possible: false))
    }

    @Test func aRegeneratingModelIsNotOfferedOnFillExtendOrErase() {
        let models = [offer("lama-inpaint", tiers: QualityTier.allCases), offer("klein-4b", tiers: [.draft]), offer("z-image-turbo", namedOnly: true)]
        for operation in ["image.fill", "image.extend", "image.erase"] {
            let narrowed = GaeaEngine.finishable(descriptor(operation, models), regenerators: ["z-image-turbo", "z-image"], hasInpainter: true)
            #expect(narrowed?.models.map(\.id) == ["lama-inpaint", "klein-4b"], "\(operation)")
        }
        // Its own operations keep it.
        let edit = GaeaEngine.finishable(descriptor("image.edit", models), regenerators: ["z-image-turbo"], hasInpainter: false)
        #expect(edit?.models.count == 3)
    }

    @Test func withOnlyRegeneratorsTheOperationIsNotOffered() {
        let models = [offer("z-image", namedOnly: true), offer("z-image-turbo", namedOnly: true)]
        #expect(GaeaEngine.finishable(descriptor("image.fill", models), regenerators: ["z-image", "z-image-turbo"], hasInpainter: false) == nil)
        #expect(GaeaEngine.finishable(descriptor("image.extend", models), regenerators: ["z-image", "z-image-turbo"], hasInpainter: false) == nil)
    }

    @Test func extendNeedsTheInpainterAndFillWithAnEditorDoesNot() {
        let klein = [offer("klein-4b", tiers: [.draft, .standard])]
        #expect(GaeaEngine.finishable(descriptor("image.extend", klein), regenerators: [], hasInpainter: false) == nil)
        #expect(GaeaEngine.finishable(descriptor("image.extend", klein), regenerators: [], hasInpainter: true)?.models.count == 1)
        let fill = GaeaEngine.finishable(descriptor("image.fill", klein), regenerators: [], hasInpainter: false)
        #expect(fill?.models.map(\.id) == ["klein-4b"])
        // The tiers follow the models left.
        #expect(fill?.qualityTiers == [.draft, .standard])
    }

    @Test func theFallbackErrorNamesWhatIsMissing() {
        #expect(GaeaModelHost.noDefault("image.fill").contains("gaea-plugin-forge"))
        #expect(GaeaModelHost.noDefault("image.describe") == "No plugin model offers image.describe without being named.")
    }
}
