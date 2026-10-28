import CryptoKit
import Foundation
import GaeaProtocol
import MESCore
import MESEngineCore
import Testing
@testable import GaeaCore

/// AB-T-0364: a plugin's own MES offers, run as themselves, with their files as the job's outputs.
@Suite(.serialized) struct OfferRoutingTests {
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "gaea-offers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    static let imageSpecs = [OutputSpec(name: "images", kind: .image, mediaTypes: ["image/png"], min: 1, max: 8)]

    /// A one-pixel PNG, written the way a worker would.
    func png(at url: URL) throws {
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
        try bytes.write(to: url)
    }

    @Test func filesMoveUnchangedAndValuesBecomeData() throws {
        let dir = try scratch()
        let worker = dir.appending(path: "out/worker"), out = dir.appending(path: "out")
        try FileManager.default.createDirectory(at: worker, withIntermediateDirectories: true)
        let a = worker.appending(path: "image-0.png"), b = worker.appending(path: "image-1.png")
        try png(at: a)
        try png(at: b)
        let hash = try sha256(a)
        let result: [String: GaeaProtocol.JSONValue] = ["type": "result", "outputs": [
            ["name": "images", "path": .string(a.path), "media_type": "image/png"],
            ["name": "caption", "value": ["text": "a pixel"]],
        ]]
        // A streamed piece the result doesn't list again comes after the result's own.
        let chunks: [[String: GaeaProtocol.JSONValue]] = [["type": "chunk", "output": "images", "index": 1, "path": .string(b.path), "media_type": "image/png"]]
        let outputs = try GaeaEngine.producedOutputs(result: result, chunks: chunks, workerDirectory: worker, outputDirectory: out,
                                                     specs: Self.imageSpecs)
        #expect(outputs.map(\.name) == ["images", "caption", "images"])
        #expect(outputs[0].kind == .image && outputs[0].width == 1 && outputs[0].height == 1)
        #expect(try sha256(#require(outputs[0].file)) == hash, "the PNG was re-encoded")
        #expect(outputs[0].file?.lastPathComponent == "images-0.png" && outputs[2].file?.lastPathComponent == "images-1.png")
        #expect(!FileManager.default.fileExists(atPath: a.path), "moved, not copied")
        #expect(outputs[1].kind == .data && outputs[1].value?["text"]?.stringValue == "a pixel")
    }

    @Test func aChunkTheResultListsIsNotCountedTwice() throws {
        let dir = try scratch()
        let worker = dir.appending(path: "worker")
        try FileManager.default.createDirectory(at: worker, withIntermediateDirectories: true)
        let a = worker.appending(path: "a.png")
        try png(at: a)
        let result: [String: GaeaProtocol.JSONValue] = ["outputs": [["name": "images", "path": .string(a.path), "media_type": "image/png"]]]
        let chunks: [[String: GaeaProtocol.JSONValue]] = [["output": "images", "index": 0, "path": .string(a.path), "media_type": "image/png"]]
        let outputs = try GaeaEngine.producedOutputs(result: result, chunks: chunks, workerDirectory: worker, outputDirectory: dir,
                                                     specs: Self.imageSpecs)
        #expect(outputs.count == 1)
    }

