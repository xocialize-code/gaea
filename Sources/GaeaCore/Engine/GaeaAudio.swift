import Foundation
import GaeaProtocol
import MESCore
import MESEngineCore
import Synchronization

/// The Audio profile (MES Audio 0.1, media-engine-spec v0.7.0, AB-T-0392). Every audio offer runs as itself: MESKit
/// validates, gates and routes the request from the offers' own `supports` and `limits` (`AudioProfileRules`), the
/// plugin's worker does the model-specific mapping (labels, cues, the model's syntax), and Gaea gives the client the
/// format it asked for (`output`, a stream plan), streaming the worker's chunks as they arrive (GPP-1 §3.3.1).
extension GaeaEngine {
    /// The media types an audio input takes. Workers read WAV; other containers come with the plugins that need them.
    static let audioInputTypes = ["audio/wav"]

    /// One descriptor per Audio operation some enabled plugin offers.
    func audioDescriptors(_ routes: [PluginRoute]) -> [Descriptor] {
        let audio = routes.filter { $0.manifestOffer.profile == AudioProfile.id }
        return Set(audio.map(\.operation)).sorted().compactMap { operation in
            Self.audioDescriptor(operation, routes: audio.filter { $0.operation == operation })
        }
    }

    static func audioDescriptor(_ operation: String, routes: [PluginRoute]) -> Descriptor? {
        guard let spec = AudioProfile.operations.operations[operation], !routes.isEmpty else { return nil }
        let models = Self.audioModels(routes)
        let streams = models.contains { $0.supports("stream")?.boolValue == true }
        let inputs = spec.inputs.sorted { $0.key < $1.key }.map { name, io in
            InputSpec(name: name, kind: io.kind, required: io.required ?? false, max: io.kind == .text ? nil : 1,
                      mediaTypes: io.kind == .audio ? audioInputTypes : nil)
        }
        var properties: [String: MESValue] = [:]
        for (order, name) in spec.vocabulary.enumerated() {
            guard case .object(var schema)? = AudioProfile.vocabularySchema(name, operation: operation) else { continue }
            if name == AudioProfile.Param.output, case .object(var fields)? = schema["properties"] {
                // Gaea writes WAV: 16- or 24-bit integer, or 32-bit float, at any rate, mono or stereo.
                fields["media_type"] = ["enum": ["audio/wav"]]
                fields["bit_depth"] = ["enum": [16, 24, 32]]
                schema["properties"] = .object(fields)
            }
            schema["x-mes-ui"] = .object(audioUI(name, order: order))
            properties[name] = .object(schema)
        }
        let outputs = spec.outputs.sorted { $0.key < $1.key }.map { name, io -> OutputSpec in
            let many = ["samples", "sounds"].contains(name)
            let optional = (operation == "audio.edit_speech" && name == "transcript") || (operation == "audio.compose" && name != "song")
            let mediaTypes = io.kind == .data ? ["application/json"] : io.kind == .text ? ["text/vnd.abc"] : ["audio/wav"]
            return OutputSpec(name: name, kind: io.kind, mediaTypes: mediaTypes, min: optional ? 0 : 1,
                              max: many ? (operation == "audio.design_voice" ? 4 : 8) : 1,
                              stream: io.streamable == true && streams ? .init(encodings: [.pcmS16LE, .pcmF32LE]) : nil)
        }
        let tiers = QualityTier.allCases.filter { tier in models.contains { $0.qualityTiers.contains(tier) } }
        return Descriptor(
            operation: operation, profile: AudioProfile.id, profileVersion: AudioProfile.version, title: audioTitle(operation),
            summary: nil, inputs: inputs,
            params: .object(["type": "object", "additionalProperties": false, "properties": .object(properties)]),
            outputs: outputs, limits: audioLimits(models), qualityTiers: tiers, models: models,
            remote: .init(possible: false))
    }

    /// The offers as MES models: the plugin's own `supports` and `limits` (GPP-1 §4.3), its voice count, and a default
    /// where the plugins named none.
    static func audioModels(_ routes: [PluginRoute]) -> [ModelOffer] {
        var models: [ModelOffer] = []
        for route in routes where !models.contains(where: { $0.id == route.model.id }) {
            var offer = route.offer
            if let voices = route.manifestOffer.voices, !voices.isEmpty {
                var supports = offer.supports ?? [:]
                supports["voices"] = .number(Double(voices.count))
                offer.supports = supports
            }
            if offer.namedOnly == true { offer.isDefault = nil }
            models.append(offer)
        }
        if !models.contains(where: { $0.isDefault == true }), let first = models.firstIndex(where: { $0.namedOnly != true }) {
            models[first].isDefault = true
        }
        return models
    }

