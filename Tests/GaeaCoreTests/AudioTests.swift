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
        let plugin = InstalledPlugin(id: manifest.id, version: manifest.version, title: manifest.title, repo: manifest.repo, enabled: true, trusted: true,
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
        #expect(descriptor.inputs.first { $0.name == "voice_ref" }?.mediaTypes == ["audio/wav", "audio/flac", "audio/mpeg", "audio/mp4"])
        let properties = descriptor.params["properties"]
        #expect(properties?["output"]?["properties"]?["bit_depth"]?["enum"] == [16, 24, 32])
        #expect(properties?["voice"] != nil)
    }

    /// Two audio.separate offers (RFC 0006): a masked music separator and a regenerating voice separator.
    @Test func aSeparatorsOutputsAreTheStemsItsOffersMake() throws {
        let routes = try speakRoutes().enumerated().map { i, route -> PluginRoute in
            var offer = route.manifestOffer
            offer.operation = "audio.separate"
            var r = route
            r.manifestOffer = offer
            r.offer.supports = i == 0
                ? ["stems": ["vocals", "instrumental"], "stem_method": "masked", "sample_rate": 44100, "channels": 2]
                : ["stems": ["speaker", "singing"], "speaker_selection": ["ordinal", "saying"], "stem_method": "regenerated",
                   "sample_rate": 24000, "channels": 1]
            r.offer.limits = .init(maxDurationSeconds: i == 0 ? 600 : 30)
            return r
        }
        let descriptor = try #require(GaeaEngine.audioDescriptor("audio.separate", routes: routes))
        #expect(descriptor.title == "Separate sources")
        // The registry's order, only the stems some offer makes, each optional and single.
        #expect(descriptor.outputs.map(\.name) == ["speaker", "singing", "vocals", "instrumental"])
        #expect(descriptor.outputs.allSatisfy { $0.min == 0 && $0.max == 1 && $0.kind == .audio })
        #expect(descriptor.inputs.map(\.name) == ["audio"] && descriptor.inputs[0].required)
        #expect(descriptor.limits?.maxDurationSeconds == 600)
        let properties = descriptor.params["properties"]
        #expect(properties?["stems"] != nil && properties?["speaker"] != nil)
        // The stems a job makes: the request's, else the offer's without the speaker, else the speaker for a pick.
        #expect(AudioProfileRules.stems([:], model: routes[1].offer) == ["singing"])
        #expect(AudioProfileRules.stems(["speaker": ["ordinal": 2]], model: routes[1].offer) == ["speaker"])
        #expect(AudioProfileRules.stems(["stems": ["vocals"]], model: routes[0].offer) == ["vocals"])
    }

    /// A mixture longer than the offer's max_duration_s is refused, never trimmed (§3.6).
    @Test func aSeparatorsMixtureIsBoundedByItsLimit() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gaea-separate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let mixture = dir.appending(path: "mix.wav")
        try AudioPCM.wav([Float](repeating: 0, count: 24000 * 31), sampleRate: 24000, channels: 1, bitDepth: 16).write(to: mixture)
        let inputs: [String: [RunInput]] = ["audio": [.file(mixture, mediaType: "audio/wav")]]
        #expect(throws: MESError.self) {
            try GaeaEngine.checkInputLengths("audio.separate", inputs: inputs, limits: .init(maxDurationSeconds: 30))
        }
        try GaeaEngine.checkInputLengths("audio.separate", inputs: inputs, limits: .init(maxDurationSeconds: 600))
    }

    /// A described-target separator (RFC 0008, MES 0.13.0: SAM-Audio's shape) beside a labelled one: the descriptor
    /// takes `describe` and `spans`, lists `target` and `residual` after the labelled stems, and carries the watermark.
    @Test func aDescribedSeparatorTakesADescriptionAndSpans() throws {
        let routes = try speakRoutes().enumerated().map { i, route -> PluginRoute in
            var offer = route.manifestOffer
            offer.operation = "audio.separate"
            var r = route
            r.manifestOffer = offer
            r.offer.supports = i == 0
                ? ["stems": ["target", "residual"], "described_target": true, "spans": true, "stem_method": "regenerated",
                   "languages": ["en"], "sample_rate": 48000, "channels": 1, "watermark": "audioseal"]
                : ["stems": ["vocals", "instrumental"], "stem_method": "masked", "sample_rate": 44100, "channels": 2]
            r.offer.limits = .init(maxDurationSeconds: 30)
            return r
        }
        let descriptor = try #require(GaeaEngine.audioDescriptor("audio.separate", routes: routes))
        #expect(descriptor.outputs.map(\.name) == ["vocals", "instrumental", "target", "residual"])
        let properties = descriptor.params["properties"]
        #expect(properties?["describe"]?["x-mes-ui"]?["label"] == "Sound to separate")
        #expect(properties?["spans"] != nil)
        #expect(descriptor.models[0].watermark == "audioseal")
        // The stems a job makes: with a description the target and the residual, without one only labelled stems.
        #expect(AudioProfileRules.stems(["describe": "speech"], model: routes[0].offer) == ["target", "residual"])
        #expect(AudioProfileRules.stems([:], model: routes[0].offer) == [])
        #expect(AudioProfileRules.stems([:], model: routes[1].offer) == ["vocals", "instrumental"])
    }

    /// A span ending more than a sample past the mixture is refused `out_of_limits`, never clipped (§3.6, RFC 0008).
    @Test func aSpanPastTheMixtureIsRefused() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gaea-spans-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "mix.wav")
        try AudioPCM.wav([Float](repeating: 0, count: 48000 * 2), sampleRate: 48000, channels: 1, bitDepth: 16).write(to: file)
        let mixture = RunInput.file(file, mediaType: "audio/wav")
        try GaeaEngine.checkSpans([.init(start: 0.5, end: 2, present: true)], mixture: mixture)
        try GaeaEngine.checkSpans([.init(start: 0.5, end: 2 + 1.0 / 48000, present: false)], mixture: mixture)
        do {
            try GaeaEngine.checkSpans([.init(start: 0, end: 1, present: true), .init(start: 1, end: 2.01, present: true)], mixture: mixture)
            Issue.record("a span 10 ms past the mixture ran")
        } catch let error as MESError {
            #expect(error.code == "out_of_limits" && error.param == "spans")
        }
        try GaeaEngine.checkSpans([], mixture: mixture)
    }

    /// The SAM-Audio plugin's manifest (engine contract 1.62.0), when its checkout is next door: Gaea decodes it, and
    /// its offer is a described-target separator under the SAM licence with both acceptances.
    static let samManifest = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "gaea-plugin-sam-audio/dist/manifest.json")
    @Test(.enabled(if: FileManager.default.fileExists(atPath: samManifest.path)))
    func theSAMAudioManifestDecodes() throws {
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: Self.samManifest))
        let offer = try #require(manifest.offers.first { $0.operation == "audio.separate" })
        let mes = try JSONDecoder().decode(ModelOffer.self, from: JSONEncoder().encode(offer.model))
        #expect(mes.id == "sam-audio-base")
        #expect(mes.supports("described_target")?.boolValue == true && mes.supports("spans")?.boolValue == true)
        #expect(mes.supports("stems")?.arrayValue?.compactMap(\.stringValue) == ["target", "residual"])
        #expect(mes.watermark == "audioseal")
        #expect(mes.license.spdx == "LicenseRef-SAM")
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

    @Test func workersGetCanonicalSixteenBitWAVs() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gaea-inputs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tone = (0..<4800).map { Float(sin(Double($0) * 0.05)) * 0.5 }
        let canonical = dir.appending(path: "in16.wav")
        try AudioPCM.wav(tone, sampleRate: 24000, channels: 1, bitDepth: 16).write(to: canonical)
        #expect(try GaeaEngine.workerAudio(canonical, name: "voice_ref-0", into: dir) == canonical)
        for depth in [24, 32] {
            let file = dir.appending(path: "in\(depth).wav")
            try AudioPCM.wav(tone, sampleRate: 24000, channels: 1, bitDepth: depth).write(to: file)
            let out = try GaeaEngine.workerAudio(file, name: "voice_ref-\(depth)", into: dir)
            let wav = try WAVFile(Data(contentsOf: out))
            #expect(out != file && wav.bitsPerSample == 16 && wav.format == .int && wav.sampleRate == 24000 && wav.frames == 4800)
            #expect(zip(wav.floatSamples, tone).allSatisfy { abs($0 - $1) < 0.001 })
        }
        let junk = dir.appending(path: "junk.wav")
        try Data("not audio".utf8).write(to: junk)
        #expect(throws: MESError.self) { try GaeaEngine.workerAudio(junk, name: "voice_ref-0", into: dir) }
    }

    @Test func aTakeLongerThanTheOffersLimitIsOutOfLimits() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "gaea-take-\(UUID().uuidString).wav")
        try AudioPCM.wav([Float](repeating: 0, count: 24000 * 3), sampleRate: 24000, channels: 1, bitDepth: 16).write(to: file)
        let take: [String: [RunInput]] = ["audio": [.file(file, mediaType: "audio/wav")]]
        var limits = Descriptor.Limits()
        limits.maxDurationSeconds = 3
        try GaeaEngine.checkInputLengths("audio.edit_speech", inputs: take, limits: limits)
        limits.maxDurationSeconds = 2
        do {
            try GaeaEngine.checkInputLengths("audio.edit_speech", inputs: take, limits: limits)
            Issue.record("a 3 s take passed a 2 s limit")
        } catch let error as MESError {
            #expect(error.code == MESErrorCode.outOfLimits.rawValue && error.param == "audio")
        }
        // Compose bounds its source by max_source_s, not max_duration_s (the song's length).
        try GaeaEngine.checkInputLengths("audio.compose", inputs: ["source": take["audio"]!], limits: limits)
        limits.profile["max_source_s"] = 1
        #expect(throws: MESError.self) { try GaeaEngine.checkInputLengths("audio.compose", inputs: ["source": take["audio"]!], limits: limits) }
        // A repaint must lie inside its 3 s source.
        let source = ["source": take["audio"]!]
        try GaeaEngine.checkInputLengths("audio.compose", inputs: source, limits: nil, edit: ["kind": "repaint", "start_s": 1, "end_s": 3])
        #expect(throws: MESError.self) {
            try GaeaEngine.checkInputLengths("audio.compose", inputs: source, limits: nil, edit: ["kind": "repaint", "start_s": 1, "end_s": 3.5])
        }
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