    @Test func aFileOutsideOutputDirIsRefused() throws {
        let dir = try scratch()
        let worker = dir.appending(path: "worker")
        try FileManager.default.createDirectory(at: worker, withIntermediateDirectories: true)
        let outside = dir.appending(path: "elsewhere.png")
        try png(at: outside)
        // A symlink inside output_dir that points out is outside too.
        let link = worker.appending(path: "link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        for path in [outside.path, link.path, worker.appending(path: "../elsewhere.png").path] {
            let result: [String: GaeaProtocol.JSONValue] = ["outputs": [["name": "images", "path": .string(path), "media_type": "image/png"]]]
            #expect(throws: MESError.self, "\(path)") {
                try GaeaEngine.producedOutputs(result: result, chunks: [], workerDirectory: worker, outputDirectory: dir,
                                               specs: Self.imageSpecs)
            }
        }
        #expect(FileManager.default.fileExists(atPath: outside.path), "a refused file is left alone")
    }

    @Test func textAndDataInputsTravelAsFiles() throws {
        let dir = try scratch()
        let image = dir.appending(path: "in.png")
        try png(at: image)
        let paths = try GaeaEngine.inputPaths([
            "prompt": [.text("a lighthouse at dusk")],
            "points": [.data(.array([.object(["x": 0.5, "y": 0.5, "label": "include"])]))],
            "images": [.file(image, mediaType: "image/png"), .file(image, mediaType: "image/png")],
        ], writingTextTo: dir.appending(path: "worker-inputs"))
        let prompt = try #require(paths["prompt"]?.stringValue)
        #expect(try String(contentsOfFile: prompt, encoding: .utf8) == "a lighthouse at dusk")
        #expect(paths["points"]?.stringValue?.hasSuffix(".json") == true)
        #expect(paths["images"]?.arrayValue?.count == 2)
    }

    @Test func descriptorLimitsAreTheLargestEveryOfferAllows() {
        let limits = GaeaEngine.limits([PluginManifest.Limits(maxPixels: 2_359_296, maxSide: 1536),
                                        PluginManifest.Limits(maxPixels: 4_194_304, maxSide: 2048)], else: nil)
        #expect(limits?.maxWidth == 2048 && limits?.maxMegapixels == 4.194304)
        // One offer that doesn't say leaves the profile's limits as they were.
        let open = GaeaEngine.limits([PluginManifest.Limits(maxSide: 1536), nil], else: Descriptor.Limits(maxWidth: 8192))
        #expect(open?.maxWidth == 8192)
    }

    /// The real thing: demo 0.3.0's signed bundle answers `image.generate` with PNGs under `output_dir`, and the host's
    /// collection hands them to MES byte for byte. Needs the bundle built next door (`scripts/build-plugin.sh`).
    @Test(.enabled(if: FileManager.default.fileExists(atPath: WorkerProcessTests.demo.appending(path: "Contents/Resources/manifest.json").path)
          && ((try? JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: WorkerProcessTests.demo
                .appending(path: "Contents/Resources/manifest.json"))))?.offers.isEmpty == false)))
    func theDemoGradientsPNGsReachMESUnchanged() async throws {
        let dir = try scratch()
        let manifestData = try Data(contentsOf: WorkerProcessTests.demo.appending(path: "Contents/Resources/manifest.json"))
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: manifestData)
        let worker = WorkerProcess(pluginID: manifest.id, version: manifest.version, bundle: WorkerProcessTests.demo, manifest: manifest,
                                   manifestData: manifestData, cacheRoot: dir, log: dir.appending(path: "w.log"), sessions: dir)
        _ = try await worker.start()
        try await worker.configure(budget: WorkerBudgetWire(ceilingBytes: 8_000_000_000), modelsRoot: dir, cacheRoot: dir, settings: [:])
        try await worker.prepare(model: "demo-gradient", lane: "fp32")
        let out = dir.appending(path: "spool/job_g/out"), workerDir = out.appending(path: "worker")
        let inputs = try GaeaEngine.inputPaths(["prompt": [.text("a lighthouse at dusk")]], writingTextTo: out.appending(path: "worker-inputs"))
        let result = try await worker.request("run", [
            "job": "job_g", "operation": "image.generate", "model": "demo-gradient", "lane": "fp32", "inputs": .object(inputs),
            "params": ["size": ["width": 645, "height": 480], "count": 2], "model_params": ["x-gaea.gradient_angle": 30],
            "seed": 7, "output_dir": .string(workerDir.path),
        ], finals: ["result"])
        let written = try (result["outputs"]?.arrayValue ?? []).map { try sha256(URL(fileURLWithPath: #require($0["path"]?.stringValue))) }
        #expect(written.count == 2)
        #expect(result["warnings"]?.arrayValue?.first?["code"]?.stringValue == "size_snapped")
        #expect(result["effective"]?["size"]?["width"]?.intValue == 640)

        let outputs = try GaeaEngine.producedOutputs(result: result, chunks: [], workerDirectory: workerDir, outputDirectory: out,
                                                     specs: Self.imageSpecs)
        #expect(try outputs.map { try sha256(#require($0.file)) } == written)
        #expect(outputs.allSatisfy { $0.kind == .image && $0.mediaType == "image/png" && $0.width == 640 && $0.height == 480 })
        #expect(written[0] != written[1], "count 2 gives seeds 7 and 8")
        _ = await worker.stop(unloading: ["demo-gradient"])
    }
}
