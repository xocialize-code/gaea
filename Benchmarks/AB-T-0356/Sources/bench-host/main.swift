import BenchShared
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import LightweightCodeRequirements

// bench-host: a minimal GPP host for AB-T-0356. MLX-free, like Gaea. It launches the signed bench
// bundle under Process.launchRequirement (team CFZS6RXUCP, Developer ID), drives it over GPP v1,
// times each phase on the system-wide clock and reads the worker's phys_footprint from outside with
// proc_pid_rusage. Every run prints one JSON line.
//
//   bench-host baseline --bundle <b.gaeaplugin>
//   bench-host zimage   --bundle <b> [--out <png>] [--seed 42] [--steps 8] [--size 1024]
//   bench-host spool    --bundle <b> --root <dir> --source <png> --case <name> [--runs 5]
//
// Spool cases: 4k-png, 4k-tiff16 (one 3840×2160 image), 1080p-<raw|png>-<count>[-par] (a batch of
// 1920×1080 frames; -par encodes and decodes on every core, on both sides).

let team = "CFZS6RXUCP"
var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}
func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("bench-host: \(message)\n".utf8))
    exit(1)
}
func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

guard let command = args.first else { die("usage: bench-host baseline|zimage|spool --bundle <b> …") }
args.removeFirst()
guard let bundlePath = option("--bundle") else { die("--bundle is required") }
let bundle = URL(fileURLWithPath: bundlePath).standardizedFileURL
let executable = bundle.appending(path: "Contents/MacOS/bench-worker")
let modelsRoot = NSHomeDirectory() + "/Library/Application Support/MLXEngine/Models"

// MARK: - The worker connection

struct Line {
    let at: Double
    let object: [String: Any]
    var type: String { object["type"] as? String ?? "" }
    var re: String? { object["re"] as? String }
}

final class Worker: @unchecked Sendable {
    let process = Process()
    private let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var lines: [Line] = []
    private let ready = DispatchSemaphore(value: 0)
    private var errBuffer = Data()
    private(set) var mainAt: Double?
    private(set) var exitedAt: Double?
    private var nextID = 0
    private(set) var launchAt: Double = 0
    private(set) var helloAt: Double = 0
    private(set) var hello: [String: Any] = [:]
    var pid: pid_t { process.processIdentifier }

    init(cacheRoot: URL) throws {
        process.executableURL = executable
        process.currentDirectoryURL = cacheRoot
        process.launchRequirement = try LaunchCodeRequirement.allOf {
            TeamIdentifier(team)
            ValidationCategory(.developerID)
        }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stdoutPipe.fileHandleForReading.readabilityHandler = { [unowned self] handle in
            let data = handle.availableData
            let at = Clock.now()
            if data.isEmpty { handle.readabilityHandler = nil; return }
            lock.lock()
            buffer.append(data)
            var count = 0
            while let nl = buffer.firstIndex(of: 0x0A) {
                let bytes = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                if let obj = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                    lines.append(Line(at: at, object: obj))
                    count += 1
                }
            }
            lock.unlock()
            for _ in 0..<count { ready.signal() }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [unowned self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            lock.lock()
            errBuffer.append(data)
            while let nl = errBuffer.firstIndex(of: 0x0A) {
                let text = String(decoding: errBuffer[errBuffer.startIndex..<nl], as: UTF8.self)
                errBuffer.removeSubrange(errBuffer.startIndex...nl)
                if text.hasPrefix("bench: main "), let t = Double(text.dropFirst(12)) { mainAt = t }
                else if ProcessInfo.processInfo.environment["BENCH_WORKER_LOG"] != nil {
                    FileHandle.standardError.write(Data("[worker] \(text)\n".utf8))
                }
            }
            lock.unlock()
        }
        process.terminationHandler = { [unowned self] _ in
            let at = Clock.now()
            lock.lock(); exitedAt = at; lock.unlock()
            ready.signal()
        }
        launchAt = Clock.now()
        try process.run()
        var hello: Line?
        let deadline = Date().addingTimeInterval(10)
        while hello == nil, Date() < deadline {
            hello = Worker.take(from: self, timeout: 10) { $0.type == "hello" }
            if exitedAt != nil { break }
        }
        guard let hello else { throw NSError(domain: "bench", code: 1, userInfo: [NSLocalizedDescriptionKey: "no hello"]) }
        self.helloAt = hello.at
        self.hello = hello.object
    }