    /// The operation's limits: a field every model declares, at the largest any allows. A model without the field
    /// isn't limited by the descriptor (its own limits gate it, Base §6.4).
    static func audioLimits(_ models: [ModelOffer]) -> Descriptor.Limits? {
        let all = models.map { $0.limits }
        guard !all.isEmpty, all.allSatisfy({ $0 != nil }) else { return nil }
        let declared = all.compactMap(\.self)
        var limits = Descriptor.Limits()
        let durations = declared.map(\.maxDurationSeconds)
        if durations.allSatisfy({ $0 != nil }) { limits.maxDurationSeconds = durations.compactMap(\.self).max() }
        let counts = declared.map(\.maxCount)
        if counts.allSatisfy({ $0 != nil }) { limits.maxCount = counts.compactMap(\.self).max() }
        for field in Set(declared.flatMap(\.profile.keys)) {
            let values = declared.map { $0.profile[field] }
            guard values.allSatisfy({ $0 != nil }) else { continue }
            // A minimum is the smallest any allows.
            limits.profile[field] = field.hasPrefix("min_") ? values.compactMap(\.self).min() : values.compactMap(\.self).max()
        }
        return limits == Descriptor.Limits() ? nil : limits
    }

    static func audioTitle(_ operation: String) -> String {
        ["audio.design_voice": "Design a voice", "audio.speak": "Speak", "audio.edit_speech": "Edit speech",
         "audio.generate": "Generate a sound", "audio.compose": "Compose a song"][operation] ?? operation
    }

    static func audioUI(_ name: String, order: Int) -> [String: MESValue] {
        let widgets = ["seed": "seed", "quality": "picker", "count": "stepper", "voice": "voice", "style": "picker",
                       "speed": "slider", "language": "text", "planning": "picker", "timestamps": "toggle",
                       "negative_prompt": "textarea", "duration_s": "slider", "target_duration_s": "slider",
                       "prompt_enhance": "picker"]
        var hints: [String: MESValue] = ["label": .string(name.replacingOccurrences(of: "_", with: " ").capitalized),
                                         "order": .number(Double(order))]
        if let widget = widgets[name] { hints["widget"] = .string(widget) }
        if ["seed", "output", "negative_prompt", "prompt_enhance"].contains(name) { hints["advanced"] = true }
        return hints
    }

    /// The preset voices an offer lists (GPP-1 §4.3), as MES voices.
    func audioVoices(operation: String, model: String) async -> [Voice] {
        guard let route = await liveRoutes().first(where: { $0.operation == operation && $0.model.id == model }) else { return [] }
        return (route.manifestOffer.voices ?? []).compactMap { try? JSONDecoder().decode(Voice.self, from: JSONEncoder().encode($0)) }
    }

    // MARK: - Running

    /// One audio offer, run as itself: the worker streams what the client asked to stream when its model can, and Gaea
    /// converts every output to the client's format.
    func runAudio(_ route: PluginRoute, _ context: RunContext) async throws -> RunOutput {
        let workerDirectory = context.outputDirectory.appending(path: "worker", directoryHint: .isDirectory)
        let inputs = try Self.inputPaths(context.inputs, writingTextTo: context.outputDirectory.appending(path: "worker-inputs",
                                                                                                          directoryHint: .isDirectory))
        var params = route.manifestOffer.defaults?.objectValue ?? [:]
        for (key, value) in context.params { params[key] = value.gpp }
        let names = Set(route.extensions.map(\.name))
        let modelParams = context.extensions.filter { names.contains($0.key) }.mapValues(\.gpp)
        let modelStreams = route.offer.supports("stream")?.boolValue == true
        let streams = modelStreams ? context.streams.map(\.output) : []
        var assets: [String: GPPValue] = [:]
        for (name, ids) in context.assets where ids.contains(where: { $0 != nil }) {
            assets[name] = .array(ids.map { $0.map(GPPValue.string) ?? .null })
        }
        var job = WorkerJob(
            job: context.jobID, pluginID: route.plugin.id, model: route.model.id, operation: route.operation,
            namedLane: context.extensions[Self.laneExtension]?.stringValue, lanes: route.manifestOffer.lanes,
            params: params, inputs: inputs, modelParams: modelParams, seed: context.param("seed")?.intValue,
            outputDir: workerDirectory)
        job.streams = streams
        job.assets = assets

        let forwarder = ChunkForwarder(plans: context.streams.filter { streams.contains($0.output) }, reporter: context.reporter,
                                       root: workerDirectory)
        let ran: WorkerJobResult
        do {
            ran = try await schedule(job, title: route.plugin.title, context: context) { line in
                if line["type"]?.stringValue == "chunk", line["encoding"] != nil { forwarder.push(line) }
            }
        } catch {
            await forwarder.drain()
            throw error
        }
        try await forwarder.finish()

        var warnings = forwarder.warnings
        var outputs: [ProducedOutput] = []
        let entries = ran.result["outputs"]?.arrayValue ?? []
        for name in streams where !forwarder.ended(name) && entries.contains(where: { $0["name"]?.stringValue == name && $0["streamed"] == true }) {
            throw MESError(.engineError, "\(route.plugin.title) listed \(name) as streamed but never sent its final chunk.")
        }
        let files = ran.result.merging(["outputs": .array(entries.filter { $0["streamed"] != true })]) { $1 }
        for output in try Self.producedOutputs(result: files, chunks: [], workerDirectory: workerDirectory,
                                               outputDirectory: context.outputDirectory, specs: context.descriptor.outputs) {
            if let plan = context.stream(output.name), let file = output.file {
                // Asked to stream, and the worker wrote a file (its model doesn't stream): the file's samples are the stream.
                warnings += try await Self.streamFile(file, plan: plan, reporter: context.reporter)
                outputs.append(.streamed(output.name))
            } else if output.kind == .audio, let file = output.file {
                let (converted, changed) = try Self.audioOutput(file, name: output.name, format: context.param(AudioProfile.Param.output)?.objectValue)
                outputs.append(converted)
                warnings += changed
            } else {
                outputs.append(output)
            }
        }
        outputs += entries.filter { $0["streamed"] == true }.compactMap { $0["name"]?.stringValue }.map { ProducedOutput.streamed($0) }

        let effective = ran.result["effective"]?.objectValue?.mapValues(\.mes) ?? [:]
        // An unseeded model reports no seed (Audio §1.6: `supports.seed: false`).
        let seeded = route.offer.supports("seed")?.boolValue != false
        var output = RunOutput(outputs: outputs, effective: effective,
                               seed: seeded ? effective["seed"]?.intValue ?? context.param("seed")?.intValue : nil)
        Self.attach(ran, plugin: route.plugin, model: route.model.id, operation: route.operation, to: &output)
        for warning in warnings where !output.warnings.contains(warning) { output.warnings.append(warning) }
        return output
    }

