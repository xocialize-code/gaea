import Darwin
import Foundation
import GaeaProtocol
import MLXMemoryPolicy
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
        /// The memory policy refused the admission (MLXMemoryPolicy's `AdmissionRefusal`), with its reason.
        case policy(String)
        /// The weights' volume reads slower than every remaining lane's floor, or than the named lane's (GPP-1 §3.2.1).
        case storageBelowFloor(String, readBytesPerSecond: UInt64, floorBytesPerSecond: UInt64)

        public var description: String {
            switch self {
            case let .unknownLane(lane, model): "\(model) has no lane \(lane)."
            case let .namedDoesNotFit(lane, need, available):
                "Lane \(lane) needs \(need.gb) and \(available.gb) is free; a request that names a lane never falls back."
            case let .nothingFits(need, available): "No lane fits: the smallest needs \(need.gb) and \(available.gb) is free."
            case let .policy(reason): reason
            case let .storageBelowFloor(lane, read, floor):
                "Lane \(lane)'s weights need a volume that reads \(floor.mbps); this one reads \(read.mbps)."
            }
        }
    }

    /// Persistent weights plus the peak transient: what a lane needs while it runs.
    public static func need(_ lane: PluginManifest.Lane) -> UInt64 { lane.resolved.persistentBytes &+ lane.resolved.peakTransientBytes }

    /// `model` with each lane's need raised to what that lane was measured holding, where that's more than it declares
    /// (`measured` by lane id). The persistent part stays declared; the transient takes the rest.
    public static func learned(_ model: PluginManifest.Model, measured: [String: UInt64]) -> PluginManifest.Model {
        var model = model
        for i in model.lanes.indices {
            let r = model.lanes[i].resolved
            guard let peak = measured[model.lanes[i].id], peak > need(model.lanes[i]) else { continue }
            model.lanes[i].resolved = ResolvedLane(
                contractVersion: r.contractVersion, quant: r.quant, footprintQuant: r.footprintQuant,
                persistentBytes: r.persistentBytes, persistentSource: r.persistentSource,
                peakTransientBytes: peak - r.persistentBytes, peakTransientSource: r.peakTransientSource,
                activationScaling: r.activationScaling, expectedWeightReadBytesPerRun: r.expectedWeightReadBytesPerRun,
                minSustainedReadBytesPerSecond: r.minSustainedReadBytesPerSecond, materialization: r.materialization,
                weightSources: r.weightSources, selfMaterializing: r.selfMaterializing, capabilities: r.capabilities)
        }
        return model
    }

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
    var mbps: String { String(format: "%.0f MB/s", Double(self) / 1e6) }
}

/// Lanes whose weights need a faster volume than the one measured (GPP-1 §3.2.1): a lane's
/// `minSustainedReadBytesPerSecond` above what the engine read is a mid-run crash, so the lane isn't chosen.
public enum StorageFloor {
    /// `model` without the lanes `read` is too slow for. A named lane among them is a refusal; with no lane left,
    /// so is the request. The default moves to the first lane left, reported as a fallback from the old one.
    public static func filter(_ model: PluginManifest.Model, read: UInt64?, named: String?) throws(LaneChoice.Refusal)
        -> (model: PluginManifest.Model, skipped: PluginManifest.Lane?)
    {
        guard let read else { return (model, nil) }
        func tooSlow(_ lane: PluginManifest.Lane) -> Bool { (lane.resolved.minSustainedReadBytesPerSecond ?? 0) > read }
        if let named, let lane = model.lanes.first(where: { $0.id == named }), tooSlow(lane) {
            throw .storageBelowFloor(named, readBytesPerSecond: read, floorBytesPerSecond: lane.resolved.minSustainedReadBytesPerSecond ?? 0)
        }
        var kept = model
        kept.lanes = model.lanes.filter { !tooSlow($0) }
        guard let first = kept.lanes.first else {
            let floor = model.lanes.compactMap(\.resolved.minSustainedReadBytesPerSecond).min() ?? 0
            throw .storageBelowFloor(model.lanes.map(\.id).joined(separator: ", "), readBytesPerSecond: read, floorBytesPerSecond: floor)
        }
        let skipped = model.lanes.first(where: \.default).flatMap { tooSlow($0) ? $0 : nil }
        if skipped != nil { kept.lanes = kept.lanes.map { var l = $0; l.default = l.id == first.id; return l } }
        return (kept, skipped)
    }
}

