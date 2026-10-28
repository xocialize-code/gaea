import CryptoKit
import Darwin
import Foundation
import GaeaProtocol
import Synchronization

/// A GPP error as the host sees it: a worker's `error` line, or the worker going away.
public struct WorkerFailure: Error, Sendable, CustomStringConvertible {
    public var code: String
    public var message: String
    public var retryable: Bool
    /// The worker exited or was killed while the request was open (SRV-8 requeues a run once).
    public var workerExited: Bool

    public init(code: String, message: String, retryable: Bool = false, workerExited: Bool = false) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.workerExited = workerExited
    }

    public var description: String { "\(code): \(message)" }
}

/// One plugin worker process, driven over GPP v1 (spec/GPP-1.md) from the host side.
///
/// Launch: the bundle was verified just before (PLG-3), the executable runs with `Process.launchRequirement` pinned
/// to the trusted team, and the first line must be a `hello` that matches the verified manifest. A worker that exits
/// before its hello (a refused launch requirement is a SIGKILL) fails the launch at once through `terminationHandler`,
/// not after the 10 s wait (GPP-1 §2).
///
/// Every line both ways is recorded to a transcript (`H `/`W ` prefixed, `# manifest:` header) that
/// `tools/validate.py --transcript` checks.
public final class WorkerProcess: @unchecked Sendable {
    public let pluginID: String
    public let version: String
    public let manifest: PluginManifest
    public let bundle: URL
    let manifestDigest: String
    let process = Process()
    private let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
    private let state = Mutex(State())
    private let writeLock = Mutex(())
    private let transcript: FileHandle?
    public let transcriptURL: URL?
    private let log: URL

    /// Answers the worker's `storage.*` requests (G-5): returns the `storage.result` fields, or throws a `WorkerFailure`.
    public var storage: (@Sendable (_ type: String, _ message: [String: JSONValue]) async throws -> [String: JSONValue])?
    /// Every unprompted `memory` report, and the answers to `memory.query`.
    public var onMemory: (@Sendable (WorkerMemoryReportWire) -> Void)?
    /// The process ended, for whatever reason.
    public var onExit: (@Sendable (_ status: Int32, _ reason: Process.TerminationReason) -> Void)?

    struct Pending {
        var finals: Set<String>
        var continuation: CheckedContinuation<[String: JSONValue], Error>
        var onLine: (@Sendable ([String: JSONValue]) -> Void)?
    }

    struct State {
        var buffer = Data()
        var pending: [String: Pending] = [:]
        var helloWaiter: CheckedContinuation<[String: JSONValue], Error>?
        var hello: [String: JSONValue]?
        var exited = false
        var exitWaiters: [CheckedContinuation<Void, Never>] = []
        var nextID = 1
        var shutdownSent = false
        var memoryReports = 0
        var memoryWaiters: [CheckedContinuation<Void, Never>] = []
    }

