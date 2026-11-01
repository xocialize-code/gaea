import AVFoundation
import Foundation
import GaeaProtocol
import MESCore
import MESEngineCore

/// Video media between Gaea and its workers (GPP-1 §3.3.3, AB-T-0400). Workers get every video input in one form, an MP4
/// with H.264 or HEVC video and AAC audio where there is sound, as they get every audio input as a canonical WAV; and
/// Gaea reads an output's facts from the file. The Video profile's own routing waits on MES Video 0.1.
extension GaeaEngine {
    /// The media types a video input takes: whatever AVFoundation reads.
    static let videoInputTypes = ["video/mp4", "video/quicktime", "video/x-m4v"]

    /// What a video file holds.
    public struct VideoFacts: Sendable, Equatable {
        public var durationSeconds: Double
        public var frameRate: Double
        public var frames: Int
        public var width: Int
        public var height: Int
        /// The video track's codec, as its four characters (`avc1`, `hvc1`, `apcn`, …).
        public var codec: String
        public var audio: (sampleRate: Int, channels: Int, codec: String)?
        /// The container, from the file's `ftyp` box: `mp4` or `mov`.
        public var container: String

        public static func == (a: VideoFacts, b: VideoFacts) -> Bool {
            a.durationSeconds == b.durationSeconds && a.frameRate == b.frameRate && a.frames == b.frames && a.width == b.width
                && a.height == b.height && a.codec == b.codec && a.container == b.container
                && a.audio?.sampleRate == b.audio?.sampleRate && a.audio?.channels == b.audio?.channels && a.audio?.codec == b.audio?.codec
        }

        /// What a worker reads without conversion: an MP4 of H.264 or HEVC, with AAC or no audio.
        public var isCanonical: Bool {
            container == "mp4" && ["avc1", "hvc1", "hev1"].contains(codec) && (audio == nil || audio?.codec == "aac ")
        }
    }

    /// Reads a video file's facts. A file AVFoundation can't read, or without a video track, is `input_invalid`.
    static func videoFacts(_ url: URL, name: String = "video") async throws -> VideoFacts {
        let asset = AVURLAsset(url: url)
        guard let video = try? await asset.loadTracks(withMediaType: .video).first else {
            throw MESError(.inputInvalid, "Input \(name) isn't a video Gaea can read.", param: name)
        }
        let (duration, rate, size, transform, formats) = try await video.load(.timeRange, .nominalFrameRate, .naturalSize,
                                                                               .preferredTransform, .formatDescriptions)
        let shown = size.applying(transform)
        let codec = formats.first.map { Self.fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "????"
        var audio: (Int, Int, String)?
        if let track = try? await asset.loadTracks(withMediaType: .audio).first,
           let format = try? await track.load(.formatDescriptions).first,
           let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
            audio = (Int(basic.mSampleRate), Int(basic.mChannelsPerFrame), Self.fourCC(CMFormatDescriptionGetMediaSubType(format)))
        }
        let seconds = duration.duration.seconds
        let fps = Double(rate)
        return VideoFacts(durationSeconds: seconds, frameRate: fps, frames: Int((seconds * fps).rounded()), width: Int(abs(shown.width).rounded()),
                          height: Int(abs(shown.height).rounded()), codec: codec, audio: audio, container: Self.container(url))
    }

