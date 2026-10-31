import AVFoundation
import Foundation
import GaeaProtocol
import MESCore
import Testing
@testable import GaeaCore

/// AB-T-0400: video media for workers (GPP-1 §3.3.3), lanes a slow volume can't feed (§3.2.1), and previews (§3.3).
@Suite struct VideoTests {
    /// A `frames`-frame clip at 24 fps, `width`×`height`, in `codec` inside a QuickTime file.
    func clip(_ url: URL, codec: AVVideoCodecType, frames: Int = 24, width: Int = 64, height: Int = 48) async throws {
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
            memset(CVPixelBufferGetBaseAddress(buffer!), Int32(i * 10 % 255), CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 24))
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
}
