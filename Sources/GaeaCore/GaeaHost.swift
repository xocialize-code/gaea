import Foundation
import GaeaOperator
import GaeaProtocol
import MESCore
import MESEngineCore
import MESEngineKit
import Synchronization

/// Gaea, assembled: gaea.sqlite, the plugin manager, the scheduler, the MES server and the operator API. The app and
/// `--headless` both run one of these.
public final class GaeaHost: Sendable {
    public struct Options: Sendable {
        /// MES's port; 0 picks a free one.
        public var port = 17630
        /// Paired mode (TLS, pairing) for the LAN; open mode serves this Mac only (SRV-7).
        public var paired = false
        public var bindHost: String?
        public var advertise = true
        public var budgetBytes: UInt64?
        /// The shared weights folder for this launch, over the operator's setting (`--models-root`).
        public var modelsRoot: URL?
        public var operatorPolicy: OperatorServer.Policy?
        public var echoLog = true
        /// Pairing approvals; the default declines (the app asks its operator).
        public var pairingApproval: @Sendable (PairingPrompt) async -> Bool = { _ in false }
        public var idleTimeout: Duration = .seconds(900)
        /// How long held outputs stay (Base §13); the MES default is an hour.
        public var outputsTTLSeconds: Int?
        public init() {}
    }

    public let paths: GaeaPaths
    public let options: Options
    public let database: GaeaDatabase
    public let log: HostLog
    public let manager: PluginManager
    public let scheduler: Scheduler
    public let enablement: ModelEnablement
    public let engine: GaeaEngine
    public let server: MESEngineServer
    public let operatorServer: OperatorServer
    private let port = Mutex<Int?>(nil)

    public init(paths: GaeaPaths = GaeaPaths(), options: Options = Options()) throws {
        self.paths = paths
        self.options = options
        try paths.create()
        log = HostLog(file: paths.hostLog, echo: options.echoLog)
        database = try GaeaDatabase(path: paths.database)
        manager = PluginManager(database: database, paths: paths, log: log)
        scheduler = Scheduler(manager: manager, database: database, paths: paths, log: log, budgetBytes: options.budgetBytes,
                              modelsRoot: options.modelsRoot, idleTimeout: options.idleTimeout)
        enablement = try ModelEnablement(store: DatabaseEnablementStore(database))
        engine = GaeaEngine(manager: manager, scheduler: scheduler, enablement: enablement)

        var config = EngineConfiguration(id: "eng_gaea_\(Host.current().localizedName.map(Self.slug) ?? "mac")", name: "Gaea",
                                         implementationName: "gaea", implementationVersion: Gaea.version,
                                         implementationURL: "https://github.com/xocialize-code/gaea", spoolDirectory: paths.spool)
        config.stateDirectory = paths.serverState
        config.port = options.port
        config.advertise = options.advertise
        config.handlesShutdownSignals = false
        if let ttl = options.outputsTTLSeconds { config.outputsTTLSeconds = ttl }
        if options.paired {
            config.mode = .paired
            config.host = options.bindHost ?? "0.0.0.0"
            config.pairingApproval = options.pairingApproval
        } else if let host = options.bindHost {
            config.host = host
        }
        server = MESEngineServer(engine: engine, configuration: config)

        let box = HandlerBox()
        operatorServer = OperatorServer(socket: paths.socket, log: log, policy: options.operatorPolicy) { request, peer in
            await box.host?.handle(request, peer: peer) ?? .failure(request.id, "Gaea is starting.")
        }
        box.host = self
        let server = self.server
        Task { await manager.attach(workers: scheduler) { await server.reloadDescriptors() } }
    }

    final class HandlerBox: @unchecked Sendable { weak var host: GaeaHost? }