    /// A video input as workers read it (GPP-1 §3.3.3): one already canonical is passed as it is; anything else is
    /// rewritten as an MP4, remuxed when its codecs already fit and re-encoded as H.264 and AAC when they don't, at its
    /// own size, frame rate and length.
    static func workerVideo(_ url: URL, name: String, into directory: URL) async throws -> URL {
        let facts = try await videoFacts(url, name: name.components(separatedBy: "-").first ?? name)
        if facts.isCanonical { return url }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let out = directory.appending(path: "\(name).mp4")
        try? FileManager.default.removeItem(at: out)
        let codecsFit = ["avc1", "hvc1", "hev1"].contains(facts.codec) && (facts.audio == nil || facts.audio?.codec == "aac ")
        let preset = codecsFit ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        guard let export = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: preset) else {
            throw MESError(.inputInvalid, "Input \(name) can't be converted for the model.", param: name.components(separatedBy: "-").first)
        }
        do {
            try await export.export(to: out, as: .mp4)
        } catch {
            throw MESError(.inputInvalid, "Input \(name) couldn't be converted for the model: \(error.localizedDescription)",
                           param: name.components(separatedBy: "-").first)
        }
        return out
    }

    /// A clip at exactly `fps` (Video §1.3: frames at a constant rate). A writer on a 1/600 time base can't place 96 fps
    /// frames evenly, so a file whose rate is off by more than a thousandth is rewritten with its frames' timestamps on a
    /// time base of `fps`: the compressed frames are copied, not re-encoded. Each frame is shown at its rank in display
    /// order; frames are decoded in their own order, early by the stream's reorder depth (B-frames), and the clip still
    /// starts at zero.
    static func retime(_ file: URL, fps: Double) async throws {
        let asset = AVURLAsset(url: file)
        guard fps > 0, let track = try await asset.loadTracks(withMediaType: .video).first,
              abs(Double(try await track.load(.nominalFrameRate)) - fps) > 0.001 else { return }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        guard reader.startReading() else { return }
        var samples: [CMSampleBuffer] = []
        while let sample = output.copyNextSampleBuffer() { if CMSampleBufferGetNumSamples(sample) > 0 { samples.append(sample) } }
        guard !samples.isEmpty else { return }
        // Display rank of each sample (in decode order), and how far decoding runs ahead of display.
        let order = samples.indices.sorted { CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(samples[$0]),
                                                           CMSampleBufferGetPresentationTimeStamp(samples[$1])) < 0 }
        var rank = [Int](repeating: 0, count: samples.count)
        for (r, i) in order.enumerated() { rank[i] = r }
        let depth = max(0, samples.indices.map { $0 - rank[$0] }.max() ?? 0, samples.indices.map { rank[$0] - $0 }.max() ?? 0)

        let scale = CMTimeScale((fps * 1000).rounded())
        let temporary = file.deletingLastPathComponent().appending(path: ".retimed-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mp4)
        writer.movieTimeScale = scale
        let formats = try await track.load(.formatDescriptions)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formats.first)
        input.mediaTimeScale = scale
        input.transform = try await track.load(.preferredTransform)
        writer.add(input)
        writer.metadata = try await asset.load(.metadata)
        guard writer.startWriting() else { throw writer.error ?? MESError(.engineError, "Gaea can't retime the video.") }
        let frame = CMTime(value: 1000, timescale: scale)
        let start = CMTimeMultiply(frame, multiplier: Int32(depth))
        writer.startSession(atSourceTime: start)
        for (i, sample) in samples.enumerated() {
            var timing = CMSampleTimingInfo(duration: frame, presentationTimeStamp: CMTimeMultiply(frame, multiplier: Int32(rank[i] + depth)),
                                            decodeTimeStamp: depth == 0 ? .invalid : CMTimeMultiply(frame, multiplier: Int32(i)))
            var copy: CMSampleBuffer?
            CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1,
                                                  sampleTimingArray: &timing, sampleBufferOut: &copy)
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard let copy, input.append(copy) else { throw writer.error ?? MESError(.engineError, "Gaea can't retime the video.") }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTimeMultiply(frame, multiplier: Int32(samples.count + depth)))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? MESError(.engineError, "Gaea can't retime the video.") }
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
    }

    static func fourCC(_ code: FourCharCode) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }, encoding: .macOSRoman) ?? "????"
    }

    /// `mp4` or `mov`, from the major brand of the file's `ftyp` box.
    static func container(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: 12), head.count == 12,
              head[head.startIndex + 4..<head.startIndex + 8] == Data("ftyp".utf8) else { return "unknown" }
        try? handle.close()
        let brand = String(decoding: head[head.startIndex + 8..<head.startIndex + 12], as: UTF8.self)
        return brand == "qt  " ? "mov" : "mp4"
    }
}

// MARK: - The Video profile

