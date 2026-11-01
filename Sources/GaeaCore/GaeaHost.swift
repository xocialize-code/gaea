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
        /// How long an update waits after a job finishes, so its client can fetch the outputs (G-24).
        public var updateGrace: TimeInterval = 60
        /// The app bundle an update replaces; nil when this process can't update itself (tests).
        public var appBundle: URL? = Bundle.main.bundleURL
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
    public let updater: GaeaUpdater
    private let port = Mutex<Int?>(nil)
    private let latestActivity = Mutex<EngineActivity?>(nil)
    private let relaunching = Mutex<(target: URL?, stop: (@Sendable () -> Void)?)>((nil, nil))

    public init(paths: GaeaPaths = GaeaPaths(), options: Options = Options()) throws {
        self.paths = paths
        self.options = options
        let installed = FileManager.default.fileExists(atPath: paths.database.path)
        try paths.create()
        log = HostLog(file: paths.hostLog, echo: options.echoLog)
        database = try GaeaDatabase(path: paths.database)
        manager = PluginManager(database: database, paths: paths, log: log)
        scheduler = Scheduler(manager: manager, database: database, paths: paths, log: log, budgetBytes: options.budgetBytes,
                              modelsRoot: options.modelsRoot, idleTimeout: options.idleTimeout)
        enablement = try ModelEnablement(store: DatabaseEnablementStore(database))
        engine = GaeaEngine(manager: manager, scheduler: scheduler, enablement: enablement)
        updater = GaeaUpdater(database: database, paths: paths, log: log, appBundle: options.appBundle, grace: options.updateGrace)

        var config = EngineConfiguration(id: Self.engineID(database, installed: installed), name: "Gaea",
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

    /// The setting that keeps this server's MES engine id.
    static let engineIDSetting = "engine.id"

    /// This server's MES engine id, kept in gaea.sqlite: clients key pairings and routing by it (Base §4), so two servers
    /// on one Mac (G-19) must not share one. A new install takes the Mac's name and a random suffix; one that existed
    /// before ids were kept keeps `eng_gaea_<mac>`, the id its clients paired with.
    static func engineID(_ database: GaeaDatabase, installed: Bool) -> String {
        if let stored = (try? database.setting(engineIDSetting)) ?? nil { return stored }
        let mac = "eng_gaea_\(Host.current().localizedName.map(Self.slug) ?? "mac")"
        let suffix = String((0..<6).map { _ in "abcdefghijkmnpqrstuvwxyz23456789".randomElement()! })
        let id = installed ? mac : "\(mac)_\(suffix)"
        try? database.setSetting(engineIDSetting, id)
        return id
    }

    static func slug(_ name: String) -> String {
        String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }.prefix(24))
    }

    /// The port MES is served on, once it serves.
    public var servedPort: Int? { port.withLock { $0 } }

    /// The app an update put in place, once Gaea has stopped serving to relaunch it. The launcher starts it.
    public var relaunchTarget: URL? { relaunching.withLock { $0.target } }

    /// How the launcher stops serving when an update is in place: it cancels the task running `run`, then starts
    /// `relaunchTarget`.
    public func onRelaunch(_ stop: @escaping @Sendable () -> Void) {
        relaunching.withLock { $0.stop = stop }
    }

    /// Where MES clients reach Gaea, once it serves.
    public var endpoint: String? {
        port.withLock { $0 }.map { "\(options.paired ? "https" : "http")://\(server.configuration.host):\($0)\(server.configuration.basePath)" }
    }

    /// Starts the operator API and background chores, then serves MES until the task is cancelled.
    public func run(onRunning: @escaping @Sendable (Int) async -> Void = { _ in }) async throws {
        await manager.attach(workers: scheduler) { [server] in await server.reloadDescriptors() }
        await updater.attach(
            plugins: { [manager] in await manager.installed() },
            activity: { [self] in latestActivity.withLock { $0 } },
            relaunch: { [self] app in
                let stop = relaunching.withLock { state -> (@Sendable () -> Void)? in
                    state.target = app
                    return state.stop
                }
                if let stop { stop() } else { log("update: \(app.path) is in place; restart Gaea to run it") }
            })
        try operatorServer.start()
        defer { operatorServer.stop() }
        log("gaea \(Gaea.version) starting: \(paths.root.path), budget \(scheduler.budgetBytes.gb), models \(await scheduler.modelsRoot.path)")
        let chores = Task { [manager, scheduler, updater] in
            await manager.checkForUpdates()
            while !Task.isCancelled {
                await updater.checkIfDue()
                try? await Task.sleep(for: .seconds(30))
                await scheduler.sweepIdle()
            }
        }
        defer { chores.cancel() }
        // The jobs every client has, which an update waits on.
        let watching = Task { [self] in
            for await activity in server.activity() { latestActivity.withLock { $0 = activity } }
        }
        defer { watching.cancel() }
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
                    let optIn = c.offer.isOptIn
                    let on = c.plugin.enabled && enablement.isEnabled(c.model.id, optIn: optIn)
                    let chosen = defaultLane(c.model, plugin: c.plugin.id)
                    let fits = PluginOffers.fits(c.model, budget: scheduler.budgetBytes)
                    return "\(on ? "on " : "off") \(c.model.id)  \(c.model.title)  [\(c.plugin.id) \(c.plugin.version)] lanes: "
                        + c.model.lanes.map { "\($0.id)\($0.id == chosen ? "*" : "") \(LaneChoice.need($0).gb)" }.joined(separator: ", ")
                        + (fits ? "" : "  (not offered: no lane fits the \(scheduler.budgetBytes.gb) budget)")
                }
                return OperatorResponse(id: request.id, ok: true, text: lines.isEmpty ? "No models: add a plugin." : lines.joined(separator: "\n"))
            case .modelsEnable, .modelsDisable:
                let id = try arg("id")
                guard let model = await engine.catalog().first(where: { $0.model.id == id }) else { throw OperatorError("no model \(id)") }
                let on = request.command == OperatorAPI.Command.modelsEnable.rawValue
                try enablement.set(id, enabled: on, optIn: model.offer.isOptIn)
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
            case .adaptersList:
                let listings = await engine.adapterListings()
                let lines = listings.map { a in
                    "\(a.enabled ? "on " : "off") \(a.id)  \(a.title)  [\(a.model)\(a.operations.isEmpty ? "" : ": " + a.operations.joined(separator: ", "))] "
                        + "\(a.format), \(a.license)\(a.optIn ? ", opt-in" : "")\(a.registered ? ", added" : "")"
                        + (a.trigger.map { ", trigger \"\($0)\"" } ?? "")
                }
                return OperatorResponse(id: request.id, ok: true,
                                        text: lines.isEmpty ? "No adapters: no plugin ships one, and none was added." : lines.joined(separator: "\n"),
                                        json: Self.json(listings))
            case .adaptersAdd:
                let row = try await engine.registerAdapter(.init(
                    url: try arg("url"), model: try arg("model"), file: args["file"], id: args["id"], title: args["title"],
                    trigger: args["trigger"], format: args["format"], strength: args["strength"].flatMap(Double.init),
                    notes: args["notes"]))
                await server.reloadDescriptors()
                let optIn = await engine.adapterListings().first { $0.id == row.id }?.optIn ?? true
                log("operator: added adapter \(row.id) (\(row.repo)@\(row.revision.prefix(12)) \(row.file)) for \(row.modelID)")
                return OperatorResponse(
                    id: request.id, ok: true,
                    text: "Added \(row.id) for \(row.modelID): \(row.repo)@\(row.revision.prefix(12)) \(row.file), \(row.format), \(row.license)."
                        + (optIn ? " Its terms are \(row.commercialUse == "unknown" ? "unknown" : row.commercialUse)\(row.licenseGated ? " and gated" : ""), so it's off until you enable it: gaea adapters enable \(row.id)" : " On."),
                    json: Self.json(row))
            case .adaptersRemove:
                try engine.removeAdapter(try arg("id"))
                await server.reloadDescriptors()
                return OperatorResponse(id: request.id, ok: true, text: "Removed \(try arg("id")). Its weights stay in the models root.")
            case .adaptersEnable, .adaptersDisable:
                let on = request.command == OperatorAPI.Command.adaptersEnable.rawValue
                try await engine.setAdapter(try arg("id"), enabled: on)
                await server.reloadDescriptors()
                return OperatorResponse(id: request.id, ok: true, text: "\(try arg("id")) \(on ? "enabled" : "disabled").")
            case .updateCheck:
                await updater.check()
                return try await updateStatus(request.id)
            case .updateInstall:
                let text = try await updater.install(version: args["version"])
                return OperatorResponse(id: request.id, ok: true, text: text)
            case .updateRollback:
                return OperatorResponse(id: request.id, ok: true, text: try await updater.rollBack())
            case .updateCancel:
                return OperatorResponse(id: request.id, ok: true, text: await updater.cancel())
            case .updatePrereleases:
                if let value = args["value"], !value.isEmpty {
                    guard ["on", "off"].contains(value) else { throw OperatorError("pre-releases: on or off") }
                    try await updater.setPrereleases(value == "on")
                    await updater.check()
                }
                return try await updateStatus(request.id)
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
            Update:    \(Self.describe(await updater.status()))
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

    func updateStatus(_ id: String) async throws -> OperatorResponse {
        let status = await updater.status()
        var lines = ["Gaea \(status.current): \(Self.describe(status))"]
        if let app = status.app { lines.append("App:       \(app)") }
        if let why = status.cannotUpdate { lines.append("Can't update itself: \(why)") }
        if let kept = status.kept { lines.append("Kept:      \(kept), for gaea update --rollback") }
        lines.append("Releases:  \(Gaea.releases.url.absoluteString)/releases, pre-releases \(status.prereleases ? "included" : "skipped")"
            + (status.lastChecked.map { ", checked \($0.formatted(.iso8601))" } ?? ""))
        if let failure = status.lastFailure { lines.append("Last failure: \(failure)") }
        return OperatorResponse(id: id, ok: true, text: lines.joined(separator: "\n"), json: Self.json(status))
    }

    public static func describe(_ status: GaeaUpdater.Status) -> String {
        if let staged = status.staged {
            return "\(status.rollingBack ? "rolling back to" : "installing") \(staged)"
                + (status.waitingFor.map { " once quiet (\($0))" } ?? ", relaunching")
        }
        if let latest = status.latest {
            return "\(latest)\(status.latestPrerelease == true ? " (pre-release)" : "") is available: gaea update"
        }
        if let error = status.checkError { return "couldn't check (\(error))" }
        return status.lastChecked == nil ? "not checked yet" : "up to date"
    }

    static func describe(_ ledger: Ledger) -> String {
        var lines = ["budget \(ledger.budgetBytes.gb), charged \(ledger.chargedBytes.gb), free \(ledger.availableBytes.gb); "
            + "host \(ledger.hostFootprintBytes.gb); \(ledger.queued) queued"]
        for w in ledger.workers {
            lines.append("  \(w.pluginID) \(w.version) pid \(w.pid)\(w.busy ? " busy" : ""): declared \(w.declaredBytes.gb), "
                + "phys_footprint \(w.physFootprintBytes?.gb ?? "?") (peak \(w.peakFootprintBytes?.gb ?? "?")), worker says \(w.reportedFootprintBytes?.gb ?? "?"), "
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