/// A run handed to a plugin worker.
public struct WorkerJob: Sendable {
    public var job: String
    public var pluginID: String
    public var model: String
    public var operation: String
    /// `x-gaea.lane` from the request: that lane or a refusal.
    public var namedLane: String?
    /// The lanes the offer may run on (GPP-1 §4.3); nil for all of the model's.
    public var lanes: [String]?
    public var params: [String: JSONValue]
    public var inputs: [String: JSONValue]
    public var modelParams: [String: JSONValue]?
    public var adapters: [JSONValue]
    public var seed: Int?
    public var outputDir: URL
    /// The outputs the worker streams (GPP-1 §3.3.1). A run that streams is never requeued: its client has chunks already.
    public var streams: [String] = []
    /// The MES asset id behind each input value (GPP-1 §3.3.2).
    public var assets: [String: JSONValue] = [:]

    public init(job: String, pluginID: String, model: String, operation: String, namedLane: String? = nil, lanes: [String]? = nil,
                params: [String: JSONValue] = [:], inputs: [String: JSONValue] = [:], modelParams: [String: JSONValue]? = nil,
                adapters: [JSONValue] = [], seed: Int? = nil, outputDir: URL) {
        self.job = job
        self.pluginID = pluginID
        self.model = model
        self.operation = operation
        self.namedLane = namedLane
        self.lanes = lanes
        self.params = params
        self.inputs = inputs
        self.modelParams = modelParams
        self.adapters = adapters
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
        /// `ri_lifetime_max_phys_footprint`: the most the worker has held since it started.
        public var peakFootprintBytes: UInt64?
        /// What the worker's own last memory report said.
        public var reportedFootprintBytes: UInt64?
        public var reportedDeclaredBytes: UInt64?
        /// What the governor charges (MLXMemoryPolicy): an idle worker the larger of its resident bytes and what it
        /// measures; a running one its resident bytes plus its run's peak.
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
/// worker dies (SRV-8), every such death recorded as a crash and a plugin quarantined on its third in ten minutes (G-26). Admission and eviction are MLXMemoryPolicy's, the rule MLXServeEngine runs in-process
/// (AB-D-0170, AB-T-0371): each worker is a tenant, and its job a run on it.
public actor Scheduler: WorkerControl {
    let manager: PluginManager
    let database: GaeaDatabase
    let paths: GaeaPaths
    let log: HostLog
    public let budgetBytes: UInt64
    /// MLXServeEngine's rules with two settings for one GPU job at a time across processes: only the job being admitted
    /// reserves a peak, and an idle worker is charged the larger of its resident bytes and its measured footprint.
    public let policy: MemoryPolicy
    /// The shared weights folder workers are configured with (G-9, MEM-8): `--models-root`, else the operator's
    /// `models.root` setting, else MLXEngine's store.
    public private(set) var modelsRoot: URL
    /// Workers to stop once their run ends, because the models root changed under them.
    var restartWhenIdle: Set<String> = []
    let gpu = GPULane()
    var waits = WorkerProcess.Waits()
    /// Workers idle this long are shut down.
    var idleTimeout: Duration
    /// Whether workers keep their weights wired while they run (AB-T-0380). MLX's wired limit is per process, and a worker
    /// raises its own only for its run, to its resident weights and that run's transient, then drops it to 0. With one
    /// GPU job at a time that wires at most the one job the governor admitted. `GAEA_UNWIRED=1` leaves it at 0, for
    /// measuring the difference.
    let wiresWeights = ProcessInfo.processInfo.environment["GAEA_UNWIRED"] != "1"

    struct Slot {
        var worker: WorkerProcess
        var plugin: InstalledPlugin
        var prepared: [String: PluginManifest.Lane] = [:]
        var lastUsed = Date()
        var report: WorkerMemoryReportWire?
        var overrun = false
        /// Every `model/lane` this worker has prepared since it started: its lifetime peak is a lane's own only while
        /// this holds one.
        var everPrepared: Set<String> = []

        var persistentBytes: UInt64 { prepared.values.reduce(0) { $0 + $1.resolved.persistentBytes } }
        var peakTransientBytes: UInt64 { prepared.values.map(\.resolved.peakTransientBytes).max() ?? 0 }
        var declaredBytes: UInt64 { persistentBytes + peakTransientBytes }
    }

    var slots: [String: Slot] = [:]
    /// What the engine measured of each model's weights volume when it refused a lane (`plugin/model` → bytes per second).
    var volumeReads: [String: UInt64] = [:]
    var busy: Set<String> = []
    /// Called whenever a worker starts or stops (the System page's process list).
    var onWorkersChanged: (@Sendable () -> Void)?
    /// Where macOS writes crash reports.
    let crashReports: CrashReports

    /// What each busy plugin is running, for its crash record.
    struct Running {
        var job: String
        var model: String
        var lane: String?
        var version: String?
    }
    var running: [String: Running] = [:]
    /// The worker launches whose exits are already recorded as crashes, newest last.
    var recordedExits: [UUID] = []

    /// This many crashes of one plugin within `quarantineWindow` quarantine it (G-26).
    public static let quarantineCrashes = 3
    public static let quarantineWindow: TimeInterval = 600

    public init(manager: PluginManager, database: GaeaDatabase, paths: GaeaPaths, log: HostLog,
                budgetBytes: UInt64? = nil, modelsRoot: URL? = nil, idleTimeout: Duration = .seconds(900),
                crashReports: CrashReports = CrashReports()) {
        self.manager = manager
        self.crashReports = crashReports
        self.database = database
        self.paths = paths
        self.log = log
        self.idleTimeout = idleTimeout
        let stored = (try? database.setting(Self.modelsRootSetting)).flatMap { $0 }.map { URL(fileURLWithPath: $0, isDirectory: true) }
        self.modelsRoot = modelsRoot ?? stored ?? paths.modelsRoot
        // Three quarters of unified memory, unless the operator set a budget.
        let configured = (try? database.setting("memory.budget_bytes")).flatMap { $0 }.flatMap(UInt64.init)
        let budget = budgetBytes ?? configured ?? ProcessInfo.processInfo.physicalMemory / 4 * 3
        self.budgetBytes = budget
        self.policy = MemoryPolicy(budgetBytes: budget, transientAccounting: .admittedRunsOnly, idleCharge: .largerOfDeclaredAndMeasured)
    }

    public func setWaits(_ waits: WorkerProcess.Waits) { self.waits = waits }

    /// The `gaea.sqlite` setting that holds the operator's models root.
    public static let modelsRootSetting = "models.root"

    /// The gaea.sqlite key of the operator's default lane for one plugin model (MEM-7).
    public static func laneSetting(plugin: String, model: String) -> String { "plugin:\(plugin):lane:\(model)" }

    /// Changes the models root and keeps it (nil returns to MLXEngine's store). Idle workers stop now and busy ones when
    /// their run ends, so the next job's worker is configured with the new folder.
    public func setModelsRoot(_ url: URL?) async throws {
        let root = url?.standardizedFileURL ?? paths.modelsRoot
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkerFailure(code: "invalid_request", message: "\(root.path) isn't a folder.")
        }
        try database.setSetting(Self.modelsRootSetting, url == nil ? nil : root.path)
        guard root.path != modelsRoot.path else { return }
        log("scheduler: models root \(modelsRoot.path) → \(root.path)")
        modelsRoot = root
        for id in Array(slots.keys) {
            if busy.contains(id) { restartWhenIdle.insert(id) } else { await retire(plugin: id) }
        }
    }
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
        let state = memoryState()
        let entries = slots.values.sorted { $0.plugin.id < $1.plugin.id }.map { slot in
            let measured = slot.worker.physFootprint
            let running = busy.contains(slot.plugin.id)
            let charge = state.tenants.first { $0.id == slot.plugin.id }.map { policy.charge($0, in: state) } ?? slot.persistentBytes
            return Ledger.Entry(
                pluginID: slot.plugin.id, title: slot.plugin.title, version: slot.plugin.version, pid: slot.worker.pid,
                lanes: slot.prepared.mapValues(\.id), declaredBytes: slot.declaredBytes, physFootprintBytes: measured,
                peakFootprintBytes: slot.worker.peakFootprint,
                reportedFootprintBytes: slot.report?.physFootprintBytes, reportedDeclaredBytes: slot.report?.declaredBytes,
                chargedBytes: charge + (running ? slot.peakTransientBytes : 0), busy: running, overrun: slot.overrun)
        }
        return Ledger(budgetBytes: budgetBytes, hostFootprintBytes: host, workers: entries, queued: await gpu.queued)
    }