/// The Video profile (MES Video 0.1, media-engine-spec v0.9.0, AB-T-0401). Every video offer runs as itself, as audio
/// offers do: MESKit validates, gates and routes the request from the offers' own `supports` and `limits`
/// (`VideoProfileRules`), the worker runs its model on canonical media, and Gaea does what the profile asks of the engine
/// around it: an `fps` turned into a factor, the source's sound and markings kept where the model drops them (§1.7,
/// §1.9), the codec the client asked for, and the facts read from the file.
extension GaeaEngine {
    /// One descriptor per Video operation some enabled plugin offers.
    func videoDescriptors(_ routes: [PluginRoute]) -> [Descriptor] {
        let video = routes.filter { $0.manifestOffer.profile == VideoProfile.id }
        return Set(video.map(\.operation)).sorted().compactMap { operation in
            Self.videoDescriptor(operation, routes: video.filter { $0.operation == operation })
        }
    }

    static func videoDescriptor(_ operation: String, routes: [PluginRoute]) -> Descriptor? {
        guard let spec = VideoProfile.operations.operations[operation], !routes.isEmpty else { return nil }
        let models = Self.audioModels(routes)
        let inputs = spec.inputs.sorted { $0.key < $1.key }.map { name, io -> InputSpec in
            let types: [String]? = switch io.kind {
            case .video: videoInputTypes
            case .audio: audioInputTypes
            case .image: ["image/png", "image/jpeg", "image/webp"]
            default: nil
            }
            let many = [VideoProfile.Input.keyframes, VideoProfile.Input.references, VideoProfile.Input.control].contains(name)
            return InputSpec(name: name, kind: io.kind, required: io.required ?? false, max: io.kind == .text ? nil : (many ? 8 : 1),
                             mediaTypes: types)
        }
        var properties: [String: MESValue] = [:]
        for (order, name) in spec.vocabulary.enumerated() {
            guard case .object(var schema)? = VideoProfile.vocabularySchema(name, operation: operation) else { continue }
            if name == VideoProfile.Param.output, case .object(var fields)? = schema["properties"] {
                // Gaea writes MP4, in either codec: it re-encodes when the model wrote the other one.
                fields["media_type"] = ["enum": ["video/mp4"]]
                fields["codec"] = ["enum": ["h264", "hevc"]]
                schema["properties"] = .object(fields)
            }
            schema["x-mes-ui"] = .object(videoUI(name, order: order))
            properties[name] = .object(schema)
        }
        let outputs = spec.outputs.sorted { $0.key < $1.key }.map { name, io in
            OutputSpec(name: name, kind: io.kind, mediaTypes: ["video/mp4"], min: 1, max: 1)
        }
        let tiers = QualityTier.allCases.filter { tier in models.contains { $0.qualityTiers.contains(tier) } }
        return Descriptor(
            operation: operation, profile: VideoProfile.id, profileVersion: VideoProfile.version, title: videoTitle(operation),
            summary: nil, inputs: inputs,
            params: .object(["type": "object", "additionalProperties": false, "properties": .object(properties)]),
            outputs: outputs, limits: audioLimits(models), qualityTiers: tiers, models: models, remote: .init(possible: false))
    }

    static func videoTitle(_ operation: String) -> String {
        ["video.generate": "Generate a clip", "video.extend": "Extend a clip", "video.retake": "Retake part of a clip",
         "video.upscale": "Upscale a video", "video.interpolate": "Interpolate frames"][operation] ?? operation
    }

    static func videoUI(_ name: String, order: Int) -> [String: MESValue] {
        let widgets = ["seed": "seed", "quality": "picker", "size": "size", "aspect": "aspect", "audio": "toggle",
                       "negative_prompt": "textarea", "duration_s": "slider", "fps": "slider", "retake": "picker",
                       "scale": "picker", "content": "picker", "factor": "stepper", "prompt_enhance": "picker"]
        let labels = ["duration_s": "Duration (s)", "fps": "Frame rate", "after_s": "Add after (s)", "before_s": "Add before (s)",
                      "start_s": "From (s)", "end_s": "To (s)", "keyframe_times": "Keyframe times (s)"]
        var hints: [String: MESValue] = ["label": .string(labels[name] ?? name.replacingOccurrences(of: "_", with: " ").capitalized),
                                         "order": .number(Double(order))]
        if let widget = widgets[name] { hints["widget"] = .string(widget) }
        if ["seed", "output", "negative_prompt", "prompt_enhance", "keyframe_times", "resolution"].contains(name) { hints["advanced"] = true }
        return hints
    }

