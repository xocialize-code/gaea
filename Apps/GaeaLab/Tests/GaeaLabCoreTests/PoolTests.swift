import Foundation
import MESCore
import Testing
@testable import GaeaLabCore

/// AB-T-0372: the pool's operations are every server's together, and the LoRA choices reach a request that names none.
@Suite struct PoolTests {
    static let license = License(spdx: "Apache-2.0", commercialUse: .yes)

    func descriptor(_ operation: String, models: [ModelOffer]) -> Descriptor {
        Descriptor(operation: operation, profile: "image", profileVersion: "0.1", title: operation, inputs: [],
                   params: .object([:]), outputs: [], qualityTiers: [.standard], models: models)
    }

    func model(_ id: String, adapters: [AdapterOffer]? = nil) -> ModelOffer {
        var offer = ModelOffer(id: id, title: id, license: Self.license, qualityTiers: [.standard])
        offer.adapters = adapters
        return offer
    }

    @Test func operationsAreEveryServersWithEveryModel() {
        let a = OperationsList(operations: [descriptor("image.generate", models: [model("z-image-turbo")]),
                                            descriptor("image.upscale", models: [model("nerve-upscale")])], etag: "a")
        let b = OperationsList(operations: [descriptor("image.generate", models: [model("qwen-image-flash"), model("z-image-turbo")])],
                               etag: "b")
        let merged = EnginePool.merged([a, b])
        #expect(merged.operations.map(\.operation) == ["image.generate", "image.upscale"])
        #expect(merged.operations[0].models.map(\.id) == ["z-image-turbo", "qwen-image-flash"])   // each model once
        #expect(merged.etag == "a+b")
    }

    @Test func choicesReachARequestThatNamesNone() {
        let choices = AdapterChoices()
        choices.choose("qwen-image:martha", strength: 0.8, on: true, for: "image.generate")
        choices.choose("qwen-image:dott4k", strength: nil, on: true, for: "image.generate")
        choices.choose("qwen-image:dott4k", strength: nil, on: false, for: "image.generate")
        #expect(choices.provider(JobRequest(operation: "image.generate")) == [AdapterRequest(id: "qwen-image:martha", strength: 0.8)])
        #expect(choices.provider(JobRequest(operation: "image.edit")) == nil)
    }

    @Test func offeredAdaptersFollowTheModel() {
        let lora = AdapterOffer(id: "qwen-image:martha", title: "Martha", strength: .init(min: 0, max: 2, defaultValue: 1),
                                license: Self.license)
        let d = descriptor("image.generate", models: [model("qwen-image-flash", adapters: [lora]), model("z-image-turbo")])
        #expect(AdapterChoices.offered(by: d, model: nil).map(\.model) == ["qwen-image-flash"])
        #expect(AdapterChoices.offered(by: d, model: "z-image-turbo").isEmpty)
    }

    @Test func uploadsWaitForTheServer() async throws {
        let pool = EnginePool()
        let file = FileManager.default.temporaryDirectory.appending(path: "lab-pool-\(UUID().uuidString).png")
        try Data([1, 2, 3]).write(to: file)
        let upload = try await pool.upload(contentsOf: file, mediaType: "image/png")
        #expect(upload.uploadID.hasPrefix(EnginePool.pendingPrefix) && upload.bytes == 3)
    }
}