    /// The workers as MLXMemoryPolicy sees them: each a tenant with its prepared lanes' resident bytes, their largest peak
    /// and its measured footprint, and each busy one with a run.
    func memoryState() -> MemoryState {
        let tenants = slots.values.sorted { $0.plugin.id < $1.plugin.id }.map { slot in
            MemoryTenant(id: slot.plugin.id, persistentBytes: slot.persistentBytes, peakTransientBytes: slot.peakTransientBytes,
                         measuredBytes: slot.worker.physFootprint,
                         lastUsed: UInt64(max(0, slot.lastUsed.timeIntervalSinceReferenceDate) * 1000), evictable: slot.worker.isRunning)
        }
        let runs = slots.values.filter { busy.contains($0.plugin.id) }.map {
            MemoryRun(token: "run:\($0.plugin.id)", tenant: $0.plugin.id, transientBytes: $0.peakTransientBytes)
        }
        return MemoryState(tenants: tenants, runs: runs)
    }

    /// What a job on worker `id` can have for one model's lane: the budget less what every other worker is charged (or,
    /// `evictingIdle`, what the busy ones are, as if every idle one were stopped), less the resident bytes of `id`'s other
    /// models when it keeps them.
    func available(for id: String, keeping model: String, evictingIdle: Bool, keepingOwn: Bool = true) -> UInt64 {
        var others = memoryState()
        others.tenants.removeAll { $0.id == id }
        others.runs.removeAll { $0.tenant == id }
        let free = evictingIdle ? policy.availableBytes(others, afterEvictingIdleExcept: nil) : policy.availableBytes(others)
        let own = keepingOwn ? ownBytes(id, except: model) : 0
        return free > own ? free - own : 0
    }

