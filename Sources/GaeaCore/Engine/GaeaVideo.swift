import AVFoundation
import Foundation
import MESCore

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