    /// The first queued line matching `match`, waiting up to `timeout`. Other lines stay queued.
    private static func take(from w: Worker, timeout: TimeInterval, _ match: (Line) -> Bool) -> Line? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            w.lock.lock()
            if let i = w.lines.firstIndex(where: match) {
                let line = w.lines.remove(at: i)
                w.lock.unlock()
                return line
            }
            let exited = w.exitedAt != nil
            w.lock.unlock()
            if exited { return nil }
            let left = deadline.timeIntervalSinceNow
            if left <= 0 { return nil }
            _ = w.ready.wait(timeout: .now() + left)
        }
    }

    func take(timeout: TimeInterval, _ match: (Line) -> Bool) -> Line? { Worker.take(from: self, timeout: timeout, match) }

    /// Every queued line matching `match`, removed.
    func drain(_ match: (Line) -> Bool) -> [Line] {
        lock.lock(); defer { lock.unlock() }
        let out = lines.filter(match)
        lines.removeAll(where: match)
        return out
    }

    func send(_ object: [String: Any]) -> Double {
        var data = try! JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        let at = Clock.now()
        stdinPipe.fileHandleForWriting.write(data)
        return at
    }

    func newID() -> String { nextID += 1; return "h\(nextID)" }

    /// Send a request and wait for the reply of one of `replies` (or an error) carrying its id.
    func request(_ type: String, _ fields: [String: Any], replies: Set<String>,
                 timeout: TimeInterval = 600) -> (sent: Double, reply: Line) {
        let id = newID()
        var m = fields
        m["type"] = type
        m["id"] = id
        let sent = send(m)
        guard let reply = take(timeout: timeout, { $0.re == id && (replies.contains($0.type) || $0.type == "error") })
        else { die("no reply to \(type) \(id)") }
        if reply.type == "error" { die("\(type) failed: \(reply.object)") }
        return (sent, reply)
    }

    /// The unprompted memory line a worker sends after prepared, unloaded and result.
    func memoryReport(timeout: TimeInterval = 5) -> [String: Any]? {
        take(timeout: timeout) { $0.type == "memory" && $0.re == nil }?.object["report"] as? [String: Any]
    }

    func configure(ceiling: UInt64 = 64_000_000_000, cacheRoot: URL) -> (sent: Double, reply: Line) {
        request("configure", ["budget": ["ceilingBytes": ceiling, "wiresWeights": false],
                              "models_root": modelsRoot, "cache_root": cacheRoot.path, "settings": [String: Any]()],
                replies: ["configured"])
    }

    /// shutdown, then wait for the process to exit. Returns the seconds from send to exit.
    func shutdown() -> Double {
        let sent = send(["type": "shutdown", "id": newID()])
        process.waitUntilExit()
        let deadline = Date().addingTimeInterval(2)
        while exitedAt == nil, Date() < deadline { usleep(1000) }
        return secs(sent, exitedAt ?? Clock.now())
    }

    var phys: UInt64 { physFootprint(pid: pid) ?? 0 }
}

func scratchFolder(_ name: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "gaea-bench-\(name)-\(UUID().uuidString.prefix(8))")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - baseline