    /// The resident bytes of the models worker `id` holds besides `model`.
    func ownBytes(_ id: String, except model: String) -> UInt64 {
        slots[id]?.prepared.filter { $0.key != model }.values.reduce(0) { $0 + $1.resolved.persistentBytes } ?? 0
    }

    // MARK: - Running

    /// Runs one job on its plugin's worker, holding the GPU lane throughout. Launches the worker, frees memory and
    /// prepares the lane as needed. A worker that dies mid-run is relaunched and the run tried once more.
    public func run(_ job: WorkerJob, progress: @escaping @Sendable ([String: JSONValue]) -> Void) async throws -> WorkerJobResult {
        await gpu.acquire()
        busy.insert(job.pluginID)
        running[job.pluginID] = Running(job: job.job, model: job.model)
        let outcome: Result<WorkerJobResult, Error>
        do {
            outcome = .success(try await attempt(job, progress: progress, requeued: false))
        } catch let failure as WorkerFailure where failure.workerExited && !Task.isCancelled && job.streams.isEmpty {
            log("scheduler: \(job.pluginID)'s worker died during \(job.job) (\(failure.message)); requeueing once")
            database.record("worker_died", plugin: job.pluginID, version: slots[job.pluginID]?.plugin.version, "during \(job.job): \(failure.message)")
            slots[job.pluginID] = nil
            onWorkersChanged?()
            let first = await crashed(failure.exit, plugin: job.pluginID, outcome: .requeued)
            do {
                outcome = .success(try await attempt(job, progress: progress, requeued: true))
            } catch let again as WorkerFailure where again.workerExited && !Task.isCancelled {
                slots[job.pluginID] = nil
                onWorkersChanged?()
                let second = await crashed(again.exit, plugin: job.pluginID, outcome: .failed)
                outcome = .failure(crashFailure(again, crashes: [first, second], plugin: job.pluginID))
            } catch {
                outcome = .failure(error)
            }
        } catch let failure as WorkerFailure where failure.workerExited && !Task.isCancelled {
            // A streamed run is never requeued: its client has chunks already.
            slots[job.pluginID] = nil
            onWorkersChanged?()
            let crash = await crashed(failure.exit, plugin: job.pluginID, outcome: .failed)
            outcome = .failure(crashFailure(failure, crashes: [crash], plugin: job.pluginID))
        } catch {
            outcome = .failure(error)
        }
        running[job.pluginID] = nil
        busy.remove(job.pluginID)
        slots[job.pluginID]?.lastUsed = Date()
        if restartWhenIdle.remove(job.pluginID) != nil { await retire(plugin: job.pluginID) }
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
        guard plugin.trusted else {
            throw WorkerFailure(code: "unknown_model", message: "\(plugin.title)'s team \(plugin.manifest.team) isn't trusted")
        }
        guard plugin.enabled else {
            if let reason = ((try? database.plugin(plugin.id)) ?? nil)?.quarantineReason {
                throw WorkerFailure(code: "unknown_model", message: "\(plugin.title) is quarantined after \(reason), until the operator switches it on")
            }
            throw WorkerFailure(code: "unknown_model", message: "\(plugin.title) is disabled")
        }
        running[plugin.id]?.version = plugin.version
        guard var model = plugin.model(job.model) else { throw WorkerFailure(code: "unknown_model", message: "no model \(job.model)") }
        if let allowed = job.lanes {
            model.lanes = model.lanes.filter { allowed.contains($0.id) }
            guard !model.lanes.isEmpty else { throw WorkerFailure(code: "unknown_model", message: "no lane of \(model.id) serves this offer") }
            if !model.lanes.contains(where: \.default) { model.lanes[0].default = true }
        }
        // A lane measured holding more than it declares is admitted at what it held (AB-T-0405).
        model = LaneChoice.learned(model, measured: measuredPeaks(plugin: plugin, model: model.id))

        // A worker on another version (an update switched in) is replaced.
        if let slot = slots[job.pluginID], slot.plugin.version != plugin.version || !slot.worker.isRunning {
            await retire(plugin: job.pluginID)
        }

        // Lanes the weights' volume is already known to be too slow for are never chosen (GPP-1 §3.2.1).
        let storageKey = "\(plugin.id)/\(model.id)"
        let (fast, skipped) = try StorageFloor.filter(model, read: volumeReads[storageKey], named: job.namedLane)
        let preferred = (try? database.setting(Self.laneSetting(plugin: plugin.id, model: model.id))) ?? nil
        let (lane, memoryFallback) = try await chooseLane(fast, plugin: plugin.id, named: job.namedLane,
                                                          preferred: preferred.flatMap { p in fast.lanes.contains { $0.id == p } ? p : nil },
                                                          conduct: requeued ? .waiting : .preempting)
        var fellBackFrom = memoryFallback
        var fallbackMessage: String?
        if let skipped, skipped.id != lane.id {
            fellBackFrom = skipped
            fallbackMessage = "Loaded \(model.id) lane \(lane.id) instead of the default \(skipped.id), whose weights need a volume "
                + "that reads \((skipped.resolved.minSustainedReadBytesPerSecond ?? 0).mbps); this one reads \((volumeReads[storageKey] ?? 0).mbps)."
            log("scheduler: lane_fallback \(model.id): \(skipped.id) → \(lane.id) (storage floor)")
        } else if let memoryFallback {
            fallbackMessage = "Loaded \(model.id) lane \(lane.id) (\(LaneChoice.need(lane).gb)) instead of the default \(memoryFallback.id) "
                + "(\(LaneChoice.need(memoryFallback).gb)), which doesn't fit in the memory free now."
            log("scheduler: lane_fallback \(model.id): \(memoryFallback.id) → \(lane.id)")
        }

        running[plugin.id]?.lane = lane.id
        let worker = try await ensureWorker(plugin)
        if slots[plugin.id]?.prepared[model.id]?.id != lane.id {
            if slots[plugin.id]?.prepared[model.id] != nil {
                try await worker.unload(model: model.id)
                slots[plugin.id]?.prepared[model.id] = nil
            }
            do {
                try await worker.prepare(model: model.id, lane: lane.id)
            } catch let failure as WorkerFailure where failure.code == "storage_below_floor" {
                // Measured now: remember it, so the next choice skips every lane this volume can't feed, and choose again.
                let read = failure.detail?["read_bytes_per_s"]?.intValue.map { UInt64(max(0, $0)) } ?? 0
                volumeReads[storageKey] = read
                log("scheduler: \(model.id) lane \(lane.id) refused: the weights' volume reads \(read.mbps) (\(failure.message))")
                database.record("storage_below_floor", plugin: plugin.id, version: plugin.version,
                                "\(model.id) \(lane.id): \(failure.message)")
                return try await attempt(job, progress: progress, requeued: requeued)
            }
            slots[plugin.id]?.prepared[model.id] = lane
            slots[plugin.id]?.everPrepared.insert("\(model.id)/\(lane.id)")
        }

        var fields: [String: JSONValue] = [
            "job": .string(job.job), "operation": .string(job.operation), "model": .string(model.id), "lane": .string(lane.id),
            "inputs": .object(job.inputs), "params": .object(job.params), "output_dir": .string(job.outputDir.path),
        ]
        if let modelParams = job.modelParams, !modelParams.isEmpty { fields["model_params"] = .object(modelParams) }
        if !job.adapters.isEmpty { fields["adapters"] = .array(job.adapters) }
        if let seed = job.seed { fields["seed"] = .int(Int64(seed)) }
        if !job.streams.isEmpty { fields["streams"] = .array(job.streams.map(JSONValue.string)) }
        if !job.assets.isEmpty { fields["assets"] = .object(job.assets) }
        try FileManager.default.createDirectory(at: job.outputDir, withIntermediateDirectories: true)

        let result = try await withTaskCancellationHandler {
            try await worker.request("run", fields, finals: ["result"], onLine: progress)
        } onCancel: {
            worker.cancel(job: job.job)
        }
        learnPeak(plugin: plugin, model: model.id, lane: lane, worker: worker)
        return WorkerJobResult(result: result, lane: lane.id, fellBackFrom: fellBackFrom?.id, fallbackMessage: fallbackMessage,
                               requeued: requeued)
    }