    static func slug(_ name: String) -> String {
        String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }.prefix(24))
    }

    /// Where MES clients reach Gaea, once it serves.
    public var endpoint: String? {
        port.withLock { $0 }.map { "\(options.paired ? "https" : "http")://\(server.configuration.host):\($0)\(server.configuration.basePath)" }
    }

    /// Starts the operator API and background chores, then serves MES until the task is cancelled.
    public func run(onRunning: @escaping @Sendable (Int) async -> Void = { _ in }) async throws {
        await manager.attach(workers: scheduler) { [server] in await server.reloadDescriptors() }
        try operatorServer.start()
        defer { operatorServer.stop() }
        log("gaea \(Gaea.version) starting: \(paths.root.path), budget \(scheduler.budgetBytes.gb), models \(await scheduler.modelsRoot.path)")
        let chores = Task { [manager, scheduler] in
            await manager.checkForUpdates()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await scheduler.sweepIdle()
            }
        }
        defer { chores.cancel() }
        do {
            try await server.run { [self] port in
                self.port.withLock { $0 = port }
                log("gaea: serving MES at \(endpoint ?? "?")")
                await onRunning(port)
            }
        } catch {
            await scheduler.stopAll()
            throw error
        }
        await scheduler.stopAll()
    }

    // MARK: - Operator commands

    func handle(_ request: OperatorRequest, peer: OperatorPeer) async -> OperatorResponse {
        let args = request.args
        func arg(_ name: String) throws -> String {
            guard let value = args[name], !value.isEmpty else { throw OperatorError("missing \(name)") }
            return value
        }
        do {
            switch OperatorAPI.Command(rawValue: request.command) {
            case .status:
                return try await status(request.id, peer: peer)
            case .logs:
                let lines = Int(args["lines"] ?? "") ?? 80
                return OperatorResponse(id: request.id, ok: true, text: HostLog.tail(paths.hostLog, lines: lines))
            case .pluginsList:
                return try await pluginList(request.id)
            case .pluginsAdd:
                let plugin = try await manager.add(repository: try arg("repo"), version: args["version"])
                return OperatorResponse(id: request.id, ok: true, text: "Installed \(plugin.title) \(plugin.version) (\(plugin.id)), enabled.",
                                        json: Self.json(["id": plugin.id, "version": plugin.version]))
            case .pluginsCheck:
                await manager.checkForUpdates()
                return try await pluginList(request.id)
            case .pluginsUpdate:
                let outcome = try await manager.update(plugin: try arg("id"), to: args["version"])
                return OperatorResponse(id: request.id, ok: true, text: Self.describe(outcome, id: try arg("id")))
            case .pluginsRollback:
                let outcome = try await manager.rollBack(plugin: try arg("id"))
                return OperatorResponse(id: request.id, ok: true, text: Self.describe(outcome, id: try arg("id")))
            case .pluginsEnable, .pluginsDisable:
                let on = request.command == OperatorAPI.Command.pluginsEnable.rawValue
                try await manager.setEnabled(on, plugin: try arg("id"))
                return OperatorResponse(id: request.id, ok: true, text: "\(try arg("id")) \(on ? "enabled" : "disabled").")
            case .pluginsRemove:
                try await manager.remove(plugin: try arg("id"))
                return OperatorResponse(id: request.id, ok: true, text: "Removed \(try arg("id")).")
            case .pluginsLogs:
                let id = try arg("id")
                let lines = Int(args["lines"] ?? "") ?? 80
                let events = try database.events(plugin: id, limit: 50).map {
                    "\($0.at.formatted(.iso8601)) \($0.kind)\($0.version.map { " \($0)" } ?? ""): \($0.message)"
                }
                let text = "== events ==\n" + events.joined(separator: "\n") + "\n== worker stderr (\(paths.pluginLog(id).path)) ==\n"
                    + HostLog.tail(paths.pluginLog(id), lines: lines)
                return OperatorResponse(id: request.id, ok: true, text: text)
            case .modelsList:
                let catalog = await engine.catalog()
                let lines = catalog.map { c in
                    let optIn = c.offer.namedOnly == true
                    let on = c.plugin.enabled && enablement.isEnabled(c.model.id, optIn: optIn)
                    let chosen = defaultLane(c.model, plugin: c.plugin.id)
                    return "\(on ? "on " : "off") \(c.model.id)  \(c.model.title)  [\(c.plugin.id) \(c.plugin.version)] lanes: "
                        + c.model.lanes.map { "\($0.id)\($0.id == chosen ? "*" : "") \(LaneChoice.need($0).gb)" }.joined(separator: ", ")
                }
                return OperatorResponse(id: request.id, ok: true, text: lines.isEmpty ? "No models: add a plugin." : lines.joined(separator: "\n"))
            case .modelsEnable, .modelsDisable:
                let id = try arg("id")
                guard let model = await engine.catalog().first(where: { $0.model.id == id }) else { throw OperatorError("no model \(id)") }
                let on = request.command == OperatorAPI.Command.modelsEnable.rawValue
                try enablement.set(id, enabled: on, optIn: model.offer.namedOnly == true)
                await server.reloadDescriptors()
                return OperatorResponse(id: request.id, ok: true, text: "\(id) \(on ? "enabled" : "disabled").")
            case .modelsRoot:
                if let path = args["path"], !path.isEmpty {
                    let url = path == "default" ? nil : URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
                    try await scheduler.setModelsRoot(url)
                }
                let root = await scheduler.modelsRoot.path
                let stored = (try? database.setting(Scheduler.modelsRootSetting)) ?? nil
                let source = options.modelsRoot != nil ? "--models-root, for this launch" : stored != nil ? "set by the operator" : "MLXEngine's store, the default"
                return OperatorResponse(id: request.id, ok: true, text: "\(root) (\(source))",
                                        json: Self.json(["models_root": root, "stored": stored ?? ""]))
            case .modelsLane:
                let id = try arg("id")
                guard let c = await engine.catalog().first(where: { $0.model.id == id }) else { throw OperatorError("no model \(id)") }
                let key = Scheduler.laneSetting(plugin: c.plugin.id, model: id)
                if let lane = args["lane"], !lane.isEmpty {
                    guard lane == "default" || c.model.lanes.contains(where: { $0.id == lane }) else {
                        throw OperatorError("\(id) has no lane \(lane): \(c.model.lanes.map(\.id).joined(separator: ", "))")
                    }
                    try database.setSetting(key, lane == "default" ? nil : lane)
                    log("operator: \(id)'s default lane is now \(lane == "default" ? "the manifest's" : lane)")
                }
                let stored = (try? database.setting(key)) ?? nil
                let lane = defaultLane(c.model, plugin: c.plugin.id) ?? ""
                return OperatorResponse(id: request.id, ok: true,
                                        text: "\(id): \(lane) (\(stored != nil ? "set by the operator" : "the manifest's default"))",
                                        json: Self.json(["model": id, "lane": lane, "stored": stored ?? ""]))
            case .ledger:
                let ledger = await scheduler.ledger()
                return OperatorResponse(id: request.id, ok: true, text: Self.describe(ledger), json: Self.json(ledger))
            case nil:
                throw OperatorError("unknown command \(request.command)")
            }
        } catch {
            log("operator: \(request.command) failed: \(error)")
            return .failure(request.id, "\(error)")
        }
    }

    struct OperatorError: Error, CustomStringConvertible {
        let description: String
        init(_ text: String) { description = text }
    }

    func status(_ id: String, peer: OperatorPeer) async throws -> OperatorResponse {
        let plugins = try database.plugins()
        let ledger = await scheduler.ledger()
        let descriptors = await server.operations() ?? []
        let text = """
            Gaea \(Gaea.version)
            MES:       \(endpoint ?? "starting") (\(options.paired ? "paired" : "open, this Mac only"))
            Operations: \(descriptors.map { "\($0.operation) [\($0.models.map(\.id).joined(separator: ", "))]" }.joined(separator: "; "))
            Plugins:   \(plugins.count) installed, \(plugins.filter(\.enabled).count) enabled
            Workers:   \(ledger.workers.map { "\($0.pluginID) pid \($0.pid)\($0.busy ? " (busy)" : "")" }.joined(separator: ", ").ifEmpty("none"))
            Memory:    \(ledger.chargedBytes.gb) charged of \(ledger.budgetBytes.gb) budget; host \(ledger.hostFootprintBytes.gb)
            Models:    \(await scheduler.modelsRoot.path)
            Operator:  \(paths.socket.path) (\(operatorServer.policy.rawValue)); you are \(peer)
            Database:  \(paths.database.path)
            """
        struct Status: Encodable {
            var version: String, endpoint: String?, paired: Bool, plugins: Int, enabled: Int, operations: [String], ledger: Ledger
            var operatorPolicy: String
        }
        return OperatorResponse(id: id, ok: true, text: text, json: Self.json(Status(
            version: Gaea.version, endpoint: endpoint, paired: options.paired, plugins: plugins.count,
            enabled: plugins.filter(\.enabled).count, operations: descriptors.map(\.operation), ledger: ledger,
            operatorPolicy: operatorServer.policy.rawValue)))
    }

    /// The lane a model loads when it fits: the operator's choice, else the manifest's default.
    func defaultLane(_ model: PluginManifest.Model, plugin: String) -> String? {
        let stored = (try? database.setting(Scheduler.laneSetting(plugin: plugin, model: model.id))) ?? nil
        return stored.flatMap { s in model.lanes.first { $0.id == s }?.id } ?? model.lanes.first(where: \.default)?.id ?? model.lanes.first?.id
    }

    func pluginList(_ id: String) async throws -> OperatorResponse {
        let rows = try database.plugins()
        let text = rows.isEmpty ? "No plugins. Add one: gaea plugins add https://github.com/owner/repo" : rows.map { row in
            var line = "\(row.enabled ? "on " : "off") \(row.id) \(row.activeVersion)  \(row.title)  \(row.repo)"
            if let previous = row.previousVersion { line += "\n      rollback: \(previous)" }
            if let pending = row.pendingVersion { line += "\n      switching to \(pending) when idle" }
            if let latest = row.latestVersion { line += "\n      update available: \(latest)" }
            if let failure = row.failure { line += "\n      failed: \(failure)" }
            return line
        }.joined(separator: "\n")
        struct Row: Encodable {
            var id: String, version: String, enabled: Bool, previous: String?, pending: String?, latest: String?, failure: String?, repo: String
        }
        return OperatorResponse(id: id, ok: true, text: text, json: Self.json(rows.map {
            Row(id: $0.id, version: $0.activeVersion, enabled: $0.enabled, previous: $0.previousVersion, pending: $0.pendingVersion,
                latest: $0.latestVersion, failure: $0.failure, repo: $0.repo)
        }))
    }

    static func describe(_ outcome: PluginManager.SwitchOutcome, id: String) -> String {
        switch outcome {
        case .switched(let version): "\(id) now runs \(version)."
        case .pending(let version): "\(id) \(version) is installed; Gaea switches to it when the plugin is idle."
        }
    }

    static func describe(_ ledger: Ledger) -> String {
        var lines = ["budget \(ledger.budgetBytes.gb), charged \(ledger.chargedBytes.gb), free \(ledger.availableBytes.gb); "
            + "host \(ledger.hostFootprintBytes.gb); \(ledger.queued) queued"]
        for w in ledger.workers {
            lines.append("  \(w.pluginID) \(w.version) pid \(w.pid)\(w.busy ? " busy" : ""): declared \(w.declaredBytes.gb), "
                + "phys_footprint \(w.physFootprintBytes?.gb ?? "?"), worker says \(w.reportedFootprintBytes?.gb ?? "?"), "
                + "charged \(w.chargedBytes.gb)\(w.overrun ? " — OVER its declaration" : "") lanes \(w.lanes)")
        }
        return lines.joined(separator: "\n")
    }

    static func json(_ value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