    public init(pluginID: String, version: String, bundle: URL, manifest: PluginManifest, manifestData: Data,
                cacheRoot: URL, log: URL, sessions: URL?) {
        self.pluginID = pluginID
        self.version = version
        self.bundle = bundle
        self.manifest = manifest
        self.log = log
        manifestDigest = SHA256.hash(data: manifestData).map { String(format: "%02x", $0) }.joined()
        process.executableURL = bundle.appending(path: "Contents/MacOS/\(manifest.executable)")
        process.currentDirectoryURL = cacheRoot
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        if let sessions {
            let stamp = Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "")
            let url = sessions.appending(path: "\(pluginID)-\(version)-\(stamp).gpp")
            FileManager.default.createFile(atPath: url.path, contents: Data(
                "# manifest: \(bundle.appending(path: "Contents/Resources/manifest.json").path)\n# Gaea \(Gaea.version) session with \(pluginID) \(version)\n".utf8))
            transcript = try? FileHandle(forWritingTo: url)
            transcript?.seekToEndOfFile()
            transcriptURL = url
        } else {
            transcript = nil
            transcriptURL = nil
        }
    }

    deinit { try? transcript?.close() }

    public var pid: pid_t { process.processIdentifier }
    public var isRunning: Bool { !state.withLock { $0.exited } }

    /// `ri_phys_footprint`, read from outside (MEM-4).
    public var physFootprint: UInt64? {
        guard isRunning else { return nil }
        var info = rusage_info_v4()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return r == 0 ? info.ri_phys_footprint : nil
    }

    // MARK: - Launch

    /// Starts the worker and waits for a hello that matches the manifest. Returns how long hello took.
    public func start(helloTimeout: Duration = .seconds(10)) async throws -> Duration {
        process.launchRequirement = try PluginVerifier.launchRequirement()
        HostLog.append("\n=== \(Date().formatted(.iso8601)) launch \(pluginID) \(version) ===\n", to: log)
        let logURL = log
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { self?.ingest(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { HostLog.append(String(decoding: data, as: UTF8.self), to: logURL) }
        }
        process.terminationHandler = { [weak self] process in
            self?.exited(status: process.terminationStatus, reason: process.terminationReason)
        }
        let clock = ContinuousClock()
        let began = clock.now
        try process.run()

        let hello: [String: JSONValue] = try await withThrowingTaskGroup(of: [String: JSONValue].self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    let ready = self.state.withLock { state -> Result<[String: JSONValue], Error>? in
                        if let hello = state.hello { return .success(hello) }
                        if state.exited { return .failure(self.exitFailure()) }
                        state.helloWaiter = continuation
                        return nil
                    }
                    if let ready { continuation.resume(with: ready) }
                }
            }
            group.addTask {
                try await Task.sleep(for: helloTimeout)
                throw WorkerFailure(code: "internal", message: "no hello within \(helloTimeout) (held at launch?)")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        let elapsed = clock.now - began
        do {
            try check(hello)
        } catch {
            kill(SIGKILL)
            throw error
        }
        return elapsed
    }

    private func exitFailure() -> WorkerFailure {
        let reason = process.terminationReason == .uncaughtSignal ? "signal \(process.terminationStatus)" : "status \(process.terminationStatus)"
        let hint = process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL
            ? " (a refused launch requirement is a SIGKILL)" : ""
        return WorkerFailure(code: "internal", message: "the worker exited before its hello: \(reason)\(hint)", workerExited: true)
    }

    /// GPP-1 §2 step 2: `plugin`, `models` and `engine` match the verified manifest, and `manifest_sha256` is its digest.
    func check(_ hello: [String: JSONValue]) throws {
        func fail(_ what: String) -> WorkerFailure {
            WorkerFailure(code: "protocol", message: "hello \(what) differs from the verified manifest")
        }
        guard hello["protocol"]?.intValue.map(Gaea.protocols.contains) == true else { throw fail("protocol") }
        guard hello["plugin"] == ["id": .string(manifest.id), "version": .string(manifest.version)] else { throw fail("plugin") }
        guard hello["models"] == .array(manifest.models.map { .string($0.id) }) else { throw fail("models") }
        guard hello["manifest_sha256"]?.stringValue == manifestDigest else { throw fail("manifest_sha256") }
        if let engine = manifest.engine {
            guard hello["engine"] == ["version": .string(engine.version), "contract": .string(engine.contract)] else { throw fail("engine") }
        }
    }

    // MARK: - Requests

    func nextID() -> String { state.withLock { s in defer { s.nextID += 1 }; return "h\(s.nextID)" } }

    /// Sends a request and waits for its final reply (one of `finals`, or `error`). Other lines carrying its id go
    /// to `onLine` (progress, chunks, materialize progress).
    @discardableResult
    public func request(_ type: String, _ fields: [String: JSONValue], finals: Set<String>,
                        onLine: (@Sendable ([String: JSONValue]) -> Void)? = nil) async throws -> [String: JSONValue] {
        let id = nextID()
        var message = fields
        message["type"] = .string(type)
        message["id"] = .string(id)
        return try await withCheckedThrowingContinuation { continuation in
            let refused = state.withLock { s -> Bool in
                if s.exited || s.shutdownSent { return true }
                s.pending[id] = Pending(finals: finals, continuation: continuation, onLine: onLine)
                return false
            }
            if refused {
                continuation.resume(throwing: WorkerFailure(code: "internal", message: "the worker isn't running", workerExited: true))
                return
            }
            send(message)
        }
    }

    public func configure(budget: WorkerBudgetWire, modelsRoot: URL, cacheRoot: URL, settings: [String: JSONValue]) async throws {
        try await request("configure", ["budget": try JSONValue(encoding: budget), "models_root": .string(modelsRoot.path),
                                        "cache_root": .string(cacheRoot.path), "settings": .object(settings)], finals: ["configured"])
    }

    public func prepare(model: String, lane: String, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await request("prepare", ["model": .string(model), "lane": .string(lane)], finals: ["prepared"]) { line in
            if line["type"]?.stringValue == "materialize.progress", let f = line["fraction"]?.doubleValue { progress?(f) }
        }
    }

    public func materialize(model: String, lane: String, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await request("materialize", ["model": .string(model), "lane": .string(lane)], finals: ["materialize.done"]) { line in
            if let f = line["fraction"]?.doubleValue { progress?(f) }
        }
    }

    /// `unload`, then the `memory` report the worker sends after `unloaded` (GPP-1 §3.2), so nothing the host sends
    /// next (a `shutdown`, say) lands between the two.
    public func unload(model: String) async throws {
        let before = state.withLock { $0.memoryReports }
        try await request("unload", ["model": .string(model)], finals: ["unloaded"])
        await awaitMemoryReport(after: before, timeout: .seconds(1))
    }

    func awaitMemoryReport(after count: Int, timeout: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    let ready = self.state.withLock { s -> Bool in
                        if s.memoryReports > count || s.exited { return true }
                        s.memoryWaiters.append(c)
                        return false
                    }
                    if ready { c.resume() }
                }
            }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
            // A waiter the timeout beat is resumed here so it never leaks.
            let stale = self.state.withLock { s in defer { s.memoryWaiters = [] }; return s.memoryWaiters }
            for waiter in stale { waiter.resume() }
        }
    }

    private func countMemoryReport() {
        let waiters = state.withLock { s in
            s.memoryReports += 1
            defer { s.memoryWaiters = [] }
            return s.memoryWaiters
        }
        for waiter in waiters { waiter.resume() }
    }

    public func memoryQuery() async throws -> WorkerMemoryReportWire? {
        let reply = try await request("memory.query", [:], finals: ["memory"])
        return reply["report"].flatMap { try? $0.decode(WorkerMemoryReportWire.self) }
    }

    /// Sends `cancel` for a job. Nothing answers it; the run ends with `cancelled` or its result.
    public func cancel(job: String) {
        send(["type": "cancel", "id": .string(nextID()), "job": .string(job)])
    }

    /// `shutdown`: the worker ends any run with `cancelled`, flushes and exits 0. Nothing answers.
    public func shutdown() {
        let first = state.withLock { s -> Bool in
            defer { s.shutdownSent = true }
            return !s.shutdownSent && !s.exited
        }
        if first { send(["type": "shutdown", "id": .string(nextID())]) }
    }

    public func kill(_ signal: Int32) {
        if isRunning { Darwin.kill(pid, signal) }
    }

    /// Waits up to `timeout` for the process to end. True when it has.
    public func waitForExit(_ timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    let done = self.state.withLock { s -> Bool in
                        if s.exited { return true }
                        s.exitWaiters.append(c)
                        return false
                    }
                    if done { c.resume() }
                }
                return true
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first || !isRunning
        }
    }

    /// The rungs of GPP-1 §5.
    public enum Rung: String, Sendable { case unload, shutdown, sigterm, sigkill }

    public struct Waits: Sendable {
        public var unload: Duration = .seconds(10)
        public var shutdown: Duration = .seconds(5)
        public var sigterm: Duration = .seconds(5)
        public init() {}
    }

    /// Climbs the escalation ladder until the worker is gone (GPP-1 §5): `unload` each model (10 s for `unloaded`),
    /// then `shutdown` (5 s for exit), then SIGTERM (5 s), then SIGKILL. Returns the rung that ended it.
    @discardableResult
    public func stop(unloading models: [String], waits: Waits = Waits()) async -> Rung {
        if !models.isEmpty, isRunning {
            let unloaded = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    for model in models { _ = try? await self.unload(model: model) }
                    return true
                }
                group.addTask {
                    try? await Task.sleep(for: waits.unload)
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
            if !unloaded { HostLog.append("unload timed out after \(waits.unload); shutting down\n", to: log) }
        }
        guard isRunning else { return .unload }
        shutdown()
        if await waitForExit(waits.shutdown) { return .shutdown }
        HostLog.append("no exit \(waits.shutdown) after shutdown; SIGTERM\n", to: log)
        kill(SIGTERM)
        if await waitForExit(waits.sigterm) { return .sigterm }
        HostLog.append("no exit \(waits.sigterm) after SIGTERM; SIGKILL\n", to: log)
        kill(SIGKILL)
        _ = await waitForExit(.seconds(5))
        return .sigkill
    }

    // MARK: - Lines

    func send(_ message: [String: JSONValue]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(message) else { return }
        writeLock.withLock { _ in
            record("H ", data)
            try? stdin.fileHandleForWriting.write(contentsOf: data + Data([0x0A]))
        }
    }

    private func record(_ prefix: String, _ line: Data) {
        guard let transcript else { return }
        try? transcript.write(contentsOf: Data(prefix.utf8) + line + Data([0x0A]))
    }

    private func ingest(_ data: Data) {
        let lines = state.withLock { s -> [Data] in
            s.buffer.append(data)
            var lines: [Data] = []
            while let nl = s.buffer.firstIndex(of: 0x0A) {
                lines.append(Data(s.buffer[s.buffer.startIndex..<nl]))
                s.buffer.removeSubrange(s.buffer.startIndex...nl)
            }
            return lines
        }
        if state.withLock({ $0.buffer.count }) > GPP.maxLineBytes {
            HostLog.append("protocol: a line longer than \(GPP.maxLineBytes) bytes; killing the worker\n", to: log)
            kill(SIGKILL)
            return
        }
        for line in lines {
            writeLock.withLock { _ in record("W ", line) }
            guard let message = try? JSONDecoder().decode(JSONValue.self, from: line).objectValue,
                  let type = message["type"]?.stringValue else {
                HostLog.append("protocol: not a JSON object: \(String(decoding: line.prefix(200), as: UTF8.self))\n", to: log)
                send(["type": "error", "code": "protocol", "message": "a line that isn't a GPP message", "retryable": false])
                continue
            }
            handle(type, message)
        }
    }

    private func handle(_ type: String, _ message: [String: JSONValue]) {
        switch type {
        case "hello":
            let waiter = state.withLock { s -> CheckedContinuation<[String: JSONValue], Error>? in
                s.hello = message
                defer { s.helloWaiter = nil }
                return s.helloWaiter
            }
            waiter?.resume(returning: message)
        case "memory" where message["re"] == nil:
            if let report = message["report"].flatMap({ try? $0.decode(WorkerMemoryReportWire.self) }) { onMemory?(report) }
            countMemoryReport()
        case let t where t.hasPrefix("storage."):
            answerStorage(type, message)
        default:
            guard let re = message["re"]?.stringValue else {
                HostLog.append("worker error without re: \(message["message"]?.stringValue ?? type)\n", to: log)
                return
            }
            if type == "memory", let report = message["report"].flatMap({ try? $0.decode(WorkerMemoryReportWire.self) }) {
                onMemory?(report)
            }
            let (pending, isFinal) = state.withLock { s -> (Pending?, Bool) in
                guard let p = s.pending[re] else { return (nil, false) }
                let final = type == "error" || p.finals.contains(type)
                if final { s.pending[re] = nil }
                return (p, final)
            }
            guard let pending else { return }
            if !isFinal {
                pending.onLine?(message)
            } else if type == "error" {
                pending.continuation.resume(throwing: WorkerFailure(
                    code: message["code"]?.stringValue ?? "internal", message: message["message"]?.stringValue ?? "",
                    retryable: message["retryable"]?.boolValue ?? false))
            } else {
                pending.continuation.resume(returning: message)
            }
        }
    }

    private func answerStorage(_ type: String, _ message: [String: JSONValue]) {
        guard let id = message["id"]?.stringValue else { return }
        let storage = self.storage
        Task {
            do {
                guard let storage else { throw WorkerFailure(code: "storage_failed", message: "no store") }
                var reply = try await storage(type, message)
                reply["type"] = "storage.result"
                reply["re"] = .string(id)
                send(reply)
            } catch {
                let failure = error as? WorkerFailure
                send(["type": "error", "re": .string(id), "code": "storage_failed",
                      "message": .string(failure?.message ?? "\(error)"), "retryable": false])
            }
        }
    }

    private func exited(status: Int32, reason: Process.TerminationReason) {
        let (pending, helloWaiter, exitWaiters) = state.withLock { s in
            s.exited = true
            defer { s.pending = [:]; s.helloWaiter = nil; s.exitWaiters = []; s.memoryWaiters = [] }
            return (Array(s.pending.values), s.helloWaiter, s.exitWaiters + s.memoryWaiters)
        }
        let how = reason == .uncaughtSignal ? "signal \(status)" : "status \(status)"
        HostLog.append("=== \(Date().formatted(.iso8601)) exited (\(how)) ===\n", to: log)
        helloWaiter?.resume(throwing: exitFailure())
        for p in pending {
            p.continuation.resume(throwing: WorkerFailure(code: "internal", message: "the worker exited (\(how))", workerExited: true))
        }
        for w in exitWaiters { w.resume() }
        onExit?(status, reason)
    }
}