    // MARK: Running

    /// One video offer, run as itself.
    func runVideo(_ route: PluginRoute, _ context: RunContext) async throws -> RunOutput {
        let workerDirectory = context.outputDirectory.appending(path: "worker", directoryHint: .isDirectory)
        let inputDirectory = context.outputDirectory.appending(path: "worker-inputs", directoryHint: .isDirectory)
        var inputs = context.inputs
        var sources: [String: (url: URL, facts: VideoFacts)] = [:]
        for (name, values) in inputs {
            var converted: [RunInput] = []
            for (i, value) in values.enumerated() {
                guard case .file(let url, let mediaType) = value else { converted.append(value); continue }
                if mediaType.hasPrefix("video/") {
                    let canonical = try await Self.workerVideo(url, name: "\(name)-\(i)", into: inputDirectory)
                    if i == 0 { sources[name] = (canonical, try await Self.videoFacts(canonical, name: name)) }
                    converted.append(.file(canonical, mediaType: "video/mp4"))
                } else if mediaType.hasPrefix("audio/") {
                    converted.append(.file(try Self.workerAudio(url, name: "\(name)-\(i)", into: inputDirectory), mediaType: "audio/wav"))
                } else {
                    converted.append(value)
                }
            }
            inputs[name] = converted
        }
        var params = route.manifestOffer.defaults?.objectValue ?? [:]
        for (key, value) in context.params { params[key] = value.gpp }
        let source = sources[VideoProfile.Input.video]
        if let source {
            try Self.checkVideoSource(source.facts, operation: route.operation, limits: route.offer.limits,
                                      scale: params[VideoProfile.Param.scale]?.intValue, grid: VideoProfile.FrameStep(route.offer),
                                      after: params[VideoProfile.Param.after]?.doubleValue,
                                      span: (params[VideoProfile.Param.start]?.doubleValue, params[VideoProfile.Param.end]?.doubleValue),
                                      retake: params[VideoProfile.Param.retake]?.stringValue)
        }
        var warnings: [Warning] = []
        if route.operation == "video.interpolate", let source {
            let (factor, warning) = Self.interpolationFactor(fps: context.param(VideoProfile.Param.fps)?.numberValue,
                                                             factor: context.param(VideoProfile.Param.factor)?.intValue,
                                                             sourceFPS: source.facts.frameRate, limits: route.offer.limits)
            params[VideoProfile.Param.fps] = nil
            params[VideoProfile.Param.factor] = .int(Int64(factor))
            if let warning { warnings.append(warning) }
        }
        let names = Set(route.extensions.map(\.name))
        let modelParams = context.extensions.filter { names.contains($0.key) }.mapValues(\.gpp)
        let job = WorkerJob(
            job: context.jobID, pluginID: route.plugin.id, model: route.model.id, operation: route.operation,
            namedLane: context.extensions[Self.laneExtension]?.stringValue, lanes: route.manifestOffer.lanes,
            params: params, inputs: try Self.inputPaths(inputs, writingTextTo: inputDirectory), modelParams: modelParams,
            seed: context.param("seed")?.intValue, outputDir: workerDirectory)
        let ran = try await schedule(job, title: route.plugin.title, context: context)

        var outputs: [ProducedOutput] = []
        var effective = ran.result["effective"]?.objectValue?.mapValues(\.mes) ?? [:]
        let codec = context.param(VideoProfile.Param.output)?.objectValue?["codec"]?.stringValue
        let keepsSource = ["video.upscale", "video.interpolate"].contains(route.operation)
        let edits = ["video.extend", "video.retake"].contains(route.operation)
        let title = route.offer.title ?? route.model.title
        let disclosure = route.operation == "video.generate" ? "AI-generated by \(title)"
            : edits ? "AI-generated in part by \(title)" : nil
        let sound = context.param(VideoProfile.Param.audio)?.boolValue != false
        for output in try Self.producedOutputs(result: ran.result, chunks: [], workerDirectory: workerDirectory,
                                               outputDirectory: context.outputDirectory, specs: context.descriptor.outputs) {
            guard output.kind == .video, let file = output.file else { outputs.append(output); continue }
            // A transformation's rate is the source's (upscale) or the source's × the factor (interpolate).
            let factor = route.operation == "video.interpolate" ? (effective["factor"]?.intValue ?? params["factor"]?.intValue ?? 2) : 1
            // A generative operation's is the rate the plugin made it at: LTX writes on a 1/600 time base, so 30 fps
            // and other rates whose frame isn't a whole 1/600 come out uneven.
            let rate = keepsSource ? source.map { $0.facts.frameRate * Double(factor) } : effective[VideoProfile.Param.fps]?.numberValue
            try await Self.finishVideo(file, keeping: keepsSource ? source?.url : nil, codec: codec, fps: rate,
                                       markings: edits ? source?.url : nil, disclosure: disclosure, sound: sound)
            let facts = try await Self.videoFacts(file, name: output.name)
            outputs.append(.video(file, name: output.name, width: facts.width, height: facts.height, fps: facts.frameRate,
                                  frames: facts.frames, sampleRate: facts.audio?.sampleRate, channels: facts.audio?.channels))
            effective[VideoProfile.Param.duration] = .number(Double(facts.frames) / facts.frameRate)
            effective[VideoProfile.Param.fps] = .number(facts.frameRate)
            effective[VideoProfile.Param.size] = ["width": .number(Double(facts.width)), "height": .number(Double(facts.height))]
            effective["frames"] = .number(Double(facts.frames))
        }
        let seeded = route.offer.supports("seed")?.boolValue != false
        var output = RunOutput(outputs: outputs, effective: effective,
                               seed: seeded ? effective["seed"]?.intValue ?? context.param("seed")?.intValue : nil)
        Self.attach(ran, plugin: route.plugin, model: route.model.id, operation: route.operation, to: &output)
        for warning in warnings where !output.warnings.contains(warning) { output.warnings.append(warning) }
        return output
    }

