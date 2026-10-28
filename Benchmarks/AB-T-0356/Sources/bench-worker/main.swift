import BenchShared
import Foundation
import GaeaPluginKit
import GaeaProtocol
import MLX
import MLXToolKit
import MLXZImage

// The AB-T-0356 bench worker: a GaeaPluginKit worker, packaged and signed like any plugin by
// scripts/build.sh, but never published.
//
// - z-image-turbo: Z-Image Turbo through MLXServeEngine (z-image-swift 0.5.4), lane int4.
// - probe: the plugin's own code. `x-bench.gpu-touch` runs one small matmul, so MLX and the Metal
//   device are up with no model loaded. `x-bench.spool` reads its input files, then writes the same
//   number back to output_dir, and reports how long each half took.

// The host reads this from stderr: when the process reached main, on the shared clock.
FileHandle.standardError.write(Data("bench: main \(Clock.now())\n".utf8))

let modelsRoot = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/MLXEngine/Models",
                     isDirectory: true)

/// Builds the Z-Image request from the job; the same request bench-inproc sends.
let zimageGenerate = EngineOperation("x-bench.zimage.generate", outputNames: ["image": "image"]) { job in
    let width = job.param("width")?.intValue ?? 1024
    let height = job.param("height")?.intValue ?? 1024
    let steps = job.param("steps")?.intValue ?? 8
    let prompt = job.param("prompt")?.stringValue ?? ""
    return EngineCall(T2IRequest(prompt: prompt, width: width, height: height, steps: steps, seed: job.seed),
                      effective: ["width": .int(Int64(width)), "height": .int(Int64(height)),
                                  "steps": .int(Int64(steps))])
}

struct NoWeights: PackageConfiguration, BundledWeightSourcing {
    var bundledWeightSources: [BundledWeightSource] { [] }
}

let probeManifest = PackageManifest(
    license: LicenseDeclaration(weightLicense: .apache2, portCodeLicense: .apache2),
    provenance: Provenance(sourceRepo: "xocialize/gaea", revision: "AB-T-0356", tier: 1),
    requirements: RequirementsManifest(
        footprints: [QuantFootprint(quant: .fp32, residentBytes: 0, peakActivationBytes: 256_000_000)],
        requiredBackends: [.metalGPU]),
    surfaces: [])

final class ProbeModel: PluginModel, @unchecked Sendable {
    func prepare(lane: LaneDefinition, context: WorkerContext) async throws {}

    func unload() async { Memory.clearCache() }

    func run(_ job: Job, context: RunContext) async throws -> RunResult {
        switch job.operation {
        case "x-bench.gpu-touch":
            let start = Clock.now()
            let a = MLXRandom.normal([256, 256])
            let c = matmul(a, a)
            eval(c)
            let sum = c.sum().item(Float.self)
            return RunResult(outputs: [.value("gpu", ["device": .string("\(Device.defaultDevice())"),
                                                      "sum": .double(Double(sum)),
                                                      "seconds": .double(secs(start))])])
        case "x-bench.spool":
            return try spool(job)
        default:
            throw GPPError(.unsupportedOperation, "probe doesn't do \(job.operation)")
        }
    }

    /// Read every input (file bytes, then decode), then write as many outputs (encode, then bytes).
    /// `work: noop` touches nothing, so the run measures the message round trip alone.
    func spool(_ job: Job) throws -> RunResult {
        guard let format = SpoolFormat(rawValue: job.param("format")?.stringValue ?? "") else {
            throw GPPError(.invalidRequest, "format is raw, png or tiff16")
        }
        let width = job.param("width")?.intValue ?? 0
        let height = job.param("height")?.intValue ?? 0
        let parallel = job.param("parallel")?.boolValue ?? false
        let inputs = job.inputs["frames"] ?? []
        if job.param("work")?.stringValue == "noop" {
            return RunResult(outputs: [.value("timing", ["count": .int(Int64(inputs.count))])])
        }
        let n = inputs.count
        let lock = NSLock()
        var files = [Data](repeating: Data(), count: n)
        var pixels = [Pixels?](repeating: nil, count: n)

        let t0 = Clock.now()
        forEach(n, parallel: parallel) { i in
            let data = try! readFile(inputs[i])
            lock.lock(); files[i] = data; lock.unlock()
        }
        let t1 = Clock.now()
        forEach(n, parallel: parallel) { i in
            lock.lock(); let data = files[i]; lock.unlock()
            let p = decode(data, as: format, width: width, height: height)
            lock.lock(); pixels[i] = p; lock.unlock()
        }
        let t2 = Clock.now()
        let bytesIn = files.reduce(0) { $0 + $1.count }
        files = []

        var encoded = [Data](repeating: Data(), count: n)
        forEach(n, parallel: parallel) { i in
            lock.lock(); let p = pixels[i]!; lock.unlock()
            let data = encode(p, as: format)
            lock.lock(); encoded[i] = data; lock.unlock()
        }
        let t3 = Clock.now()
        var outputs: [Output] = []
        let urls = (0..<n).map { job.outputDir.appending(path: String(format: "out_%04d.%@", $0, format.fileExtension)) }
        forEach(n, parallel: parallel) { i in
            lock.lock(); let data = encoded[i]; lock.unlock()
            try! writeFile(data, to: urls[i])
        }
        let t4 = Clock.now()
        let bytesOut = encoded.reduce(0) { $0 + $1.count }
        for url in urls { outputs.append(.file("frames", url, mediaType: format.mediaType)) }
        outputs.append(.value("timing", [
            "count": .int(Int64(n)), "bytes_in": .int(Int64(bytesIn)), "bytes_out": .int(Int64(bytesOut)),
            "read_io_s": .double(secs(t0, t1)), "read_decode_s": .double(secs(t1, t2)),
            "write_encode_s": .double(secs(t2, t3)), "write_io_s": .double(secs(t3, t4)),
        ]))
        return RunResult(outputs: outputs)
    }
}

let bench = GaeaPluginDefinition(
    id: "com.xocialize.gaea.bench-ab-t-0356",
    version: "0.1.0",
    team: "CFZS6RXUCP",
    repo: "https://github.com/xocialize/gaea",
    title: "AB-T-0356 bench worker",
    summary: "Measures what running a model out of process costs. Not published.",
    license: "Apache-2.0",
    executable: "bench-worker",
    models: [
        .engine(ZImageTurboT2IPackage.self, id: "z-image-turbo", title: "Z-Image Turbo",
                lanes: [LaneDefinition(id: "int4", default: true,
                                       configuration: ZImageConfiguration.turbo(quant: .int4,
                                                                                modelsRootDirectory: modelsRoot))],
                operations: [zimageGenerate]),
        .custom(id: "probe", title: "Probe", manifest: probeManifest,
                lanes: [LaneDefinition(id: "fp32", default: true, configuration: NoWeights())],
                make: { ProbeModel() }),
    ],
    helpers: [
        PluginManifest.Helper(operation: "x-bench.zimage.generate", model: "z-image-turbo", title: "Z-Image generate"),
        PluginManifest.Helper(operation: "x-bench.gpu-touch", model: "probe", title: "One small matmul"),
        PluginManifest.Helper(operation: "x-bench.spool", model: "probe", title: "Spool echo"),
    ])

await GaeaPluginMain.run(bench)