/// `configure.budget`: MLXToolKit's `WorkerBudget` on the wire.
public struct WorkerBudgetWire: Codable, Sendable, Equatable {
    public var ceilingBytes: UInt64
    public var cacheLimitBytes: UInt64?
    public var wiresWeights: Bool

    public init(ceilingBytes: UInt64, cacheLimitBytes: UInt64? = nil, wiresWeights: Bool = false) {
        self.ceilingBytes = ceilingBytes
        self.cacheLimitBytes = cacheLimitBytes
        self.wiresWeights = wiresWeights
    }
}

/// `memory.report`: MLXToolKit's `WorkerMemoryReport` as the worker sends it. Decoded leniently (the date's
/// encoding is the worker's), since the host reads only the byte counts.
public struct WorkerMemoryReportWire: Codable, Sendable, Equatable {
    public var budgetBytes: UInt64
    public var residentBytes: UInt64
    public var transientReserveBytes: UInt64
    public var availableBytes: UInt64
    public var physFootprintBytes: UInt64?
    public var gpuActiveBytes: UInt64?
    public var gpuCacheBytes: UInt64?
    public var residents: [String: UInt64]
    public var running: [String]

    /// What the worker's own governor has charged: the persistent weights plus its transient reserve.
    public var declaredBytes: UInt64 { residentBytes + transientReserveBytes }
}