/// A worker's fixed cost: launch, hello, configure, MLX and Metal up with no model, shutdown.
func baseline() throws {
    let cache = scratchFolder("cache")
    defer { try? FileManager.default.removeItem(at: cache) }
    var r: [String: Any] = ["mode": "baseline"]
    usleep(300_000)
    r["sys_anon_before"] = systemAnonymousBytes() ?? 0
    let w = try Worker(cacheRoot: cache)
    r["launch_to_main_s"] = w.mainAt.map { secs(w.launchAt, $0) } ?? NSNull()
    r["main_to_hello_s"] = w.mainAt.map { secs($0, w.helloAt) } ?? NSNull()
    r["launch_to_hello_s"] = secs(w.launchAt, w.helloAt)
    r["phys_after_hello"] = w.phys
    usleep(200_000)
    r["phys_after_hello_settled"] = w.phys

    let c = w.configure(cacheRoot: cache)
    r["configure_s"] = secs(c.sent, c.reply.at)
    r["phys_after_configure"] = w.phys
    usleep(200_000)
    r["phys_after_configure_settled"] = w.phys

    let p = w.request("prepare", ["model": "probe", "lane": "fp32"], replies: ["prepared"])
    r["probe_prepare_s"] = secs(p.sent, p.reply.at)
    _ = w.memoryReport()
    let g = w.request("run", ["job": "gpu-1", "operation": "x-bench.gpu-touch", "model": "probe", "lane": "fp32",
                              "inputs": [String: Any](), "params": [String: Any](), "output_dir": cache.appending(path: "out").path],
                      replies: ["result"])
    r["gpu_touch_rtt_s"] = secs(g.sent, g.reply.at)
    if let outputs = g.reply.object["outputs"] as? [[String: Any]], let v = outputs.first?["value"] as? [String: Any] {
        r["gpu_touch_worker_s"] = v["seconds"]
        r["gpu_device"] = v["device"]
    }
    let report = w.memoryReport()
    r["phys_after_gpu"] = w.phys
    usleep(200_000)
    r["phys_after_gpu_settled"] = w.phys
    r["worker_report_phys_after_gpu"] = report?["physFootprintBytes"] ?? NSNull()
    r["worker_report_gpu_active"] = report?["gpuActiveBytes"] ?? NSNull()

    // A second touch: the warm cost of the same op (kernels compiled, pool warm).
    let g2 = w.request("run", ["job": "gpu-2", "operation": "x-bench.gpu-touch", "model": "probe", "lane": "fp32",
                               "inputs": [String: Any](), "params": [String: Any](), "output_dir": cache.appending(path: "out").path],
                       replies: ["result"])
    r["gpu_touch2_rtt_s"] = secs(g2.sent, g2.reply.at)
    _ = w.memoryReport()

    let u = w.request("unload", ["model": "probe"], replies: ["unloaded"])
    _ = w.memoryReport()
    r["unload_s"] = secs(u.sent, u.reply.at)
    usleep(200_000)
    r["phys_after_unload"] = w.phys
    let pid = w.pid
    r["shutdown_to_exit_s"] = w.shutdown()
    r["phys_after_exit"] = physFootprint(pid: pid) ?? 0  // nil: the pid is gone
    r["pid_gone_after_exit"] = physFootprint(pid: pid) == nil
    usleep(300_000)
    r["sys_anon_after"] = systemAnonymousBytes() ?? 0
    // Launch to a finished first GPU op, without the settle pauses this harness adds.
    r["cold_to_gpu_ready_s"] = (r["launch_to_hello_s"] as! Double) + (r["configure_s"] as! Double)
        + (r["probe_prepare_s"] as! Double) + (r["gpu_touch_rtt_s"] as! Double)
    emit(r)
}

// MARK: - zimage

