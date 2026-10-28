import Darwin
import Foundation
import GaeaProtocol
import MLXToolKit

/// One GPU job at a time across Gaea (G-13): a FIFO lock every job holds while it runs.
actor GPULane {
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var queued: Int { waiters.count }

    func acquire() async {
        if !held {
            held = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { held = false } else { waiters.removeFirst().resume() }
    }
}

/// How Gaea picks a lane by memory (MEM-7, G-23).
public enum LaneChoice {
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case unknownLane(String, model: String)
        /// The request named this lane and it doesn't fit: never fall back.
        case namedDoesNotFit(String, need: UInt64, available: UInt64)
        case nothingFits(need: UInt64, available: UInt64)

        public var description: String {
            switch self {
            case let .unknownLane(lane, model): "\(model) has no lane \(lane)."
            case let .namedDoesNotFit(lane, need, available):
                "Lane \(lane) needs \(need.gb) and \(available.gb) is free; a request that names a lane never falls back."
            case let .nothingFits(need, available): "No lane fits: the smallest needs \(need.gb) and \(available.gb) is free."
            }
        }
    }

    /// Persistent weights plus the peak transient: what a lane needs while it runs.
    public static func need(_ lane: PluginManifest.Lane) -> UInt64 { lane.resolved.persistentBytes &+ lane.resolved.peakTransientBytes }

    /// The operator's default lane when it fits, else the largest smaller lane that fits (reported as `fellBackFrom`).
    /// A named lane is that lane or a refusal.
    public static func choose(_ model: PluginManifest.Model, named: String?, preferred: String?, available: UInt64) throws(Refusal)
        -> (lane: PluginManifest.Lane, fellBackFrom: PluginManifest.Lane?)
    {
        if let named {
            guard let lane = model.lanes.first(where: { $0.id == named }) else { throw .unknownLane(named, model: model.id) }
            guard need(lane) <= available else { throw .namedDoesNotFit(named, need: need(lane), available: available) }
            return (lane, nil)
        }
        let chosen = preferred.flatMap { p in model.lanes.first { $0.id == p } } ?? model.lanes.first(where: \.default) ?? model.lanes[0]
        if need(chosen) <= available { return (chosen, nil) }
        let smaller = model.lanes.filter { need($0) < need(chosen) && need($0) <= available }.max { need($0) < need($1) }
        guard let smaller else {
            throw .nothingFits(need: model.lanes.map(need).min() ?? need(chosen), available: available)
        }
        return (smaller, chosen)
    }
}

extension UInt64 {
    var gb: String { String(format: "%.2f GB", Double(self) / 1e9) }
}

/// A run handed to a plugin worker.
public struct WorkerJob: Sendable {
    public var job: String
    public var pluginID: String
    public var model: String
    public var operation: String
    /// `x-gaea.lane` from the request: that lane or a refusal.
    public var namedLane: String?
    public var params: [String: JSONValue]
    public var inputs: [String: JSONValue]
    public var modelParams: [String: JSONValue]?
    public var seed: Int?
    public var outputDir: URL

    public init(job: String, pluginID: String, model: String, operation: String, namedLane: String? = nil,
                params: [String: JSONValue] = [:], inputs: [String: JSONValue] = [:], modelParams: [String: JSONValue]? = nil,
                seed: Int? = nil, outputDir: URL) {
        self.job = job
        self.pluginID = pluginID
        self.model = model
        self.operation = operation
        self.namedLane = namedLane
        self.params = params
        self.inputs = inputs
        self.modelParams = modelParams
        self.seed = seed
        self.outputDir = outputDir
    }
}

public struct WorkerJobResult: Sendable {
    /// The worker's `result` line.
    public var result: [String: JSONValue]
    public var lane: String
    /// The lane the operator's default asked for, when a smaller one ran instead (`lane_fallback`).
    public var fellBackFrom: String?
    public var fallbackMessage: String?
    public var requeued: Bool
}