    /// An audio file as the client asked for it (`output`: rate, channels, bit depth), with its facts. A file that needs
    /// no change is kept as the worker wrote it.
    static func audioOutput(_ file: URL, name: String, format: [String: MESValue]?) throws -> (ProducedOutput, [Warning]) {
        guard let wav = try? WAVFile(Data(contentsOf: file)) else {
            throw MESError(.engineError, "The plugin's \(name) isn't a WAV file Gaea can read.")
        }
        let rate = format?["sample_rate"]?.intValue ?? wav.sampleRate
        let channels = format?["channels"]?.intValue ?? wav.channels
        let depth = format?["bit_depth"]?.intValue ?? (wav.format == .float ? 32 : wav.bitsPerSample)
        var warnings: [Warning] = []
        let same = rate == wav.sampleRate && channels == wav.channels && depth == wav.bitsPerSample
            && (depth == 32) == (wav.format == .float)
        if !same {
            let conversion = AudioConversion(fromRate: wav.sampleRate, fromChannels: wav.channels, toRate: rate, toChannels: channels)
            let samples = conversion.convert(wav.floatSamples, final: true)
            try AudioPCM.wav(samples, sampleRate: rate, channels: channels, bitDepth: depth).write(to: file)
            warnings += Self.conversionWarnings(conversion, param: AudioProfile.Param.output)
        }
        let written = try WAVFile(Data(contentsOf: file))
        return (.audio(file, name: name, durationSeconds: written.durationSeconds, sampleRate: written.sampleRate,
                       channels: written.channels, bitDepth: written.bitsPerSample), warnings)
    }

    /// A file's samples sent as one stream: passed through when they are already in the plan's format.
    static func streamFile(_ file: URL, plan: StreamPlan, reporter: RunReporter) async throws -> [Warning] {
        guard let wav = try? WAVFile(Data(contentsOf: file)) else {
            throw MESError(.engineError, "The plugin's \(plan.output) isn't a WAV file Gaea can read.")
        }
        defer { try? FileManager.default.removeItem(at: file) }
        let native = wav.sampleRate == plan.sampleRate && wav.channels == plan.channels
        if native, wav.format == .int, wav.bitsPerSample == 16, plan.encoding == .pcmS16LE {
            await reporter.chunk(plan.output, samples: wav.pcm, final: true)
            return []
        }
        let conversion = AudioConversion(fromRate: wav.sampleRate, fromChannels: wav.channels, toRate: plan.sampleRate,
                                         toChannels: plan.channels)
        await reporter.chunk(plan.output, samples: AudioPCM.encode(conversion.convert(wav.floatSamples, final: true), plan.encoding),
                             final: true)
        return conversionWarnings(conversion, param: AudioProfile.Param.output)
    }

