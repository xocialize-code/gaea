import BenchShared
import Foundation
import MLX
import MLXServeCore
import MLXToolKit
import MLXZImage

// The in-process baseline for AB-T-0356: Z-Image Turbo int4 loaded by MLXServeEngine in this
// process, with the same budget, request, steps and seed the bench worker gets over GPP. One cold
// generate and one warm generate per process; prints one JSON line.
//
//   bench-inproc [--prompt <text>] [--size 1024] [--steps 8] [--seed 42] [--ceiling <bytes>] [--out <png>]

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}
let mainAt = Clock.now()
let prompt = option("--prompt") ?? "A lighthouse on a rocky coast at dusk, photorealistic, 35mm film"
let size = Int(option("--size") ?? "") ?? 1024
let steps = Int(option("--steps") ?? "") ?? 8
let seed = UInt64(option("--seed") ?? "") ?? 42
let ceiling = UInt64(option("--ceiling") ?? "") ?? 64_000_000_000
let outPath = option("--out")

let pid = getpid()
let sampler = PeakSampler(pid: pid)
var result: [String: Any] = ["mode": "inproc", "pid": Int(pid), "main_at": mainAt]
func phys() -> UInt64 { physFootprint(pid: pid) ?? 0 }
result["phys_at_main"] = phys()

let modelsRoot = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/MLXEngine/Models",
                     isDirectory: true)

// The same budget Gaea sends a worker (wiresWeights off, the automatic pool cap).
var t = Clock.now()
let engine = MLXServeEngine(workerBudget: WorkerBudget(ceilingBytes: ceiling, wiresWeights: false))
await engine.useModelStore(ModelStore(root: modelsRoot))
result["engine_init_s"] = secs(t)
result["phys_after_engine"] = phys()

t = Clock.now()
let id = PackageID("z-image-turbo")
_ = try await engine.register(ZImageTurboT2IPackage.registration,
                              configuration: ZImageConfiguration.turbo(quant: .int4, modelsRootDirectory: modelsRoot),
                              id: id)
result["register_s"] = secs(t)

_ = sampler.takePeak()
t = Clock.now()
_ = try await engine.prepare(.textToImage, package: id)
result["prepare_s"] = secs(t)
result["phys_after_prepare"] = phys()
result["peak_phys_prepare"] = sampler.takePeak()

/// One generate, with the time each RunProgress phase first appeared.
func generate(_ label: String) async throws {
    final class Firsts: @unchecked Sendable { var at: [String: Double] = [:]; let lock = NSLock() }
    let firsts = Firsts()
    let request = T2IRequest(prompt: prompt, width: size, height: size, steps: steps, seed: seed)
    let start = Clock.now()
    let response = try await RunProgress.$sink.withValue({ report in
        firsts.lock.lock()
        if firsts.at[report.phase.rawValue] == nil { firsts.at[report.phase.rawValue] = Clock.now() }
        firsts.lock.unlock()
    }) {
        try await engine.run(request, package: id)
    }
    let end = Clock.now()
    result["\(label)_s"] = secs(start, end)
    result["\(label)_phase_first"] = firsts.at.mapValues { secs(start, $0) }
    result["phys_after_\(label)"] = phys()
    result["peak_phys_\(label)"] = sampler.takePeak()
    if let image = (response as? T2IResponse)?.image {
        result["\(label)_image"] = ["format": image.format.rawValue, "bytes": image.data.count,
                                    "width": image.width ?? 0, "height": image.height ?? 0]
        if label == "run1", let outPath { try image.data.write(to: URL(fileURLWithPath: outPath)) }
    }
}
try await generate("run1")
try await generate("run2")

t = Clock.now()
await engine.evict(package: id)
Memory.clearCache()
result["evict_s"] = secs(t)
try? await Task.sleep(for: .milliseconds(500))
result["phys_after_evict"] = phys()
result["cold_total_s"] = secs(mainAt, mainAt + (result["engine_init_s"] as! Double) + (result["register_s"] as! Double)
                               + (result["prepare_s"] as! Double) + (result["run1_s"] as! Double))
sampler.stop()

let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
