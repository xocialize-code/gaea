import Foundation
@testable import GaeaCore
import GaeaProtocol
import MESCore
import MESEngineCore
import Testing

/// The Audio profile's host side (AB-T-0392): descriptors from offers, the client's formats, streamed chunks.
@Suite("Audio")
struct AudioTests {
    let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Two audio.speak offers on the z-image manifest's model: one streams with two preset voices, one doesn't.
    func speakRoutes() throws -> [PluginRoute] {
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repoRoot.appending(path: "examples/v1/manifest/z-image.json"))) as? [String: Any])
        let base = try #require((json["offers"] as? [[String: Any]])?.first)
        var model = try #require(base["model"] as? [String: Any])
        var streaming = base
        model["supports"] = ["stream": true, "default_voice": true, "seed": false, "sample_rate": 24000, "channels": 1, "languages": ["en-US"]]
        model["limits"] = ["max_text_chars": 4000, "max_duration_s": 120]
        streaming["operation"] = "audio.speak"
        streaming["profile"] = "audio"
        streaming["model"] = model
        streaming["voices"] = [["id": "af_heart", "title": "Heart", "languages": ["en-US"]], ["id": "bm_lewis", "title": "Lewis"]]
        var plain = streaming
        var other = model
        other["id"] = "z-image-base"
        other["supports"] = ["sample_rate": 44100, "channels": 2, "voice_ref": true]
        other["limits"] = ["max_text_chars": 1000]
        plain["model"] = other
        plain["voices"] = nil
        var models = try #require(json["models"] as? [[String: Any]])
        var second = models[0]
        second["id"] = "z-image-base"
        models.append(second)
        json["models"] = models
        json["offers"] = [streaming, plain]
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

    @Test func aDescriptorFromTheOffersOwnSupportsLimitsAndVoices() throws {
        let descriptor = try #require(GaeaEngine.audioDescriptor("audio.speak", routes: try speakRoutes()))
        #expect(descriptor.profile == "audio" && descriptor.profileVersion == "0.1")
        #expect(descriptor.models.map(\.id) == ["z-image-turbo", "z-image-base"])
        #expect(descriptor.models[0].isDefault == true)
        #expect(descriptor.models[0].supports("voices")?.intValue == 2)
        #expect(descriptor.models[1].supports("voices") == nil)
        #expect(descriptor.outputs.first { $0.name == "audio" }?.stream?.encodings == [.pcmS16LE, .pcmF32LE])
        // Every model declares max_text_chars, so the operation's is the largest; only one declares a duration.
        #expect(descriptor.limits?.profile["max_text_chars"] == 4000)
        #expect(descriptor.limits?.maxDurationSeconds == nil)
        #expect(descriptor.inputs.contains { $0.name == "text" && $0.required })
        #expect(descriptor.inputs.first { $0.name == "voice_ref" }?.mediaTypes == ["audio/wav"])
        let properties = descriptor.params["properties"]
        #expect(properties?["output"]?["properties"]?["bit_depth"]?["enum"] == [16, 24, 32])
        #expect(properties?["voice"] != nil)
    }

    @Test func noStreamingModelMeansNoStreamedOutput() throws {
        let descriptor = try #require(GaeaEngine.audioDescriptor("audio.speak", routes: [try speakRoutes()[1]]))
        #expect(descriptor.outputs.allSatisfy { $0.stream == nil })
        #expect(descriptor.models[0].isDefault == true)
    }

    @Test func sixteenBitSamplesAreTheFleetsWAVSamples() {
        let samples: [Float] = [0, 0.5, -0.5, 1, -1, 2, -2, 0.0000305]
        let data = AudioPCM.encode(samples, .pcmS16LE)
        let ints = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        #expect(ints == [0, 16383, -16383, 32767, -32767, 32767, -32767, 0])
        #expect(AudioPCM.encode(samples, .pcmF32LE).count == samples.count * 4)
        #expect(AudioPCM.remix([0.1, 0.2], from: 1, to: 2) == [0.1, 0.1, 0.2, 0.2])
        #expect(AudioPCM.remix([0.2, 0.4, -1, 1], from: 2, to: 1).map { ($0 * 100).rounded() } == [30, 0])
    }

    @Test func aStreamResamplesAsOneSignal() {
        let conversion = AudioConversion(fromRate: 24000, fromChannels: 1, toRate: 48000, toChannels: 1)
        let tone = (0..<7200).map { Float(sin(Double($0) * 2 * .pi * 440 / 24000)) * 0.5 }
        var out: [Float] = []
        for i in 0..<3 { out += conversion.convert(Array(tone[(i * 2400)..<((i + 1) * 2400)]), final: i == 2) }
        #expect(abs(out.count - 14400) <= 64, "\(out.count)")
        #expect(conversion.resamples && !conversion.remixes)
        let same = AudioConversion(fromRate: 24000, fromChannels: 1, toRate: 24000, toChannels: 1)
        #expect(same.convert(tone, final: true) == tone)
    }

    @Test func aFileNeedingNoChangeIsKeptByteForByte() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gaea-audio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "audio-0.wav")
        let wav = AudioPCM.wav((0..<2400).map { Float($0 % 100) / 200 }, sampleRate: 24000, channels: 1, bitDepth: 16)
        try wav.write(to: file)
        let (kept, none) = try GaeaEngine.audioOutput(file, name: "audio", format: nil)
        #expect(try Data(contentsOf: file) == wav && none.isEmpty)
        #expect(kept.sampleRate == 24000 && kept.channels == 1 && kept.bitDepth == 16 && kept.durationSeconds == 0.1)
        let (converted, warnings) = try GaeaEngine.audioOutput(file, name: "audio", format: ["sample_rate": 48000, "channels": 2])
        #expect(converted.sampleRate == 48000 && converted.channels == 2)
        #expect(warnings.map(\.code) == ["audio_resampled"])
    }

    @Test func chunksAreConvertedForwardedInOrderAndDeleted() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "gaea-chunks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "stream"), withIntermediateDirectories: true)
        let sent = Sent()
        let reporter = RunReporter(progress: { _ in }, warning: { _ in }, preview: { _, _ in },
                                   chunk: { output, data, final in sent.add(output, data, final) })
        let plan = StreamPlan(output: "audio", encoding: .pcmS16LE, sampleRate: 24000, channels: 1)
        let forwarder = ChunkForwarder(plans: [plan], reporter: reporter, root: root)
        var expected: [Data] = []
        for i in 0..<3 {
            let samples = (0..<240).map { Float(i * 240 + $0) / 1000 }
            let file = root.appending(path: "stream/audio-\(i).f32")
            try samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: file)
            expected.append(AudioPCM.encode(samples, .pcmS16LE))
            var line: [String: GPPValue] = ["type": "chunk", "output": "audio", "index": .int(Int64(i)), "path": .string(file.path),
                                            "encoding": "pcm_f32le", "sample_rate": 24000, "channels": 1]
            if i == 2 { line["final"] = true }
            forwarder.push(line)
        }
        try await forwarder.finish()
        #expect(sent.all.map(\.data) == expected)
        #expect(sent.all.map(\.final) == [false, false, true])
        #expect(forwarder.ended("audio") && forwarder.warnings.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "stream").path).isEmpty)
    }

    @Test func sixteenBitChunksInTheClientsFormatPassThrough() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "gaea-chunks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sent = Sent()
        let reporter = RunReporter(progress: { _ in }, warning: { _ in }, preview: { _, _ in },
                                   chunk: { output, data, final in sent.add(output, data, final) })
        let ints: [Int16] = [0, 16384, -16384, 32767, -32768, 1]
        let pcm = ints.withUnsafeBufferPointer { Data(buffer: $0) }
        let file = root.appending(path: "audio-0.s16")
        try pcm.write(to: file)
        let line: [String: GPPValue] = ["output": "audio", "index": 0, "path": .string(file.path), "encoding": "pcm_s16le",
                                        "sample_rate": 24000, "channels": 1, "final": true]
        let same = ChunkForwarder(plans: [StreamPlan(output: "audio", encoding: .pcmS16LE, sampleRate: 24000, channels: 1)],
                                  reporter: reporter, root: root)
        same.push(line)
        try await same.finish()
        #expect(sent.all.map(\.data) == [pcm])
        // To float: exactly the integers over 32768.
        try pcm.write(to: file)
        let float = ChunkForwarder(plans: [StreamPlan(output: "audio", encoding: .pcmF32LE, sampleRate: 24000, channels: 1)],
                                   reporter: reporter, root: root)
        float.push(line)
        try await float.finish()
        #expect(sent.all.last?.data == AudioPCM.encode(ints.map { Float($0) / 32768 }, .pcmF32LE))
    }

    @Test func aChunkOutOfOrderOrOutsideTheRunFailsIt() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "gaea-chunks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let plan = StreamPlan(output: "audio", encoding: .pcmF32LE, sampleRate: 24000, channels: 1)
        let file = root.appending(path: "audio-1.f32")
        try Data(count: 16).write(to: file)
        let skipping = ChunkForwarder(plans: [plan], reporter: .none, root: root)
        skipping.push(["output": "audio", "index": 1, "path": .string(file.path), "encoding": "pcm_f32le", "sample_rate": 24000, "channels": 1])
        await #expect(throws: MESError.self) { try await skipping.finish() }
        let outside = ChunkForwarder(plans: [plan], reporter: .none, root: root.appending(path: "worker"))
        outside.push(["output": "audio", "index": 0, "path": .string(file.path), "encoding": "pcm_f32le", "sample_rate": 24000, "channels": 1])
        await #expect(throws: MESError.self) { try await outside.finish() }
    }
}

final class Sent: @unchecked Sendable {
    struct Chunk { var output: String; var data: Data; var final: Bool }
    private let lock = NSLock()
    private var chunks: [Chunk] = []
    func add(_ output: String, _ data: Data, _ final: Bool) { lock.lock(); chunks.append(Chunk(output: output, data: data, final: final)); lock.unlock() }
    var all: [Chunk] { lock.lock(); defer { lock.unlock() }; return chunks }
}
