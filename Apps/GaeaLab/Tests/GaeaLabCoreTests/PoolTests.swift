import Foundation
import MESClientKit
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

    /// AB-T-0395: an asset is kept on every server and becomes the chosen one's own id; voices come from the server that
    /// lists them, and so do their samples.
    @Test func assetsAreOnEveryServerAndVoicesComeFromTheirOwn() async throws {
        let a = FakeServer(id: "a", voices: []), b = FakeServer(id: "b", voices: ["ryan"])
        let pool = EnginePool()
        await pool.setMembers([.init(id: "a", name: "A", connection: a), .init(id: "b", name: "B", connection: b)])
        let file = FileManager.default.temporaryDirectory.appending(path: "lab-asset-\(UUID().uuidString).wav")
        try Data([1, 2, 3]).write(to: file)
        let asset = try await pool.createAsset(contentsOf: file, mediaType: "audio/wav", ttlSeconds: 3600)
        #expect(asset.assetID.hasPrefix(EnginePool.assetPrefix))
        #expect(try await pool.assets().map(\.assetID) == [asset.assetID])
        #expect(try pool.asset(.one(.asset(asset.assetID)), on: "b") == .one(.asset("b-asset-1")))
        #expect(try pool.asset(.one(.upload("u1")), on: "b") == .one(.upload("u1")))
        let voices = try await pool.voices(operation: "audio.speak", model: "qwen3-tts")
        #expect(voices.voices.map(\.id) == ["ryan"])
        #expect(try await pool.sample(of: voices.voices[0]) == Data("b:ryan".utf8))
        try await pool.deleteAsset(asset.assetID)
        #expect(a.deleted == ["a-asset-1"] && b.deleted == ["b-asset-1"])
        #expect(try await pool.assets().isEmpty)
    }
}

/// A server that keeps assets and lists the voices it is given; everything else is unused.
final class FakeServer: EngineConnection, @unchecked Sendable {
    let id: String
    let voiceIDs: [String]
    var deleted: [String] = []
    init(id: String, voices: [String]) { self.id = id; self.voiceIDs = voices }

    func createAsset(contentsOf file: URL, mediaType: String, ttlSeconds: Int) async throws -> Asset {
        Asset(assetID: "\(id)-asset-1", mediaType: mediaType, bytes: 3, sha256: "", createdAt: Date(),
              expiresAt: Date().addingTimeInterval(Double(ttlSeconds)))
    }
    func deleteAsset(_ id: String) async throws { deleted.append(id) }
    func voices(operation: String, model: String) async throws -> VoiceList {
        guard !voiceIDs.isEmpty else { throw MESClientError.unexpected("no voices here") }
        return VoiceList(voices: voiceIDs.map { Voice(id: $0, title: $0, sample: "/voices/\($0).wav") }, etag: id)
    }
    func sample(of voice: Voice) async throws -> Data { Data("\(id):\(voice.id)".utf8) }

    func engineInfo() async throws -> EngineInfo { throw MESClientError.unexpected("unused") }
    func operations() async throws -> OperationsList { throw MESClientError.unexpected("unused") }
    func health() async throws -> Health { throw MESClientError.unexpected("unused") }
    func upload(contentsOf file: URL, mediaType: String) async throws -> Upload { throw MESClientError.unexpected("unused") }
    func submit(_ request: JobRequest, idempotencyKey: String?) async throws -> Job { throw MESClientError.unexpected("unused") }
    func job(_ id: String, wait: Int) async throws -> Job { throw MESClientError.unexpected("unused") }
    func jobs(state: JobState?) async throws -> [Job] { [] }
    func release(_ id: String) async throws -> Job { throw MESClientError.unexpected("unused") }
    func confirm(_ id: String) async throws -> Job { throw MESClientError.unexpected("unused") }
    func download(job: String, output: Output, to destination: URL) async throws -> URL { throw MESClientError.unexpected("unused") }
    func events(job: String, after seq: Int) -> AsyncThrowingStream<Event, any Error> { AsyncThrowingStream { $0.finish() } }
}