/// Z-Image Turbo int4 through a worker: launch, hello, configure, prepare, a cold 1024² generate,
/// the output read back by the host, then a warm second generate, unload and shutdown.
func zimage() throws {
    let prompt = option("--prompt") ?? "A lighthouse on a rocky coast at dusk, photorealistic, 35mm film"
    let size = Int(option("--size") ?? "") ?? 1024
    let steps = Int(option("--steps") ?? "") ?? 8
    let seed = Int(option("--seed") ?? "") ?? 42
    let outPath = option("--out")
    let cache = scratchFolder("cache")
    let spool = scratchFolder("spool")
    defer {
        try? FileManager.default.removeItem(at: cache)
        try? FileManager.default.removeItem(at: spool)
    }
    var r: [String: Any] = ["mode": "worker"]
    let w = try Worker(cacheRoot: cache)
    let sampler = PeakSampler(pid: w.pid)
    defer { sampler.stop() }
    r["launch_to_main_s"] = w.mainAt.map { secs(w.launchAt, $0) } ?? NSNull()
    r["main_to_hello_s"] = w.mainAt.map { secs($0, w.helloAt) } ?? NSNull()
    r["launch_to_hello_s"] = secs(w.launchAt, w.helloAt)
    r["phys_after_hello"] = w.phys

    let c = w.configure(cacheRoot: cache)
    r["configure_s"] = secs(c.sent, c.reply.at)
    r["phys_after_configure"] = w.phys

    _ = sampler.takePeak()
    let p = w.request("prepare", ["model": "z-image-turbo", "lane": "int4"], replies: ["prepared"])
    r["prepare_s"] = secs(p.sent, p.reply.at)
    r["prepare_worker_s"] = p.reply.object["seconds"]
    let prepReport = w.memoryReport()
    r["phys_after_prepare"] = w.phys
    r["peak_phys_prepare"] = sampler.takePeak()
    r["report_after_prepare"] = prepReport ?? NSNull()

    func generate(_ label: String) {
        let out = spool.appending(path: label)
        let (sent, reply) = w.request("run", [
            "job": label, "operation": "x-bench.zimage.generate", "model": "z-image-turbo", "lane": "int4",
            "inputs": [String: Any](), "params": ["prompt": prompt, "width": size, "height": size, "steps": steps],
            "seed": seed, "output_dir": out.path,
        ], replies: ["result"], timeout: 900)
        let progress = w.drain { $0.type == "progress" && $0.object["job"] as? String == label }
        var firsts: [String: Double] = [:]
        for line in progress {
            let stage = line.object["stage"] as? String ?? "?"
            if firsts[stage] == nil { firsts[stage] = secs(sent, line.at) }
        }
        r["\(label)_s"] = secs(sent, reply.at)
        r["\(label)_worker_s"] = reply.object["seconds"]
        r["\(label)_phase_first"] = firsts
        r["\(label)_progress_lines"] = progress.count
        _ = w.memoryReport()
        r["phys_after_\(label)"] = w.phys
        r["peak_phys_\(label)"] = sampler.takePeak()
        // The host reads the output back: the file, then a full decode.
        if let outputs = reply.object["outputs"] as? [[String: Any]], let path = outputs.first?["path"] as? String {
            let t0 = Clock.now()
            let data = try! readFile(URL(fileURLWithPath: path))
            let t1 = Clock.now()
            let pixels = decode(data, as: .png, width: 0, height: 0)
            let t2 = Clock.now()
            r["\(label)_host_read_io_s"] = secs(t0, t1)
            r["\(label)_host_decode_s"] = secs(t1, t2)
            r["\(label)_output"] = ["bytes": data.count, "width": pixels.width, "height": pixels.height]
            if label == "run1", let outPath { try? data.write(to: URL(fileURLWithPath: outPath)) }
        }
    }
    generate("run1")
    generate("run2")

    let u = w.request("unload", ["model": "z-image-turbo"], replies: ["unloaded"])
    r["unload_s"] = secs(u.sent, u.reply.at)
    r["report_after_unload"] = w.memoryReport() ?? NSNull()
    usleep(500_000)
    r["phys_after_unload"] = w.phys
    r["shutdown_to_exit_s"] = w.shutdown()
    // What a cold job costs end to end: launch to the run's result, plus the host's read.
    let host1 = ((r["run1_host_read_io_s"] as? Double) ?? 0) + ((r["run1_host_decode_s"] as? Double) ?? 0)
    r["cold_total_s"] = (r["launch_to_hello_s"] as! Double) + (r["configure_s"] as! Double)
        + (r["prepare_s"] as! Double) + (r["run1_s"] as! Double)
    r["cold_total_with_host_read_s"] = (r["cold_total_s"] as! Double) + host1
    emit(r)
}