    /// What Video §3.5 asks of `fps`: the nearest factor the offer admits (2 to `max_factor`), warning `fps_adjusted`
    /// when the result's rate isn't the one asked for. Without either, factor 2.
    static func interpolationFactor(fps: Double?, factor: Int?, sourceFPS: Double, limits: Descriptor.Limits?) -> (Int, Warning?) {
        let most = Int(limits?.value(VideoProfile.LimitField.maxFactor) ?? 8)
        guard let fps, sourceFPS > 0 else { return (factor ?? 2, nil) }
        let chosen = min(most, max(2, Int((fps / sourceFPS).rounded())))
        let made = sourceFPS * Double(chosen)
        guard abs(made - fps) > 0.01 else { return (chosen, nil) }
        return (chosen, Warning(code: VideoProfile.WarningCode.fpsAdjusted,
                                message: String(format: "%g fps isn't a factor of the source's %g fps; the clip is %g fps.", fps, sourceFPS, made),
                                param: VideoProfile.Param.fps))
    }

    /// The source's length and the output's size against the offer's limits: 422 `out_of_limits`, never trimmed (Video
    /// §4.2; the kit can't read media). `interpolate` keeps the source's size; `upscale`'s output is the source's × `scale`
    /// (the request's, else the offer's default), which `max_width` and `max_height` bound (§3.4).
    ///
    /// `extend` and `retake` keep the source's size and frames (§3.2, §3.3): a source larger than the offer's size, or
    /// off its frame grid, is refused rather than cut down. A retake's span lies inside the source, and an extend's total
    /// (the source and `after`, in whole grid steps) within `max_frames` and `max_duration_s`.
    static func checkVideoSource(_ facts: VideoFacts, operation: String, limits: Descriptor.Limits?, scale: Int? = nil,
                                 grid: VideoProfile.FrameStep = .any, after: Double? = nil,
                                 span: (start: Double?, end: Double?) = (nil, nil), retake: String? = nil) throws {
        if ["video.extend", "video.retake"].contains(operation) {
            if !grid.admits(facts.frames) {
                let below = grid.floor(facts.frames).map { "\($0)" } ?? "none"
                throw MESError(.inputInvalid, "The video has \(facts.frames) frames; this model edits clips of \(grid.multiple)k + \(grid.offset) "
                               + "frames (the nearest below is \(below)), so it would change the clip's length.", param: VideoProfile.Input.video)
            }
            if operation == "video.retake", ["sound", "both"].contains(retake ?? ""), facts.audio == nil {
                throw MESError(.inputInvalid, "The video has no sound to retake.", param: VideoProfile.Param.retake)
            }
            let halfFrame = 0.5 / max(facts.frameRate, 1)
            if let start = span.start, start >= facts.durationSeconds {
                throw MESError(.outOfLimits, String(format: "start_s %g is past the %.3f s video.", start, facts.durationSeconds),
                               param: VideoProfile.Param.start)
            }
            if let end = span.end, end > facts.durationSeconds + halfFrame {
                throw MESError(.outOfLimits, String(format: "end_s %g is past the %.3f s video.", end, facts.durationSeconds),
                               param: VideoProfile.Param.end)
            }
        }
        guard let limits else { return }
        if ["video.extend", "video.retake"].contains(operation) {
            if let w = limits.maxWidth, facts.width > w {
                throw MESError(.outOfLimits, "The video is \(facts.width) pixels wide; this model edits at most \(w).", param: VideoProfile.Input.video)
            }
            if let h = limits.maxHeight, facts.height > h {
                throw MESError(.outOfLimits, "The video is \(facts.height) pixels high; this model edits at most \(h).", param: VideoProfile.Input.video)
            }
            var frames = facts.frames
            if operation == "video.extend", let after, after > 0 {
                let steps = max(1, Int((after * facts.frameRate / Double(grid.multiple)).rounded()))
                frames += steps * grid.multiple
            }
            let param = operation == "video.extend" ? VideoProfile.Param.after : VideoProfile.Input.video
            if let most = limits.value(VideoProfile.LimitField.maxFrames), Double(frames) > most {
                throw MESError(.outOfLimits, "The clip would have \(frames) frames; this model makes at most \(Int(most)).", param: param)
            }
            if let most = limits.maxDurationSeconds, Double(frames) / facts.frameRate > most + 0.0005 {
                throw MESError(.outOfLimits, String(format: "The clip would be %.2f s; this model makes at most %g s.", Double(frames) / facts.frameRate, most),
                               param: param)
            }
        }
        if let most = limits.value(VideoProfile.LimitField.maxSourceSeconds), facts.durationSeconds > most + 0.0005 {
            throw MESError(.outOfLimits, String(format: "The video is %.2f s; this model takes at most %g s.", facts.durationSeconds, most),
                           param: VideoProfile.Input.video)
        }
        if operation == "video.upscale", let scale {
            let (w, h) = (facts.width * scale, facts.height * scale)
            if let most = limits.maxWidth, w > most {
                throw MESError(.outOfLimits, "Upscaled \(scale)×, the \(facts.width)-pixel-wide video would be \(w) pixels wide; this model makes at most \(most).",
                               param: VideoProfile.Input.video)
            }
            if let most = limits.maxHeight, h > most {
                throw MESError(.outOfLimits, "Upscaled \(scale)×, the \(facts.height)-pixel-high video would be \(h) pixels high; this model makes at most \(most).",
                               param: VideoProfile.Input.video)
            }
        }
        if operation == "video.interpolate" {
            if let w = limits.maxWidth, facts.width > w {
                throw MESError(.outOfLimits, "The video is \(facts.width) pixels wide; this model takes at most \(w).", param: VideoProfile.Input.video)
            }
            if let h = limits.maxHeight, facts.height > h {
                throw MESError(.outOfLimits, "The video is \(facts.height) pixels high; this model takes at most \(h).", param: VideoProfile.Input.video)
            }
        }
    }