/// Everything memory-shaped Gaea knows, across its processes (MEM-4).
public struct Ledger: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public var pluginID: String
        public var title: String
        public var version: String
        public var pid: Int32
        /// Prepared lanes, by model.
        public var lanes: [String: String]
        /// From the manifest: the prepared lanes' persistent bytes plus the largest peak transient.
        public var declaredBytes: UInt64
        /// `proc_pid_rusage` `ri_phys_footprint`, read by the host.
        public var physFootprintBytes: UInt64?
        /// What the worker's own last memory report said.
        public var reportedFootprintBytes: UInt64?
        public var reportedDeclaredBytes: UInt64?
        /// What the scheduler charges: the larger of declared and measured.
        public var chargedBytes: UInt64
        public var busy: Bool
        public var overrun: Bool
    }

    public var budgetBytes: UInt64
    public var hostFootprintBytes: UInt64
    public var workers: [Entry]
    public var chargedBytes: UInt64 { workers.reduce(0) { $0 + $1.chargedBytes } }
    public var availableBytes: UInt64 { budgetBytes > chargedBytes ? budgetBytes - chargedBytes : 0 }
    public var queued: Int
}

/// The queue and the governor (Plan §2.1): one GPU job at a time, workers launched on demand and kept warm, a ledger
/// across processes, lane choice by memory, eviction through GPP's escalation ladder, and a run requeued once when its
/// worker dies (SRV-8).
public actor Scheduler: WorkerControl {
    let manager: PluginManager
    let database: GaeaDatabase
    let paths: GaeaPaths
    let log: HostLog
    public let budgetBytes: UInt64
    let gpu = GPULane()
    var waits = WorkerProcess.Waits()
    /// Workers idle this long are shut down.
    var idleTimeout: Duration

    struct Slot {
        var worker: WorkerProcess
        var plugin: InstalledPlugin
        var prepared: [String: PluginManifest.Lane] = [:]
        var lastUsed = Date()
        var report: WorkerMemoryReportWire?
        var overrun = false

        var declaredBytes: UInt64 {
            prepared.values.reduce(0) { $0 + $1.resolved.persistentBytes } + (prepared.values.map(\.resolved.peakTransientBytes).max() ?? 0)
        }
    }

    var slots: [String: Slot] = [:]
    var busy: Set<String> = []
    /// Called whenever a worker starts or stops (the System page's process list).
    var onWorkersChanged: (@Sendable () -> Void)?

    public init(manager: PluginManager, database: GaeaDatabase, paths: GaeaPaths, log: HostLog,
                budgetBytes: UInt64? = nil, idleTimeout: Duration = .seconds(900)) {
        self.manager = manager
        self.database = database
        self.paths = paths
        self.log = log
        self.idleTimeout = idleTimeout
        // Three quarters of unified memory, unless the operator set a budget.
        let configured = (try? database.setting("memory.budget_bytes")).flatMap { $0 }.flatMap(UInt64.init)
        self.budgetBytes = budgetBytes ?? configured ?? ProcessInfo.processInfo.physicalMemory / 4 * 3
    }

    public func setWaits(_ waits: WorkerProcess.Waits) { self.waits = waits }
    public func observeWorkers(_ handler: @escaping @Sendable () -> Void) { onWorkersChanged = handler }

    // MARK: - WorkerControl

    public func isIdle(plugin id: String) -> Bool { !busy.contains(id) }

    public func retire(plugin id: String) async {
        guard let slot = slots.removeValue(forKey: id) else { return }
        let rung = await slot.worker.stop(unloading: Array(slot.prepared.keys), waits: waits)
        log("scheduler: stopped \(id) \(slot.plugin.version) (\(rung.rawValue))")
        onWorkersChanged?()
    }

    // MARK: - Reading

    public func residentModels() -> [String] { slots.values.flatMap { $0.prepared.keys } }

    public func processes() -> [(pluginID: String, title: String, pid: pid_t, models: [String])] {
        slots.values.filter { $0.worker.isRunning }.map { ($0.plugin.id, $0.plugin.title, $0.worker.pid, Array($0.prepared.keys).sorted()) }
    }

    public func ledger() async -> Ledger {
        let host = ProcessFootprintReader.read(getpid()) ?? 0
        let entries = slots.values.sorted { $0.plugin.id < $1.plugin.id }.map { slot in
            let measured = slot.worker.physFootprint
            return Ledger.Entry(
                pluginID: slot.plugin.id, title: slot.plugin.title, version: slot.plugin.version, pid: slot.worker.pid,
                lanes: slot.prepared.mapValues(\.id), declaredBytes: slot.declaredBytes, physFootprintBytes: measured,
                reportedFootprintBytes: slot.report?.physFootprintBytes, reportedDeclaredBytes: slot.report?.declaredBytes,
                chargedBytes: max(slot.declaredBytes, measured ?? 0), busy: busy.contains(slot.plugin.id), overrun: slot.overrun)
        }
        return Ledger(budgetBytes: budgetBytes, hostFootprintBytes: host, workers: entries, queued: await gpu.queued)
    }

    /// What every other worker holds: the larger of its declared and measured memory.
    func charged(excluding id: String?) -> UInt64 {
        slots.values.filter { $0.plugin.id != id }.reduce(0) { $0 + max($1.declaredBytes, $1.worker.physFootprint ?? 0) }
    }

    func available(for id: String, keeping model: String) -> UInt64 {
        var used = charged(excluding: id)
        if let own = slots[id] {
            let others = own.prepared.filter { $0.key != model }.values
            used += others.reduce(0) { $0 + $1.resolved.persistentBytes }
        }
        return budgetBytes > used ? budgetBytes - used : 0
    }

    // MARK: - Running

    /// Runs one job on its plugin's worker, holding the GPU lane throughout. Launches the worker, frees memory and
    /// prepares the lane as needed. A worker that dies mid-run is relaunched and the run tried once more.
    public func run(_ job: WorkerJob, progress: @escaping @Sendable ([String: JSONValue]) -> Void) async throws -> WorkerJobResult {
        await gpu.acquire()
        busy.insert(job.pluginID)
        let outcome: Result<WorkerJobResult, Error>
        do {
            outcome = .success(try await attempt(job, progress: progress, requeued: false))
        } catch let failure as WorkerFailure where failure.workerExited && !Task.isCancelled {
            log("scheduler: \(job.pluginID)'s worker died during \(job.job) (\(failure.message)); requeueing once")
            database.record("worker_died", plugin: job.pluginID, version: slots[job.pluginID]?.plugin.version, "during \(job.job): \(failure.message)")
            slots[job.pluginID] = nil
            onWorkersChanged?()
            do {
                outcome = .success(try await attempt(job, progress: progress, requeued: true))
            } catch {
                outcome = .failure(error)
            }
        } catch {
            outcome = .failure(error)
        }
        busy.remove(job.pluginID)
        slots[job.pluginID]?.lastUsed = Date()
        await gpu.release()
        await manager.pluginBecameIdle(job.pluginID)
        return try outcome.get()
    }

    func attempt(_ job: WorkerJob, progress: @escaping @Sendable ([String: JSONValue]) -> Void, requeued: Bool) async throws -> WorkerJobResult {
        try Task.checkCancellation()
        // The signature is checked again before every launch (PLG-3); a running worker of the active version was checked
        // when it launched, and the kernel holds it to its launch requirement.
        let active = await manager.installed().first { $0.id == job.pluginID }
        let plugin: InstalledPlugin
        if let active, let slot = slots[job.pluginID], slot.worker.isRunning, slot.plugin.version == active.version {
            plugin = active
        } else {
            plugin = try await manager.launchable(job.pluginID)
        }
        guard plugin.enabled else { throw WorkerFailure(code: "unknown_model", message: "\(plugin.title) is disabled") }
        guard let model = plugin.model(job.model) else { throw WorkerFailure(code: "unknown_model", message: "no model \(job.model)") }

        // A worker on another version (an update switched in) is replaced.
        if let slot = slots[job.pluginID], slot.plugin.version != plugin.version || !slot.worker.isRunning {
            await retire(plugin: job.pluginID)
        }

        let preferred = try? database.setting("plugin:\(plugin.id):lane:\(model.id)")
        let (lane, fellBackFrom) = try await chooseLane(model, plugin: plugin.id, named: job.namedLane, preferred: preferred ?? nil)
        var fallbackMessage: String?
        if let fellBackFrom {
            fallbackMessage = "Loaded \(model.id) lane \(lane.id) (\(LaneChoice.need(lane).gb)) instead of the default \(fellBackFrom.id) "
                + "(\(LaneChoice.need(fellBackFrom).gb)), which doesn't fit in the memory free now."
            log("scheduler: lane_fallback \(model.id): \(fellBackFrom.id) → \(lane.id)")
        }

        let worker = try await ensureWorker(plugin)
        if slots[plugin.id]?.prepared[model.id]?.id != lane.id {
            if slots[plugin.id]?.prepared[model.id] != nil {
                try await worker.unload(model: model.id)
                slots[plugin.id]?.prepared[model.id] = nil
            }
            try await worker.prepare(model: model.id, lane: lane.id)
            slots[plugin.id]?.prepared[model.id] = lane
        }

        var fields: [String: JSONValue] = [
            "job": .string(job.job), "operation": .string(job.operation), "model": .string(model.id), "lane": .string(lane.id),
            "inputs": .object(job.inputs), "params": .object(job.params), "output_dir": .string(job.outputDir.path),
        ]
        if let modelParams = job.modelParams, !modelParams.isEmpty { fields["model_params"] = .object(modelParams) }
        if let seed = job.seed { fields["seed"] = .int(Int64(seed)) }
        try FileManager.default.createDirectory(at: job.outputDir, withIntermediateDirectories: true)

        let result = try await withTaskCancellationHandler {
            try await worker.request("run", fields, finals: ["result"], onLine: progress)
        } onCancel: {
            worker.cancel(job: job.job)
        }
        return WorkerJobResult(result: result, lane: lane.id, fellBackFrom: fellBackFrom?.id, fallbackMessage: fallbackMessage,
                               requeued: requeued)
    }

    /// Picks the lane after freeing what can be freed: idle workers go, least recently used first, until the default
    /// lane fits or nothing idle is left; then the lane rules decide (G-23).
    func chooseLane(_ model: PluginManifest.Model, plugin id: String, named: String?, preferred: String?) async throws
        -> (PluginManifest.Lane, PluginManifest.Lane?)
    {
        let target: PluginManifest.Lane? = named.flatMap { n in model.lanes.first { $0.id == n } }
            ?? preferred.flatMap { p in model.lanes.first { $0.id == p } } ?? model.lanes.first(where: \.default)
        while let target, LaneChoice.need(target) > available(for: id, keeping: model.id) {
            let idle = slots.values.filter { $0.plugin.id != id && !busy.contains($0.plugin.id) }.min { $0.lastUsed < $1.lastUsed }
            guard let idle else { break }
            log("scheduler: evicting \(idle.plugin.id) to make room for \(model.id) \(target.id)")
            await retire(plugin: idle.plugin.id)
        }
        do {
            let choice = try LaneChoice.choose(model, named: named, preferred: preferred, available: available(for: id, keeping: model.id))
            return (choice.lane, choice.fellBackFrom)
        } catch {
            throw error
        }
    }

    /// The plugin's running worker, or a new one: launched under the launch requirement, hello checked, configured.
    func ensureWorker(_ plugin: InstalledPlugin) async throws -> WorkerProcess {
        if let slot = slots[plugin.id], slot.worker.isRunning { return slot.worker }
        let cache = paths.pluginCache(plugin.id)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try migrateStore(plugin)
        let worker = WorkerProcess(pluginID: plugin.id, version: plugin.version, bundle: plugin.bundle, manifest: plugin.manifest,
                                   manifestData: plugin.manifestData, cacheRoot: cache, log: paths.pluginLog(plugin.id),
                                   sessions: paths.sessions)
        let pluginID = plugin.id
        let database = self.database
        worker.storage = { type, message in try Self.storage(type, message, plugin: pluginID, database: database) }
        worker.onMemory = { [weak self] report in Task { await self?.received(report, plugin: pluginID) } }
        worker.onExit = { [weak self] status, reason in Task { await self?.exited(pluginID, worker: worker, status: status, reason: reason) } }
        let helloAfter: Duration
        do {
            helloAfter = try await worker.start()
        } catch {
            database.record("launch_failed", plugin: plugin.id, version: plugin.version, "\(error)")
            log("scheduler: \(plugin.id) \(plugin.version) failed to launch: \(error)")
            throw error
        }
        log("scheduler: launched \(plugin.id) \(plugin.version), pid \(worker.pid), hello after \(helloAfter)")
        slots[plugin.id] = Slot(worker: worker, plugin: plugin)
        onWorkersChanged?()
        let ceiling = max(available(for: plugin.id, keeping: ""), 1 << 30)
        try await worker.configure(budget: WorkerBudgetWire(ceilingBytes: ceiling, wiresWeights: false), modelsRoot: paths.modelsRoot,
                                   cacheRoot: cache, settings: settings(for: plugin))
        return worker
    }

    /// Each setting's default from the manifest, overridden by the operator's value in gaea.sqlite.
    func settings(for plugin: InstalledPlugin) -> [String: JSONValue] {
        var values: [String: JSONValue] = [:]
        for setting in plugin.manifest.settings ?? [] {
            if let stored = (try? database.setting("plugin:\(plugin.id):setting:\(setting.key)")) ?? nil,
               let value = try? JSONDecoder().decode(JSONValue.self, from: Data(stored.utf8)) {
                values[setting.key] = value
            } else if let value = setting.schema["default"] {
                values[setting.key] = value
            }
        }
        return values
    }

    /// Records the store schema a new version declares before it launches (GPP-1 §3.6).
    func migrateStore(_ plugin: InstalledPlugin) throws {
        guard let storage = plugin.manifest.storage else { return }
        let current = try database.storeSchema(plugin: plugin.id)
        if current?.version != storage.schemaVersion || current?.migrations != storage.migrations {
            try database.setStoreSchema(plugin: plugin.id, version: storage.schemaVersion, migrations: storage.migrations)
            database.record("store_migrated", plugin: plugin.id, version: plugin.version,
                            "store schema \(current?.version ?? 0) → \(storage.schemaVersion)")
        }
    }

    func received(_ report: WorkerMemoryReportWire, plugin id: String) {
        guard var slot = slots[id] else { return }
        slot.report = report
        // A worker well past its declaration is a manifest bug, logged against the plugin version once (MEM-4).
        let declared = slot.declaredBytes
        if let measured = report.physFootprintBytes, !slot.overrun, measured > declared + declared / 4 + (512 << 20) {
            slot.overrun = true
            let lanes = slot.prepared.map { "\($0.key)/\($0.value.id)" }.sorted().joined(separator: ", ")
            database.record("memory_overrun", plugin: id, version: slot.plugin.version,
                            "phys_footprint \(measured.gb) is past the declared \(declared.gb) (lanes: \(lanes.isEmpty ? "none" : lanes))")
            log("ledger: \(id) \(slot.plugin.version) runs at \(measured.gb), past its declared \(declared.gb)")
        }
        slots[id] = slot
    }

    func exited(_ id: String, worker: WorkerProcess, status: Int32, reason: Process.TerminationReason) {
        guard slots[id]?.worker === worker else { return }
        slots[id] = nil
        log("scheduler: \(id)'s worker exited (\(reason == .uncaughtSignal ? "signal" : "status") \(status))")
        onWorkersChanged?()
    }

    /// Shuts down workers idle longer than the idle timeout.
    public func sweepIdle() async {
        let cutoff = Date().addingTimeInterval(-Double(idleTimeout.components.seconds))
        for slot in slots.values where !busy.contains(slot.plugin.id) && slot.lastUsed < cutoff {
            log("scheduler: \(slot.plugin.id) idle since \(slot.lastUsed.formatted(.iso8601)); stopping")
            await retire(plugin: slot.plugin.id)
        }
    }

    /// Releases a model from memory if no job is using it: `unload` to its worker, which stops once nothing is left.
    public func unload(model id: String) async {
        guard let slot = slots.values.first(where: { $0.prepared[id] != nil }), !busy.contains(slot.plugin.id) else { return }
        if slot.prepared.count == 1 {
            await retire(plugin: slot.plugin.id)
        } else {
            try? await slot.worker.unload(model: id)
            slots[slot.plugin.id]?.prepared[id] = nil
        }
    }

    public func stopAll() async {
        for id in slots.keys { await retire(plugin: id) }
    }

    // MARK: - Plugin stores (GPP-1 §3.6)

    static func storage(_ type: String, _ message: [String: JSONValue], plugin: String, database: GaeaDatabase) throws -> [String: JSONValue] {
        guard let namespace = message["namespace"]?.stringValue, !namespace.isEmpty else {
            throw WorkerFailure(code: "storage_failed", message: "a storage request needs a namespace")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func decode(_ text: String) -> JSONValue { (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .null }
        do {
            switch type {
            case "storage.get":
                guard let key = message["key"]?.stringValue else { throw WorkerFailure(code: "storage_failed", message: "no key") }
                if let value = try database.storeGet(plugin: plugin, namespace: namespace, key: key) {
                    return ["found": true, "value": decode(value)]
                }
                return ["found": false]
            case "storage.put":
                guard let key = message["key"]?.stringValue, let value = message["value"] else {
                    throw WorkerFailure(code: "storage_failed", message: "put needs a key and a value")
                }
                let data = try encoder.encode(value)
                guard data.count <= GPP.maxStorageValueBytes else {
                    throw WorkerFailure(code: "storage_failed", message: "a stored value is at most 1 MiB")
                }
                try database.storePut(plugin: plugin, namespace: namespace, key: key, value: String(decoding: data, as: UTF8.self))
                return [:]
            case "storage.delete":
                guard let key = message["key"]?.stringValue else { throw WorkerFailure(code: "storage_failed", message: "no key") }
                try database.storeDelete(plugin: plugin, namespace: namespace, key: key)
                return [:]
            case "storage.query":
                let limit = min(message["limit"]?.intValue ?? 100, 1000)
                let (items, more) = try database.storeQuery(plugin: plugin, namespace: namespace, prefix: message["prefix"]?.stringValue,
                                                            after: message["after"]?.stringValue, limit: limit)
                return ["items": .array(items.map { .object(["key": .string($0.key), "value": decode($0.value)]) }), "more": .bool(more)]
            default:
                throw WorkerFailure(code: "storage_failed", message: "unknown storage request \(type)")
            }
        } catch let failure as WorkerFailure {
            throw failure
        } catch {
            throw WorkerFailure(code: "storage_failed", message: "\(error)")
        }
    }
}

enum ProcessFootprintReader {
    static func read(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return r == 0 ? info.ri_phys_footprint : nil
    }
}