// MARK: - spool

struct SpoolCase {
    let name: String
    let format: SpoolFormat
    let width: Int, height: Int, count: Int
    let parallel: Bool

    init(_ name: String) {
        self.name = name
        switch name {
        case "4k-png": (format, width, height, count, parallel) = (.png, 3840, 2160, 1, false)
        case "4k-tiff16": (format, width, height, count, parallel) = (.tiff16, 3840, 2160, 1, false)
        default:
            // 1080p-<raw|png>-<count>[-par]
            let parts = name.split(separator: "-")
            guard parts.count >= 3, parts[0] == "1080p", let f = SpoolFormat(rawValue: String(parts[1])),
                  let n = Int(parts[2]) else { die("unknown case \(name)") }
            (format, width, height, count, parallel) = (f, 1920, 1080, n, parts.count > 3 && parts[3] == "par")
        }
    }
}

/// Host → worker → host through the job spool, each half timed separately.
func spoolBench() throws {
    guard let rootPath = option("--root"), let sourcePath = option("--source"), let caseName = option("--case")
    else { die("spool needs --root, --source and --case") }
    let runs = Int(option("--runs") ?? "") ?? 5
    let spec = SpoolCase(caseName)
    let root = URL(fileURLWithPath: rootPath, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    // Source pixels: the Z-Image output, scaled to cover the frame, panned a little per frame so no
    // two frames are equal. 60 distinct frames, cycled (content, not count, moves PNG's cost).
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { die("can't read \(sourcePath)") }
    let distinct = min(spec.count, 60)
    let frames: [Pixels] = (0..<distinct).map { i in
        Pixels(drawing: image, width: spec.width, height: spec.height, bitsPerComponent: spec.format.bitsPerComponent,
               offset: CGPoint(x: Double(i) * 3, y: Double(i) * 1.5))
    }

    let cache = scratchFolder("cache")
    defer { try? FileManager.default.removeItem(at: cache) }
    let w = try Worker(cacheRoot: cache)
    _ = w.configure(cacheRoot: cache)
    _ = w.request("prepare", ["model": "probe", "lane": "fp32"], replies: ["prepared"])
    _ = w.memoryReport()

    for run in 0..<(runs + 1) {  // run 0 warms the worker's code paths and is reported as warmup
        var r: [String: Any] = ["mode": "spool", "case": spec.name, "root": root.path, "run": run,
                                "warmup": run == 0, "count": spec.count, "format": spec.format.rawValue,
                                "width": spec.width, "height": spec.height, "parallel": spec.parallel]
        let job = root.appending(path: "job-\(UUID().uuidString.prefix(8))")
        let inDir = job.appending(path: "in"), outDir = job.appending(path: "out")
        try FileManager.default.createDirectory(at: inDir, withIntermediateDirectories: true)
        let inputs = (0..<spec.count).map { inDir.appending(path: String(format: "in_%04d.%@", $0, spec.format.fileExtension)) }

        // 1. Host write: encode, then the file.
        let lock = NSLock()
        var encoded = [Data](repeating: Data(), count: spec.count)
        let t0 = Clock.now()
        forEach(spec.count, parallel: spec.parallel) { i in
            let data = encode(frames[i % distinct], as: spec.format)
            lock.lock(); encoded[i] = data; lock.unlock()
        }
        let t1 = Clock.now()
        forEach(spec.count, parallel: spec.parallel) { i in
            lock.lock(); let data = encoded[i]; lock.unlock()
            try! writeFile(data, to: inputs[i])
        }
        let t2 = Clock.now()
        r["host_write_encode_s"] = secs(t0, t1)
        r["host_write_io_s"] = secs(t1, t2)
        r["bytes_in"] = encoded.reduce(0) { $0 + $1.count }
        encoded = []

        let params: [String: Any] = ["format": spec.format.rawValue, "width": spec.width, "height": spec.height,
                                     "parallel": spec.parallel]

        // 2. The message alone: the same inputs, a worker that touches nothing.
        var noop = params
        noop["work"] = "noop"
        let n = w.request("run", ["job": "noop-\(run)", "operation": "x-bench.spool", "model": "probe", "lane": "fp32",
                                  "inputs": ["frames": inputs.map(\.path)], "params": noop,
                                  "output_dir": job.appending(path: "noop").path], replies: ["result"])
        r["gpp_noop_rtt_s"] = secs(n.sent, n.reply.at)
        _ = w.memoryReport()

        // 3. The echo: worker read, then worker write; the rest of the round trip is GPP.
        let e = w.request("run", ["job": "echo-\(run)", "operation": "x-bench.spool", "model": "probe", "lane": "fp32",
                                  "inputs": ["frames": inputs.map(\.path)], "params": params,
                                  "output_dir": outDir.path], replies: ["result"], timeout: 1800)
        let rtt = secs(e.sent, e.reply.at)
        r["echo_rtt_s"] = rtt
        let outputs = e.reply.object["outputs"] as? [[String: Any]] ?? []
        let timing = outputs.first { $0["name"] as? String == "timing" }?["value"] as? [String: Any] ?? [:]
        for key in ["read_io_s", "read_decode_s", "write_encode_s", "write_io_s", "bytes_out"] {
            r["worker_\(key)"] = timing[key] ?? NSNull()
        }
        let workerWork = ["read_io_s", "read_decode_s", "write_encode_s", "write_io_s"]
            .reduce(0.0) { $0 + ((timing[$1] as? Double) ?? 0) }
        r["echo_gpp_overhead_s"] = rtt - workerWork
        r["result_line_bytes"] = (try? JSONSerialization.data(withJSONObject: e.reply.object).count) ?? 0
        _ = w.memoryReport()

        // 4. Host read: the file, then a full decode.
        let paths = outputs.compactMap { $0["path"] as? String }.map { URL(fileURLWithPath: $0) }
        var files = [Data](repeating: Data(), count: paths.count)
        let t3 = Clock.now()
        forEach(paths.count, parallel: spec.parallel) { i in
            let data = try! readFile(paths[i])
            lock.lock(); files[i] = data; lock.unlock()
        }
        let t4 = Clock.now()
        forEach(paths.count, parallel: spec.parallel) { i in
            lock.lock(); let data = files[i]; lock.unlock()
            _ = decode(data, as: spec.format, width: spec.width, height: spec.height)
        }
        let t5 = Clock.now()
        r["host_read_io_s"] = secs(t3, t4)
        r["host_read_decode_s"] = secs(t4, t5)
        files = []

        // 5. Cleanup, as the host does when a job's TTL ends.
        let t6 = Clock.now()
        try? FileManager.default.removeItem(at: job)
        r["cleanup_s"] = secs(t6)

        r["file_path_total_s"] = (r["host_write_io_s"] as! Double) + (timing["read_io_s"] as? Double ?? 0)
            + (timing["write_io_s"] as? Double ?? 0) + (r["host_read_io_s"] as! Double)
            + (r["echo_gpp_overhead_s"] as! Double)
        r["codec_total_s"] = (r["host_write_encode_s"] as! Double) + (timing["read_decode_s"] as? Double ?? 0)
            + (timing["write_encode_s"] as? Double ?? 0) + (r["host_read_decode_s"] as! Double)
        emit(r)
    }
    _ = w.shutdown()
}

switch command {
case "baseline": try baseline()
case "zimage": try zimage()
case "spool": try spoolBench()
default: die("unknown command \(command)")
}
exit(0)