    /// A worker's video as the client gets it: the source's audio track and its markings (comment, copyright, …) put back
    /// when `keeping` names a source (upscale, interpolate: Video §1.7, §1.9), and the codec asked for. Without either
    /// change the file is kept as the worker wrote it. Sound and markings are copied, not re-encoded.
    ///
    /// `markings` names a source whose markings (not its sound) carry over: extend and retake, whose model makes the
    /// sound. `disclosure` is the comment item a generative operation's output carries (Video §1.9): it replaces the
    /// comment, or follows it when the source had one. `sound: false` leaves the audio track out (`audio: false`, §5.4).
    static func finishVideo(_ file: URL, keeping source: URL?, codec: String?, fps: Double? = nil, markings: URL? = nil,
                            disclosure: String? = nil, sound: Bool = true) async throws {
        if let fps { try await retime(file, fps: fps) }
        let made = AVURLAsset(url: file)
        let madeFacts = try await videoFacts(file)
        let wantsCodec = codec.map { ($0 == "h264" ? ["avc1"] : ["hvc1", "hev1"]).contains(madeFacts.codec) == false } ?? false
        // A track doesn't keep its asset alive: the source's asset lives as long as its track is used.
        let sourceAsset = source.map { AVURLAsset(url: $0) }
        let markingsAsset = markings.map { AVURLAsset(url: $0) }
        var sourceAudio: AVAssetTrack?
        var metadata: [AVMetadataItem] = []
        if let sourceAsset {
            sourceAudio = try await sourceAsset.loadTracks(withMediaType: .audio).first
            metadata = try await sourceAsset.load(.metadata)
        }
        if let markingsAsset { metadata = try await markingsAsset.load(.metadata) }
        let madeAudio = sound ? try await made.loadTracks(withMediaType: .audio).first : nil
        if !sound { sourceAudio = nil }
        let dropsSound = !sound && madeFacts.audio != nil
        guard wantsCodec || (sourceAudio != nil && madeAudio == nil) || !metadata.isEmpty || disclosure != nil || dropsSound else { return }
        if metadata.isEmpty { metadata = try await made.load(.metadata) }
        if let disclosure { metadata = try await Self.disclosed(metadata, disclosure) }

        let composition = AVMutableComposition()
        guard let video = try await made.loadTracks(withMediaType: .video).first,
              let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MESError(.engineError, "The model's video has no picture.")
        }
        let range = try await video.load(.timeRange)
        try track.insertTimeRange(range, of: video, at: .zero)
        track.preferredTransform = try await video.load(.preferredTransform)
        if let audio = madeAudio ?? sourceAudio,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            // The sound lasts no longer than the picture: duration changes by less than a source frame (§3.5). AAC is
            // copied in whole packets of 1024 samples, so it is cut at the last packet that ends inside the picture.
            let available = try await audio.load(.timeRange)
            var length = CMTimeMinimum(available.duration, range.duration)
            if let format = try await audio.load(.formatDescriptions).first,
               let rate = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee.mSampleRate, rate > 0 {
                let packets = (length.seconds * rate / 1024).rounded(.down)
                length = CMTime(value: CMTimeValue(packets * 1024), timescale: CMTimeScale(rate))
            }
            try audioTrack.insertTimeRange(CMTimeRange(start: available.start, duration: length), of: audio, at: .zero)
        }
        let preset = !wantsCodec ? AVAssetExportPresetPassthrough
            : codec == "h264" ? AVAssetExportPresetHighestQuality : AVAssetExportPresetHEVCHighestQuality
        guard let export = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw MESError(.engineError, "Gaea can't write the video's final file.")
        }
        export.metadata = metadata
        let temporary = file.deletingLastPathComponent().appending(path: ".finished-\(UUID().uuidString).mp4")
        try await export.export(to: temporary, as: .mp4)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
        withExtendedLifetime((made, sourceAsset, markingsAsset)) {}
    }

    /// `metadata` with its comment item saying `disclosure`: the comment alone when there was none or it already says
    /// AI-generated, else the old comment followed by it.
    static func disclosed(_ metadata: [AVMetadataItem], _ disclosure: String) async throws -> [AVMetadataItem] {
        let comments: Set<AVMetadataIdentifier> = [.iTunesMetadataUserComment, .quickTimeMetadataComment, .commonIdentifierDescription]
        var kept: [AVMetadataItem] = []
        var old: String?
        for item in metadata {
            if let id = item.identifier, comments.contains(id) {
                if old == nil, let text = try? await item.load(.stringValue), !text.isEmpty { old = text }
            } else {
                kept.append(item)
            }
        }
        let comment = AVMutableMetadataItem()
        comment.identifier = .iTunesMetadataUserComment
        comment.extendedLanguageTag = "und"
        comment.value = (old.map { $0.contains("AI-generated") ? $0 : "\($0) — \(disclosure)" } ?? disclosure) as NSString
        return kept + [comment]
    }
}
