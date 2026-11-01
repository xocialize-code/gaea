import AVFoundation
import Foundation
import GaeaProtocol
import MESCore
import Testing
@testable import GaeaCore

/// AB-T-0400: video media for workers (GPP-1 §3.3.3), lanes a slow volume can't feed (§3.2.1), and previews (§3.3).
@Suite struct VideoTests {
    /// A `frames`-frame clip at 24 fps (or `fps` placed on a 1/600 time base, as frame-stream-native writes), `width`×`height`,
    /// in `codec` inside a QuickTime file.
    func clip(_ url: URL, codec: AVVideoCodecType, frames: Int = 24, width: Int = 64, height: Int = 48, fps600: Double? = nil,
              base: Int = 0) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), Int32((base + i * 10) % 255), CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            let time = fps600.map { CMTime(value: CMTimeValue((Double(i) * 600 / $0).rounded()), timescale: 600) }
                ?? CMTime(value: CMTimeValue(i), timescale: 24)
            adaptor.append(buffer!, withPresentationTime: time)
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gaea-video-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func aProResMovieBecomesACanonicalMP4OfTheSameFrames() async throws {
        let dir = try folder()
        let mov = dir.appending(path: "in.mov")
        try await clip(mov, codec: .proRes422)
        let facts = try await GaeaEngine.videoFacts(mov)
        #expect(facts.container == "mov" && facts.codec == "apcn" && !facts.isCanonical)
        #expect((facts.width, facts.height, facts.frames) == (64, 48, 24) && abs(facts.frameRate - 24) < 0.01)
        let out = try await GaeaEngine.workerVideo(mov, name: "video-0", into: dir)
        #expect(out != mov && out.pathExtension == "mp4")
        let converted = try await GaeaEngine.videoFacts(out)
        #expect(converted.isCanonical, "\(converted)")
        #expect((converted.width, converted.height, converted.frames) == (64, 48, 24) && abs(converted.frameRate - 24) < 0.01)
        // A canonical file passes through untouched.
        #expect(try await GaeaEngine.workerVideo(out, name: "video-1", into: dir) == out)
    }

    @Test func anH264MovieIsRemuxed() async throws {
        let dir = try folder()
        let mov = dir.appending(path: "h264.mov")
        try await clip(mov, codec: .h264, frames: 12)
        let out = try await GaeaEngine.workerVideo(mov, name: "video-0", into: dir)
        let facts = try await GaeaEngine.videoFacts(out)
        #expect(facts.isCanonical && facts.codec == "avc1" && facts.frames == 12)
    }

    @Test func somethingElseIsInputInvalid() async throws {
        let junk = try folder().appending(path: "junk.mp4")
        try Data("not a video".utf8).write(to: junk)
        await #expect(throws: MESError.self) { try await GaeaEngine.videoFacts(junk) }
    }

    /// The z-image example's model, its bf16 lane given a floor and made the default.
    func model(bf16Floor: UInt64) throws -> PluginManifest.Model {
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: repoRoot.appending(path: "examples/v1/manifest/z-image.json"))) as! [String: Any]
        var models = json["models"] as! [[String: Any]]
        var lanes = models[0]["lanes"] as! [[String: Any]]
        for i in lanes.indices {
            let id = lanes[i]["id"] as! String
            lanes[i]["default"] = id == "bf16"
            if id == "bf16" {
                var resolved = lanes[i]["resolved"] as! [String: Any]
                resolved["minSustainedReadBytesPerSecond"] = bf16Floor
                lanes[i]["resolved"] = resolved
            }
        }
        models[0]["lanes"] = lanes
        json["models"] = models
        return try JSONDecoder().decode(PluginManifest.self, from: JSONSerialization.data(withJSONObject: json)).models[0]
    }

    @Test func lanesTheVolumeIsTooSlowForAreSkipped() throws {
        let m = try model(bf16Floor: 1_000_000_000)
        #expect(m.lanes.first { $0.id == "bf16" }?.resolved.minSustainedReadBytesPerSecond == 1_000_000_000)
        // Nothing measured yet: every lane stays.
        #expect(try StorageFloor.filter(m, read: nil, named: nil).model.lanes.count == m.lanes.count)
        // A volume at 450 MB/s: bf16 goes, the first lane left becomes the default, reported as skipped from bf16.
        let (kept, skipped) = try StorageFloor.filter(m, read: 450_000_000, named: nil)
        #expect(!kept.lanes.contains { $0.id == "bf16" } && kept.lanes.count == m.lanes.count - 1 && skipped?.id == "bf16")
        #expect(kept.lanes.filter(\.default).map(\.id) == [kept.lanes[0].id])
        // A request that names bf16 is refused, never moved.
        #expect(throws: LaneChoice.Refusal.self) { try StorageFloor.filter(m, read: 450_000_000, named: "bf16") }
        // Fast enough: nothing skipped.
        #expect(try StorageFloor.filter(m, read: 2_000_000_000, named: nil).skipped == nil)
    }

    @Test func aModelNoLaneOfWhichFitsTheBudgetIsntOffered() throws {
        let m = try model(bf16Floor: 1_000_000_000)
        let smallest = m.lanes.map(LaneChoice.need).min()!
        #expect(PluginOffers.fits(m, budget: smallest))
        #expect(!PluginOffers.fits(m, budget: smallest - 1))
    }

    @Test func aPreviewIsReadFromTheRunAndDeleted() throws {
        let dir = try folder()
        let frame = dir.appending(path: "preview-1.png")
        try Data([1, 2, 3]).write(to: frame)
        let root = dir.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let line: [String: GPPValue] = ["type": "progress", "preview": ["path": .string(frame.path), "media_type": "image/png"]]
        let preview = GaeaEngine.preview(line, root: root)
        #expect(preview?.data == Data([1, 2, 3]) && preview?.mediaType == "image/png")
        #expect(!FileManager.default.fileExists(atPath: frame.path))
        // Outside the run's folder: dropped.
        let outside: [String: GPPValue] = ["type": "progress", "preview": ["path": "/etc/hosts", "media_type": "image/png"]]
        #expect(GaeaEngine.preview(outside, root: root) == nil)
    }

    // MARK: The Video profile (AB-T-0401)

    @Test func fpsBecomesTheNearestFactorItAdmits() {
        var limits = Descriptor.Limits()
        limits.profile["max_factor"] = 4
        #expect(GaeaEngine.interpolationFactor(fps: nil, factor: nil, sourceFPS: 24, limits: limits).0 == 2)
        #expect(GaeaEngine.interpolationFactor(fps: nil, factor: 3, sourceFPS: 24, limits: limits).0 == 3)
        let exact = GaeaEngine.interpolationFactor(fps: 48, factor: nil, sourceFPS: 24, limits: limits)
        #expect(exact.0 == 2 && exact.1 == nil)
        let near = GaeaEngine.interpolationFactor(fps: 60, factor: nil, sourceFPS: 24, limits: limits)
        #expect(near.0 == 3 && near.1?.code == "fps_adjusted")
        #expect(GaeaEngine.interpolationFactor(fps: 240, factor: nil, sourceFPS: 24, limits: limits).0 == 4)
    }

    @Test func aSourceOverTheLimitsIsOutOfLimits() throws {
        let facts = GaeaEngine.VideoFacts(durationSeconds: 70, frameRate: 24, frames: 1680, width: 3840, height: 2160, codec: "avc1",
                                          audio: nil, container: "mp4")
        var limits = Descriptor.Limits(maxWidth: 3840, maxHeight: 2160)
        try GaeaEngine.checkVideoSource(facts, operation: "video.interpolate", limits: limits)
        limits.profile["max_source_s"] = 60
        #expect(throws: MESError.self) { try GaeaEngine.checkVideoSource(facts, operation: "video.interpolate", limits: limits) }
        limits = Descriptor.Limits(maxWidth: 1920, maxHeight: 1080)
        #expect(throws: MESError.self) { try GaeaEngine.checkVideoSource(facts, operation: "video.interpolate", limits: limits) }

        // upscale bounds the output: 960×540 × 2 fits 1920×1080, × 4 doesn't.
        let small = GaeaEngine.VideoFacts(durationSeconds: 1, frameRate: 24, frames: 24, width: 960, height: 540, codec: "avc1",
                                          audio: nil, container: "mp4")
        try GaeaEngine.checkVideoSource(small, operation: "video.upscale", limits: limits, scale: 2)
        #expect(throws: MESError.self) { try GaeaEngine.checkVideoSource(small, operation: "video.upscale", limits: limits, scale: 4) }
        #expect(throws: MESError.self) { try GaeaEngine.checkVideoSource(facts, operation: "video.upscale", limits: limits, scale: 2) }
    }

    /// A 1 s source with an AAC track and a comment, as a client might send.
    func sourceWithSound(_ dir: URL, comment text: String = "AI-generated by Test Model", name: String = "source") async throws -> URL {
        let picture = dir.appending(path: "\(name)-picture.mov")
        try await clip(picture, codec: .h264)
        let sound = dir.appending(path: "\(name)-sound.m4a")
        do {   // The file is finished when the writer is released.
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
            let file = try AVAudioFile(forWriting: sound, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
                                                                     AVNumberOfChannelsKey: 2])
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
            buffer.frameLength = 48000
            for c in 0..<2 { for i in 0..<48000 { buffer.floatChannelData![c][i] = Float(sin(Double(i) * 0.05)) * 0.3 } }
            try file.write(from: buffer)
        }
        let composition = AVMutableComposition()
        let pictureAsset = AVURLAsset(url: picture), soundAsset = AVURLAsset(url: sound)
        defer { withExtendedLifetime((pictureAsset, soundAsset)) {} }
        let v = try await pictureAsset.loadTracks(withMediaType: .video)[0]
        let a = try await soundAsset.loadTracks(withMediaType: .audio)[0]
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            .insertTimeRange(try await v.load(.timeRange), of: v, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            .insertTimeRange(try await a.load(.timeRange), of: a, at: .zero)
        let comment = AVMutableMetadataItem()
        comment.identifier = .iTunesMetadataUserComment
        comment.value = text as NSString
        comment.extendedLanguageTag = "und"
        let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        export.metadata = [comment]
        let out = dir.appending(path: "\(name).mp4")
        try await export.export(to: out, as: .mp4)
        return out
    }

    @Test func aTransformationKeepsTheSourcesSoundAndMarking() async throws {
        let dir = try folder()
        let source = try await sourceWithSound(dir)
        let sourceFacts = try await GaeaEngine.videoFacts(source)
        #expect(sourceFacts.audio?.codec == "aac " && sourceFacts.isCanonical)
        // What a frame-stream model writes: the picture alone, in HEVC.
        let mov = dir.appending(path: "model.mov")
        try await clip(mov, codec: .hevc, frames: 47)
        let made = try await GaeaEngine.workerVideo(mov, name: "made", into: dir)
        #expect(try await GaeaEngine.videoFacts(made).audio == nil)
        try await GaeaEngine.finishVideo(made, keeping: source, codec: nil)
        let facts = try await GaeaEngine.videoFacts(made)
        #expect(facts.frames == 47 && facts.codec == "hvc1", "\(facts)")
        #expect(facts.audio?.sampleRate == 48000 && facts.audio?.channels == 2 && facts.audio?.codec == "aac ")
        let comments = try await AVURLAsset(url: made).load(.metadata).filter { $0.identifier == .iTunesMetadataUserComment }
        #expect(try await comments.first?.load(.stringValue) == "AI-generated by Test Model")
    }

    @Test func aGeneratedClipSaysItIsAIGeneratedAndCanLoseItsSound() async throws {
        let dir = try folder()
        // What LTX writes: picture and sound, no comment of Gaea's.
        let made = try await sourceWithSound(dir, comment: "Lavf", name: "made")
        try await GaeaEngine.finishVideo(made, keeping: nil, codec: nil, disclosure: "AI-generated by LTX 2.5", sound: false)
        let facts = try await GaeaEngine.videoFacts(made)
        #expect(facts.audio == nil && facts.frames == 24, "\(facts)")
        let comments = try await AVURLAsset(url: made).load(.metadata).filter { $0.identifier == .iTunesMetadataUserComment }
        #expect(comments.count == 1)
        #expect(try await comments.first?.load(.stringValue) == "Lavf — AI-generated by LTX 2.5")
    }

    @Test func anEditKeepsTheSourcesMarkingAndAddsTheDisclosure() async throws {
        let dir = try folder()
        let source = try await sourceWithSound(dir, comment: "Shot by Pat", name: "source")
        let made = try await sourceWithSound(dir, comment: "", name: "made")
        try await GaeaEngine.finishVideo(made, keeping: nil, codec: nil, markings: source, disclosure: "AI-generated in part by LTX 2.5")
        let facts = try await GaeaEngine.videoFacts(made)
        #expect(facts.audio?.sampleRate == 48000, "\(facts)")
        let comments = try await AVURLAsset(url: made).load(.metadata).filter { $0.identifier == .iTunesMetadataUserComment }
        #expect(try await comments.first?.load(.stringValue) == "Shot by Pat — AI-generated in part by LTX 2.5")
        // A source already marked keeps its marking as it is.
        let marked = try await sourceWithSound(dir, name: "marked")
        let again = try await sourceWithSound(dir, comment: "", name: "again")
        try await GaeaEngine.finishVideo(again, keeping: nil, codec: nil, markings: marked, disclosure: "AI-generated in part by LTX 2.5")
        let kept = try await AVURLAsset(url: again).load(.metadata).filter { $0.identifier == .iTunesMetadataUserComment }
        #expect(try await kept.first?.load(.stringValue) == "AI-generated by Test Model")
    }

    @Test func anEditKeepsTheSourcesSizeAndFramesOrIsRefused() throws {
        let grid = VideoProfile.FrameStep(multiple: 8, offset: 1)
        let clip = GaeaEngine.VideoFacts(durationSeconds: 17.0 / 24, frameRate: 24, frames: 17, width: 128, height: 96, codec: "avc1",
                                         audio: nil, container: "mp4")
        var limits = Descriptor.Limits(maxWidth: 704, maxHeight: 512)
        limits.profile["max_frames"] = 121
        try GaeaEngine.checkVideoSource(clip, operation: "video.retake", limits: limits, grid: grid, span: (0.4, 0.7))
        try GaeaEngine.checkVideoSource(clip, operation: "video.extend", limits: limits, grid: grid, after: 1)
        func refused(_ code: MESErrorCode, _ param: String, _ body: () throws -> Void) {
            #expect { try body() } throws: { ($0 as? MESError)?.code == code.rawValue && ($0 as? MESError)?.param == param }
        }
        var off = clip; off.frames = 24
        refused(.inputInvalid, "video") { try GaeaEngine.checkVideoSource(off, operation: "video.retake", limits: limits, grid: grid) }
        refused(.outOfLimits, "end_s") { try GaeaEngine.checkVideoSource(clip, operation: "video.retake", limits: limits, grid: grid, span: (0.4, 0.9)) }
        refused(.outOfLimits, "start_s") { try GaeaEngine.checkVideoSource(clip, operation: "video.retake", limits: limits, grid: grid, span: (0.8, 0.9)) }
        // 17 frames and 5 s at 24 fps (120 frames) is 137, past 121.
        refused(.outOfLimits, "after_s") { try GaeaEngine.checkVideoSource(clip, operation: "video.extend", limits: limits, grid: grid, after: 5) }
        var wide = clip; wide.width = 1280
        refused(.outOfLimits, "video") { try GaeaEngine.checkVideoSource(wide, operation: "video.extend", limits: limits, grid: grid, after: 1) }
    }

    /// Each frame's brightness (the blue byte at the centre), in display order.
    func shades(_ url: URL) async throws -> [Int] {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.startReading()
        var out: [Int] = []
        while let sample = output.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(sample) {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let row = CVPixelBufferGetBytesPerRow(buffer), base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            out.append(Int(base[row * (CVPixelBufferGetHeight(buffer) / 2) + 4 * (CVPixelBufferGetWidth(buffer) / 2)]))
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        return out
    }

    @Test func anEditKeepsTheSourcesOwnFramesOutsideWhatItRemade() async throws {
        let dir = try folder()
        let sourceMov = dir.appending(path: "source.mov"), madeMov = dir.appending(path: "made.mov")
        try await clip(sourceMov, codec: .h264, frames: 17)
        try await clip(madeMov, codec: .h264, frames: 17, base: 7)
        let source = try await GaeaEngine.workerVideo(sourceMov, name: "source", into: dir)
        let made = try await GaeaEngine.workerVideo(madeMov, name: "made", into: dir)
        // A retake of 9–16 (0.375–0.708 s): frames 0–8 are the source's.
        let kept = GaeaEngine.keptFrames(operation: "video.retake", effective: ["start_s": .number(9.0 / 24), "end_s": .number(17.0 / 24)],
                                         sourceFrames: 17, fps: 24, overlap: 0)
        #expect(kept == [0..<9])
        try await GaeaEngine.keepSourceFrames(made, source: source, kept: kept)
        let got = try await shades(made), want = (0..<17).map { ($0 < 9 ? 0 : 7) + $0 * 10 }
        #expect(got.count == 17)
        for (g, w) in zip(got, want) { #expect(abs(g - w) <= 4, "\(got) vs \(want)") }
        // An extend reworks overlap_s before the join; a sound retake keeps every frame.
        #expect(GaeaEngine.keptFrames(operation: "video.extend", effective: [:], sourceFrames: 17, fps: 24, overlap: 0.5) == [0..<5])
        #expect(GaeaEngine.keptFrames(operation: "video.retake", effective: ["retake": "sound"], sourceFrames: 17, fps: 24, overlap: 0) == [0..<17])
    }

    @Test func anOfferAskingForTheOperatorsAcceptanceIsOptIn() {
        var offer = ModelOffer(id: "ltx", title: "LTX", license: License(spdx: "LicenseRef-LTX-2-Community", commercialUse: .yes),
                               memoryClass: .large, speedClass: .slow, qualityTiers: [.draft])
        #expect(!offer.isOptIn)
        offer.license.acceptedRequired = true
        #expect(offer.isOptIn)
        offer.license.acceptedRequired = nil
        offer.namedOnly = true
        #expect(offer.isOptIn)
    }

    @Test func theCodecAskedForIsWritten() async throws {
        let dir = try folder()
        let mov = dir.appending(path: "hevc.mov")
        try await clip(mov, codec: .hevc, frames: 12)
        let made = try await GaeaEngine.workerVideo(mov, name: "made", into: dir)
        try await GaeaEngine.finishVideo(made, keeping: nil, codec: "h264")
        let facts = try await GaeaEngine.videoFacts(made)
        #expect(facts.codec == "avc1" && facts.frames == 12 && facts.isCanonical, "\(facts)")
        // Already in the codec asked for, and nothing to keep: untouched.
        let before = try Data(contentsOf: made)
        try await GaeaEngine.finishVideo(made, keeping: nil, codec: "h264")
        #expect(try Data(contentsOf: made) == before)
    }

    @Test func aClipOffItsRateIsRetimedWithoutReencoding() async throws {
        let dir = try folder()
        let mov = dir.appending(path: "uneven.mov")
        try await clip(mov, codec: .hevc, frames: 65, fps600: 96)
        let file = try await GaeaEngine.workerVideo(mov, name: "uneven", into: dir)
        let before = try await GaeaEngine.videoFacts(file)
        #expect(abs(before.frameRate - 96) > 0.001, "\(before)")
        try await GaeaEngine.retime(file, fps: 96)
        let after = try await GaeaEngine.videoFacts(file)
        #expect(abs(after.frameRate - 96) < 0.001 && after.frames == 65 && after.codec == before.codec, "\(after)")
        #expect(abs(after.durationSeconds - 65.0 / 96) < 0.0005)
        // Already exact: untouched.
        let data = try Data(contentsOf: file)
        try await GaeaEngine.retime(file, fps: 96)
        #expect(try Data(contentsOf: file) == data)
    }
}