    static func conversionWarnings(_ conversion: AudioConversion, param: String) -> [Warning] {
        var warnings: [Warning] = []
        if conversion.resamples {
            warnings.append(Warning(code: AudioProfile.WarningCode.audioResampled,
                                    message: "Resampled from the model's \(conversion.fromRate) Hz to \(conversion.toRate) Hz.", param: param))
        }
        if conversion.remixes, conversion.toChannels < conversion.fromChannels {
            warnings.append(Warning(code: AudioProfile.WarningCode.audioDownmixed,
                                    message: "Mixed down from \(conversion.fromChannels) channels to \(conversion.toChannels).", param: param))
        }
        return warnings
    }
}

/// A run's PCM chunks on their way to the client (GPP-1 §3.3.1), in the order the worker sent them: each read from its
/// file, converted to the stream plan, forwarded through MESKit's reporter and deleted. A file outside the run's
/// `output_dir` is refused, as an output is.
final class ChunkForwarder: @unchecked Sendable {
    private let plans: [StreamPlan]
    private let reporter: RunReporter
    private let root: String
    private let continuation: AsyncStream<[String: GPPValue]>.Continuation
    private var task: Task<Void, Never>?
    private let state = Mutex<State>(State())

    struct State {
        var conversions: [String: AudioConversion] = [:]
        var next: [String: Int] = [:]
        var ended: Set<String> = []
        var warnings: [Warning] = []
        var failure: MESError?
    }

    init(plans: [StreamPlan], reporter: RunReporter, root: URL) {
        self.plans = plans
        self.reporter = reporter
        self.root = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let (stream, continuation) = AsyncStream.makeStream(of: [String: GPPValue].self)
        self.continuation = continuation
        task = Task { [self] in
            for await line in stream { await forward(line) }
        }
    }

    func push(_ line: [String: GPPValue]) { continuation.yield(line) }

    /// Waits for every chunk already pushed; throws if one was bad.
    func finish() async throws {
        continuation.finish()
        await task?.value
        if let failure = state.withLock({ $0.failure }) { throw failure }
    }

    /// Waits for the chunks without throwing (the run already failed).
    func drain() async {
        continuation.finish()
        await task?.value
    }

    func ended(_ output: String) -> Bool { state.withLock { $0.ended.contains(output) } }
    var warnings: [Warning] { state.withLock { $0.warnings } }

    private func forward(_ line: [String: GPPValue]) async {
        guard state.withLock({ $0.failure == nil }) else { return }
        guard let output = line["output"]?.stringValue, let plan = plans.first(where: { $0.output == output }),
              let path = line["path"]?.stringValue, let rate = line["sample_rate"]?.intValue, let channels = line["channels"]?.intValue
        else { return fail("The plugin sent a chunk of an output it wasn't asked to stream.") }
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root) else { return fail("The plugin sent a chunk at \(path), outside its output_dir.") }
        defer { try? FileManager.default.removeItem(at: file) }
        let index = line["index"]?.intValue ?? -1
        let final = line["final"]?.boolValue == true
        let expected = state.withLock { $0.next[output, default: 0] }
        guard index == expected, !ended(output) else { return fail("The plugin sent chunk \(index) of \(output), expecting \(expected).") }
        let int16 = line["encoding"]?.stringValue == "pcm_s16le"
        guard let data = try? Data(contentsOf: file), data.count % ((int16 ? 2 : 4) * channels) == 0 else {
            return fail("Chunk \(index) of \(output) isn't whole \(line["encoding"]?.stringValue ?? "") frames.")
        }
        // 16-bit samples already in the client's format pass through untouched.
        if int16, plan.encoding == .pcmS16LE, rate == plan.sampleRate, channels == plan.channels {
            await reporter.chunk(output, samples: data, final: final)
            state.withLock {
                $0.next[output] = index + 1
                if final { $0.ended.insert(output) }
            }
            return
        }
        let samples = int16 ? data.withUnsafeBytes { $0.bindMemory(to: Int16.self).map { Float($0) / 32768 } }
            : data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let conversion = state.withLock { s -> AudioConversion in
            if let c = s.conversions[output], c.fromRate == rate, c.fromChannels == channels { return c }
            let c = AudioConversion(fromRate: rate, fromChannels: channels, toRate: plan.sampleRate, toChannels: plan.channels)
            s.conversions[output] = c
            for w in GaeaEngine.conversionWarnings(c, param: AudioProfile.Param.output) where !s.warnings.contains(w) { s.warnings.append(w) }
            return c
        }
        await reporter.chunk(output, samples: AudioPCM.encode(conversion.convert(samples, final: final), plan.encoding), final: final)
        state.withLock {
            $0.next[output] = index + 1
            if final { $0.ended.insert(output) }
        }
    }

    private func fail(_ message: String) {
        state.withLock { if $0.failure == nil { $0.failure = MESError(.engineError, message) } }
    }
}