    /// Picks the lane (G-23) against what stopping every idle worker would free, then admits it under the memory policy.
    /// A lane that fits only without the worker's own other models has them unloaded first: the policy sees workers,
    /// not the models inside one.
    func chooseLane(_ model: PluginManifest.Model, plugin id: String, named: String?, preferred: String?,
                    conduct: AdmissionConduct) async throws -> (PluginManifest.Lane, PluginManifest.Lane?)
    {
        let keeping = available(for: id, keeping: model.id, evictingIdle: true)
        var choice = try? LaneChoice.choose(model, named: named, preferred: preferred, available: keeping)
        var dropOwn = false
        if choice == nil || choice?.fellBackFrom != nil, ownBytes(id, except: model.id) > 0,
           let better = try? LaneChoice.choose(model, named: named, preferred: preferred,
                                               available: available(for: id, keeping: model.id, evictingIdle: true, keepingOwn: false)),
           choice == nil || better.fellBackFrom == nil {
            choice = better
            dropOwn = true
        }
        // Nothing fits either way: the refusal names what the worker keeping its models would have.
        let chosen = try choice ?? LaneChoice.choose(model, named: named, preferred: preferred, available: keeping)
        if dropOwn, let slot = slots[id] {
            for other in slot.prepared.keys.sorted() where other != model.id {
                log("scheduler: unloading \(other) from \(id)'s worker: \(model.id) \(chosen.lane.id) fits only without it")
                try await slot.worker.unload(model: other)
                slots[id]?.prepared[other] = nil
            }
        }
        try await admit(chosen.lane, model: model.id, plugin: id, conduct: conduct)
        return (chosen.lane, chosen.fellBackFrom)
    }

