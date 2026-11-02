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
        /// Whether Gaea's own team is trusted without asking. `GAEA_UNTRUST_OWN_TEAM=1` treats it as unknown, so a run
        /// can test the trust list with Gaea's own plugins (G-25). It only ever narrows trust.
        public var ownTeamTrusted = ProcessInfo.processInfo.environment["GAEA_UNTRUST_OWN_TEAM"] != "1"
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
        manager = PluginManager(database: database, paths: paths, log: log, ownTeamTrusted: options.ownTeamTrusted)
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
                switch try await manager.add(repository: try arg("repo"), version: args["version"]) {
                case .installed(let plugin):
                    return OperatorResponse(id: request.id, ok: true, text: "Installed \(plugin.title) \(plugin.version) (\(plugin.id)), enabled.",
                                            json: Self.json(["id": plugin.id, "version": plugin.version]))
                case .held(let held):
                    return OperatorResponse(id: request.id, ok: true, text: Self.describe(held), json: Self.json(held))
                }
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
            case .crashesList:
                return try crashList(request.id, plugin: args["plugin"], limit: Int(args["lines"] ?? "") ?? 50)
            case .crashesShow:
                let text = try arg("id")
                guard let number = Int64(text.trimmingCharacters(in: CharacterSet(charactersIn: "#"))),
                      let crash = try database.crash(number) else { throw OperatorError("No crash \(text): gaea crashes lists them.") }
                return OperatorResponse(id: request.id, ok: true, text: Self.describe(crash), json: Self.json(crash))
            case .trustList:
                return trustList(request.id)
            case .trustApprove:
                let text = switch try await manager.approve(try arg("id")) {
                case .added(let plugin): "Trusted its team. Installed \(plugin.title) \(plugin.version) (\(plugin.id)), enabled."
                case let .updated(id, outcome): "Trusted its team. " + Self.describe(outcome, id: id)
                case let .team(team, plugins):
                    "Trusted \(team)." + (plugins.isEmpty ? "" : " Its plugins run again: \(plugins.joined(separator: ", ")).")
                }
                return OperatorResponse(id: request.id, ok: true, text: text)
            case .trustDecline:
                let held = try await manager.decline(try arg("id"))
                return OperatorResponse(id: request.id, ok: true,
                                        text: "Declined \(held.title) \(held.version) from \(held.teamName) (\(held.team)); the download is gone.")
            case .trustRemove:
                let team = try arg("team")
                let stopped = try await manager.revoke(team: team)
                return OperatorResponse(id: request.id, ok: true, text: "No longer trusting \(team.uppercased())."
                    + (stopped.isEmpty ? "" : " Stopped, and kept installed until it's trusted again: \(stopped.joined(separator: ", "))."))
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
            Trust:     \(await trustSummary())
            Crashes:   \(try crashSummary(plugins))
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
        let trusted = await manager.trustedTeams()
        let text = rows.isEmpty ? "No plugins. Add one: gaea plugins add https://github.com/owner/repo" : rows.map { row in
            var line = "\(row.enabled ? "on " : "off") \(row.id) \(row.activeVersion)  \(row.title)  \(row.repo)"
            if let previous = row.previousVersion { line += "\n      rollback: \(previous)" }
            if let pending = row.pendingVersion { line += "\n      switching to \(pending) when idle" }
            if let latest = row.latestVersion { line += "\n      update available: \(latest)" }
            if let failure = row.failure { line += "\n      failed: \(failure)" }
            if !trusted.contains(row.team) { line += "\n      stopped: its team \(row.team) isn't trusted (gaea trust approve \(row.team))" }
            if let reason = row.quarantineReason {
                line += "\n      quarantined \(row.quarantinedAt?.formatted(.iso8601) ?? ""): \(reason) (gaea plugins enable \(row.id) clears it)"
            }
            let recent = (try? database.crashes(plugin: row.id, since: Date().addingTimeInterval(-86_400))) ?? []
            if let last = recent.first {
                line += "\n      crashed \(recent.count == 1 ? "once" : "\(recent.count) times") in 24 h, last \(last.how) at "
                    + "\(last.at.formatted(.iso8601)) (gaea crashes show \(last.id ?? 0))"
            }
            return line
        }.joined(separator: "\n")
        struct Row: Encodable {
            var id: String, version: String, enabled: Bool, previous: String?, pending: String?, latest: String?, failure: String?, repo: String
            var quarantined: String?
        }
        return OperatorResponse(id: id, ok: true, text: text, json: Self.json(rows.map {
            Row(id: $0.id, version: $0.activeVersion, enabled: $0.enabled, previous: $0.previousVersion, pending: $0.pendingVersion,
                latest: $0.latestVersion, failure: $0.failure, repo: $0.repo, quarantined: $0.quarantineReason)
        }))
    }

    /// The last day's crashes, and the plugins quarantined now.
    func crashSummary(_ plugins: [GaeaDatabase.PluginRow]) throws -> String {
        let day = try database.crashes(since: Date().addingTimeInterval(-86_400), limit: 1000).count
        let quarantined = plugins.filter { $0.quarantinedAt != nil }.map(\.id)
        return "\(day == 0 ? "none" : "\(day)") in the last 24 h"
            + (quarantined.isEmpty ? "" : "; quarantined: \(quarantined.joined(separator: ", ")) (gaea plugins)")
    }

    func crashList(_ id: String, plugin: String?, limit: Int) throws -> OperatorResponse {
        let crashes = try database.crashes(plugin: plugin, limit: limit)
        let titles = Dictionary(uniqueKeysWithValues: try database.plugins().map { ($0.id, $0.title) })
        let text = crashes.isEmpty ? "No crashes\(plugin.map { " of \($0)" } ?? "")." : crashes.map { crash in
            var line = "#\(crash.id ?? 0)  \(crash.at.formatted(.iso8601))  \(titles[crash.pluginID] ?? crash.pluginID) \(crash.version)  "
                + "\(crash.how)  \(crash.outcome.rawValue)"
            line += crash.model.map { "\n      running \($0)\(crash.lane.map { " \($0)" } ?? "") for \(crash.job ?? "?")" } ?? "\n      while idle"
            if let fault = crash.fault { line += "; \(fault)" }
            if let first = crash.reportSummary?.split(separator: "\n").first { line += "\n      report: \(first)" }
            else if let note = crash.reportNote { line += "\n      report: \(note)" }
            if crash.quarantined { line += "\n      quarantined \(crash.pluginID)" }
            return line
        }.joined(separator: "\n")
        return OperatorResponse(id: id, ok: true, text: text, json: Self.json(crashes))
    }

    /// One crash in full: what ran, how it ended, stderr's last lines and macOS's report.
    static func describe(_ crash: CrashRecord) -> String {
        let job = switch crash.outcome {
        case .requeued: "requeued once"
        case .failed: "failed"
        case .idle: "none"
        }
        var lines = [
            "Crash #\(crash.id ?? 0) at \(crash.at.formatted(.iso8601))",
            "  Plugin:   \(crash.pluginID) \(crash.version), pid \(crash.pid)",
            "  Running:  " + (crash.model.map { "\($0)\(crash.lane.map { " lane \($0)" } ?? "") for job \(crash.job ?? "?")" } ?? "nothing (idle)"),
            "  Ended by: \(crash.how)\(crash.fault.map { " (\($0))" } ?? "")",
            "  The job:  \(job)",
        ]
        if crash.quarantined { lines.append("  This crash quarantined the plugin (G-26).") }
        lines.append("  Report:   " + (crash.reportPath ?? crash.reportNote ?? "none"))
        if let summary = crash.reportSummary {
            lines += summary.split(separator: "\n").map { "    \($0)" }
        }
        lines.append("  stderr's last lines:")
        lines += crash.stderrTail.isEmpty ? ["    (nothing)"] : crash.stderrTail.map { "    \($0)" }
        return lines.joined(separator: "\n")
    }

    static func describe(_ outcome: PluginManager.SwitchOutcome, id: String) -> String {
        switch outcome {
        case .switched(let version): "\(id) now runs \(version)."
        case .pending(let version): "\(id) \(version) is installed; Gaea switches to it when the plugin is idle."
        case .held(let held): describe(held)
        }
    }

    /// What the operator needs to answer a held release (UI-3): who signed it, notarization, the repo and the models.
    static func describe(_ held: HeldRelease) -> String {
        """
        Held \(held.id): \(held.title) \(held.version) (\(held.pluginID)) is signed by a team Gaea doesn't trust yet.
          Signed by:  \(held.signingIdentity ?? held.team)
          Team:       \(held.team)
          Notarized:  \(held.notarized ? "yes" : "no, Apple hasn't notarized this build")
          Repo:       \(held.repo) (\(held.tag))
          Models:     \(held.models.joined(separator: ", ").ifEmpty("none"))
        Trusting the team lets Gaea run any plugin it signs, including later updates.
          Approve: gaea trust approve \(held.id)
          Decline: gaea trust decline \(held.id)
        """
    }

    func trustSummary() async -> String {
        let teams = await manager.trustedTeams().sorted()
        let held = await manager.held().count
        return (teams.isEmpty ? "no team" : teams.joined(separator: ", ")) + (held > 0 ? "; \(held) held: gaea trust" : "")
    }

    func trustList(_ id: String) -> OperatorResponse {
        let builtIn = manager.builtInTeams
        let approved = (try? database.trustedTeams()) ?? []
        let plugins = (try? database.plugins()) ?? []
        let held = (try? database.held()) ?? []
        func using(_ team: String) -> String {
            let ids = plugins.filter { $0.team == team }.map(\.id)
            return ids.isEmpty ? "" : "  plugins: \(ids.joined(separator: ", "))"
        }
        var lines = ["Trusted teams:"]
        for team in builtIn.sorted() { lines.append("  \(team)  Gaea's own team (built in)" + using(team)) }
        for t in approved where !builtIn.contains(t.team) {
            lines.append("  \(t.team)  \(t.name), approved \(t.addedAt.formatted(.iso8601))" + using(t.team))
        }
        if builtIn.isEmpty { lines.append("  (Gaea's own team is treated as unknown for this run: GAEA_UNTRUST_OWN_TEAM)") }
        let trusted = builtIn.union(approved.map(\.team))
        let untrusted = Dictionary(grouping: plugins.filter { !trusted.contains($0.team) }, by: \.team)
        if !untrusted.isEmpty {
            lines.append("Not trusted, installed and stopped:")
            for (team, rows) in untrusted.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(team)  plugins: \(rows.map(\.id).joined(separator: ", "))  (gaea trust approve \(team))")
            }
        }
        lines.append(held.isEmpty ? "Held: none" : "Held:")
        for h in held { lines.append(Self.describe(h).split(separator: "\n").map { "  " + $0 }.joined(separator: "\n")) }
        struct List: Encodable {
            struct Team: Encodable { var team: String, name: String, builtIn: Bool, addedAt: Date? }
            var trusted: [Team], held: [HeldRelease], untrustedPlugins: [String]
        }
        let list = List(trusted: builtIn.sorted().map { .init(team: $0, name: "Gaea's own team", builtIn: true, addedAt: nil) }
                            + approved.filter { !builtIn.contains($0.team) }.map { .init(team: $0.team, name: $0.name, builtIn: false, addedAt: $0.addedAt) },
                        held: held, untrustedPlugins: untrusted.values.flatMap { $0.map(\.id) }.sorted())
        return OperatorResponse(id: id, ok: true, text: lines.joined(separator: "\n"), json: Self.json(list))
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
