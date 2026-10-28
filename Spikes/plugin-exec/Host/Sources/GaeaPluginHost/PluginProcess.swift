import Darwin
import Foundation

/// One running worker. Gaea would hold at most one heavy worker at a time and keep it warm.
final class PluginProcess {
    let process = Process()
    private let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
    private var buffer = Data()
    private let lock = NSLock()
    private var waiters: [String: CheckedContinuation<[String: Any], Never>] = [:]
    private var helloWaiter: CheckedContinuation<[String: Any], Never>?
    private(set) var hello: [String: Any]?
    var onEvent: (([String: Any]) -> Void)?
    var stderrText = ""

    init(executable: URL) {
        process.executableURL = executable
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
    }

    var pid: pid_t { process.processIdentifier }

    /// Launch and wait for the worker's hello line, with a deadline: a launch Gatekeeper is
    /// holding never says hello.
    func start(timeout: TimeInterval = 10) async throws -> (hello: [String: Any], seconds: Double) {
        let began = Date()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] h in self?.ingest(h.availableData) }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] h in
            if let s = String(data: h.availableData, encoding: .utf8) { self?.stderrText += s }
        }
        try process.run()
        let hello = await withCheckedContinuation { (c: CheckedContinuation<[String: Any], Never>) in
            lock.lock(); helloWaiter = c; let ready = self.hello; lock.unlock()
            if let ready { lock.lock(); helloWaiter = nil; lock.unlock(); c.resume(returning: ready) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                self.lock.lock(); let w = self.helloWaiter; self.helloWaiter = nil; self.lock.unlock()
                w?.resume(returning: ["type": "timeout"])
            }
        }
        if hello["type"] as? String == "timeout" {
            process.terminate()
            throw NSError(domain: "Gaea", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "no hello within \(Int(timeout)) s (blocked at launch — Gatekeeper?)"])
        }
        return (hello, Date().timeIntervalSince(began))
    }

    func send(_ object: [String: Any]) {
        var data = try! JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        stdin.fileHandleForWriting.write(data)
    }

    /// Send a job and await its result or error line.
    func run(id: String, op: String, params: [String: Any]) async -> [String: Any] {
        await withCheckedContinuation { c in
            lock.lock(); waiters[id] = c; lock.unlock()
            send(["id": id, "op": op, "params": params])
        }
    }

    func cancel(_ id: String) { send(["op": "cancel", "target": id]) }

    func shutdown() {
        send(["op": "shutdown"])
        process.waitUntilExit()
    }

    /// The worker's physical footprint, as Activity Monitor's "Memory" column reports it.
    var footprintBytes: UInt64 {
        var info = rusage_info_v4()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return r == 0 ? info.ri_phys_footprint : 0
    }

    private func ingest(_ data: Data) {
        lock.lock(); buffer.append(data)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer[buffer.startIndex..<nl]); buffer.removeSubrange(buffer.startIndex...nl)
        }
        lock.unlock()
        for line in lines {
            guard let msg = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            onEvent?(msg)
            switch msg["type"] as? String {
            case "hello":
                lock.lock(); hello = msg; let w = helloWaiter; helloWaiter = nil; lock.unlock()
                w?.resume(returning: msg)
            case "result", "error":
                let id = msg["id"] as? String ?? ""
                lock.lock(); let w = waiters.removeValue(forKey: id); lock.unlock()
                w?.resume(returning: msg)
            default: break
            }
        }
    }
}