    /// Admits a lane under MLXMemoryPolicy and carries out its plan: the idle workers it evicts, least recently used
    /// first, and those real pressure evicts, each logged with the policy's reason. A refusal is `no_capacity`.
    func admit(_ lane: PluginManifest.Lane, model: String, plugin id: String, conduct: AdmissionConduct) async throws {
        let state = memoryState()
        let admission = MemoryAdmission(tenant: id, persistentBytes: ownBytes(id, except: model) + lane.resolved.persistentBytes,
                                        transientBytes: lane.resolved.peakTransientBytes)
        // R-MEM-1 reads what the other workers measure, plus what this one will hold.
        let reading = state.tenants.filter { $0.id != id }.reduce(admission.persistentBytes) { $0 + ($1.measuredBytes ?? $1.persistentBytes) }
        let plan = policy.plan(admission, in: state, conduct: conduct, measuredReading: reading)
        let what = "\(model) \(lane.id)"
        if case .refused(let refusal) = plan.outcome {
            let reason = switch refusal {
            case let .exceedsBudget(required, budget): "\(what) needs \(required.gb) and the budget is \(budget.gb)."
            case let .externalTenantsHoldMemory(required, external, budget):
                "\(what) needs \(required.gb) beside the \(external.gb) other processes hold, in a \(budget.gb) budget."
            }
            log("scheduler: policy refuses \(what): \(reason)")
            throw LaneChoice.Refusal.policy(reason)
        }
        guard !plan.evictions.isEmpty || plan.outcome != .fits else { return }
        let charges = Dictionary(uniqueKeysWithValues: state.tenants.map { ($0.id, policy.charge($0, in: state)) })
        log("scheduler: policy plan for \(what) on \(id): needs \(policy.required(admission, in: state).gb) of \(budgetBytes.gb), "
            + "evicting [\(plan.evictions.joined(separator: ", "))]")
        for step in plan.steps {
            switch step {
            case .evict(let tenant):
                log("scheduler: evicting \(tenant) to make room for \(what) (idle, least recently used; charged \((charges[tenant] ?? 0).gb))")
                await retire(plugin: tenant)
            case .preempt(_, let tenant), .awaitRun(_, let tenant), .endLiveSession(_, let tenant):
                // One GPU job at a time: no other worker is mid-run while this job holds the lane.
                log("scheduler: the policy would reclaim \(tenant) for \(what), but no other job runs while this one is admitted")
            }
        }
        for tenant in plan.realPressureEvictions {
            log("scheduler: evicting \(tenant) to make room for \(what) (real pressure: the measured footprints are past "
                + "\(policy.realPressureCeiling.gb))")
            await retire(plugin: tenant)
        }
        if case .overcommitted(let short) = plan.outcome {
            log("scheduler: \(what) admitted over-committed by \(short.gb): no idle worker is left to stop")
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
        // The whole budget: Gaea admits every lane across workers itself (`admit`), so a ceiling cut to what the others
        // held at launch would go stale as soon as one of them stopped, and the worker would refuse what Gaea admitted.
        try await worker.configure(budget: WorkerBudgetWire(ceilingBytes: budgetBytes, wiresWeights: wiresWeights), modelsRoot: modelsRoot,
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

    /// The setting that keeps what a lane was measured holding, per plugin version.
    static func peakSetting(plugin: InstalledPlugin, model: String, lane: String) -> String {
        "measured-peak/\(plugin.id)@\(plugin.version)/\(model)/\(lane)"
    }

    /// What each lane of `model` was measured holding, by lane id.
    func measuredPeaks(plugin: InstalledPlugin, model: String) -> [String: UInt64] {
        var out: [String: UInt64] = [:]
        for lane in plugin.model(model)?.lanes ?? [] {
            if let v = (try? database.setting(Self.peakSetting(plugin: plugin, model: model, lane: lane.id))) ?? nil, let bytes = UInt64(v) {
                out[lane.id] = bytes
            }
        }
        return out
    }

    /// After a run on a worker that has held only this lane, its lifetime peak is the lane's: kept when it's past what
    /// the lane declares and what was measured before, so the next admission charges it.
    func learnPeak(plugin: InstalledPlugin, model: String, lane: PluginManifest.Lane, worker: WorkerProcess) {
        guard slots[plugin.id]?.everPrepared == ["\(model)/\(lane.id)"], let peak = worker.peakFootprint else { return }
        let key = Self.peakSetting(plugin: plugin, model: model, lane: lane.id)
        let known = ((try? database.setting(key)) ?? nil).flatMap(UInt64.init) ?? 0
        guard peak > max(known, LaneChoice.need(lane)) else { return }
        try? database.setSetting(key, String(peak))
        database.record("memory_learned", plugin: plugin.id, version: plugin.version,
                        "\(model) lane \(lane.id) held \(peak.gb), past its declared \(LaneChoice.need(lane).gb); admitted at that from now on")
        log("scheduler: \(model) lane \(lane.id) held \(peak.gb), past \(LaneChoice.need(lane).gb); admitting it at that from now on")
        // The worker's own charge follows at once.
        if let current = slots[plugin.id]?.prepared[model], current.id == lane.id, let learned = plugin.model(model).map({
            LaneChoice.learned($0, measured: [lane.id: peak]) })?.lanes.first(where: { $0.id == lane.id }) {
            slots[plugin.id]?.prepared[model] = learned
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

    func exited(_ id: String, worker: WorkerProcess, status: Int32, reason: Process.TerminationReason) async {
        if slots[id]?.worker === worker {
            slots[id] = nil
            log("scheduler: \(id)'s worker exited (\(reason == .uncaughtSignal ? "signal" : "status") \(status))")
            onWorkersChanged?()
        }
        // A death during a job is `run`'s to record, since it knows what became of the job.
        if !busy.contains(id) { await crashed(worker.exitInfo, plugin: id, version: worker.version, outcome: .idle) }
    }

    // MARK: - Crashes (SRV-8, G-26)

    /// Records a worker death Gaea didn't ask for, looks for macOS's crash report, and quarantines the plugin on its third
    /// crash in ten minutes. Nil for an exit Gaea asked for, or one already recorded.
    @discardableResult
    func crashed(_ exit: WorkerExit?, plugin id: String, version: String? = nil, outcome: CrashRecord.Outcome) async -> CrashRecord? {
        guard let exit, !exit.expected, !recordedExits.contains(exit.worker) else { return nil }
        recordedExits.append(exit.worker)
        if recordedExits.count > 64 { recordedExits.removeFirst() }
        let context = outcome == .idle ? nil : running[id]
        let version = version ?? context?.version ?? "?"
        var crash = CrashRecord(
            at: exit.at, pluginID: id, version: version, pid: exit.pid, how: exit.how, signal: exit.signalled ? exit.status : nil,
            status: exit.signalled ? nil : exit.status, fault: exit.fault, model: context?.model, lane: context?.lane, job: context?.job,
            outcome: outcome, stderrTail: exit.stderrTail,
            reportNote: exit.writesCrashReport ? "looking for macOS's crash report" : "none: \(exit.how) writes no crash report")
        do {
            crash.id = try database.insertCrash(crash)
        } catch {
            log("scheduler: couldn't record \(id)'s crash: \(error)")
            return nil
        }
        let doing = context.map { " running \($0.model) for \($0.job)" } ?? " while idle"
        log("scheduler: crash #\(crash.id!): \(id) \(version) pid \(exit.pid) ended by \(exit.how)\(doing); \(outcome.rawValue)")
        database.record("crashed", plugin: id, version: version, "crash #\(crash.id!): \(exit.how)\(doing); \(outcome.rawValue)")
        if exit.writesCrashReport { collectReport(crash.id!, exit: exit) }
        crash.quarantined = await quarantineIfRepeated(id, crash: crash)
        return crash
    }

    /// Copies macOS's crash report into Gaea's Crashes folder once ReportCrash has written it, and summarises it.
    nonisolated func collectReport(_ id: Int64, exit: WorkerExit) {
        let (reports, database, folder, log) = (crashReports, self.database, paths.crashes, self.log)
        Task.detached {
            guard let found = await reports.wait(process: exit.process, pid: exit.pid, after: exit.at) else {
                try? database.updateCrash(id) { $0.reportNote = "none found: macOS wrote no crash report within 20 s" }
                return
            }
            let copy = folder.appending(path: "\(id)-\(found.lastPathComponent)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: copy)
            let kept = (try? FileManager.default.copyItem(at: found, to: copy)) != nil ? copy : found
            let summary = CrashReports.Report(kept)?.summary
            try? database.updateCrash(id) { $0.reportPath = kept.path; $0.reportSummary = summary; $0.reportNote = nil }
            log("scheduler: crash #\(id)'s report: \(kept.path)")
        }
    }

    /// G-26: a plugin's third crash within ten minutes (since the operator last switched it on) switches it off.
    func quarantineIfRepeated(_ id: String, crash: CrashRecord) async -> Bool {
        guard let crashID = crash.id, let row = (try? database.plugin(id)) ?? nil, row.quarantinedAt == nil else { return false }
        let since = max(crash.at.addingTimeInterval(-Self.quarantineWindow), row.crashesClearedAt ?? .distantPast)
        let recent = (try? database.crashes(plugin: id, since: since, limit: Self.quarantineCrashes)) ?? []
        guard recent.count >= Self.quarantineCrashes else { return false }
        let doing = crash.model.map { " running \($0)" } ?? " while idle"
        let reason = "\(recent.count) crashes in \(Int(Self.quarantineWindow / 60)) minutes, the last \(crash.how)\(doing) (crash #\(crashID))"
        try? database.updateCrash(crashID) { $0.quarantined = true }
        await manager.quarantine(id, reason: reason)
        return true
    }

    /// What a job's client is told when its worker crashed: each crash named, and the quarantine if one followed.
    func crashFailure(_ failure: WorkerFailure, crashes: [CrashRecord?], plugin id: String) -> WorkerFailure {
        let named = crashes.compactMap { $0 }.map { "\($0.how) (crash #\($0.id ?? 0))" }
        guard !named.isEmpty else { return failure }
        var message = crashes.count > 1
            ? "the worker crashed twice running this job, \(named.joined(separator: " then ")); it was requeued once"
            : "the worker crashed during this streamed run, \(named[0]), which is never requeued"
        if let reason = ((try? database.plugin(id)) ?? nil)?.quarantineReason {
            message += ". The plugin is quarantined after \(reason), until the operator switches it on"
        }
        return WorkerFailure(code: "internal", message: message + ". gaea crashes shows them.", workerExited: true, exit: failure.exit)
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
    /// An MES asset is gone (GPP-1 §3.3.2): every running worker of a plugin with an Audio offer drops what it cached from
    /// it. Nothing answers.
    public func assetRemoved(_ asset: String) {
        for slot in slots.values where slot.worker.isRunning && slot.plugin.manifest.offers.contains(where: { $0.profile == "audio" }) {
            slot.worker.send(["type": "asset_removed", "id": .string(UUID().uuidString), "asset": .string(asset)])
        }
    }

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
