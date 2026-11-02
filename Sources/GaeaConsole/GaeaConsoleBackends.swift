import Foundation
import GaeaCore
import GaeaProtocol
import MESCore
import MESEngineCore
import MESEngineKit
import MESEngineUI

/// The console's Queue and Models pages over Gaea (UI-2): the server's activity, and every plugin model with its
/// plugin, version and update.
public struct GaeaConsoleBackend: EngineConsoleBackend {
    let host: GaeaHost

    public init(host: GaeaHost) { self.host = host }

    public func activity() -> AsyncStream<EngineActivity> { host.server.activity() }
    public func cancel(job id: String) async throws { _ = try await host.server.cancel(job: id) }
    public func operations() async -> [Descriptor] { await host.server.operations() ?? [] }

    public func models() async -> [EngineModel] {
        let catalog = await host.engine.catalog()
        let routes = await host.engine.routes()
        let live = await operations()
        let resident = Set(await host.scheduler.residentModels())
        let rows = Dictionary(uniqueKeysWithValues: ((try? host.database.plugins()) ?? []).map { ($0.id, $0) })
        func isDefault(_ model: String, for operation: String) -> Bool {
            live.first { $0.operation == operation }?.models.contains { $0.id == model && $0.isDefault == true } ?? false
        }
        return catalog.map { entry in
            let optIn = entry.offer.isOptIn
            let lane = entry.model.lanes.first(where: \.default)
            let row = rows[entry.plugin.id]
            let bundled = lane.map { $0.resolved.materialization == .bundled || $0.resolved.weightSources.isEmpty } ?? true
            // The operations the normalizer offers the model for, as clients see them; a model that is off shows its
            // plugin's own offers.
            let own = routes.filter { $0.plugin.id == entry.plugin.id && $0.model.id == entry.model.id }
            let offer = own.first?.offer ?? entry.offer
            let offered: [EngineModel.Role] = live.compactMap { descriptor in
                descriptor.models.first { $0.id == entry.model.id }.map {
                    .init(operation: descriptor.operation, qualityTiers: $0.qualityTiers, isDefault: $0.isDefault == true,
                          namedOnly: $0.namedOnly == true)
                }
            }
            let roles = offered.isEmpty
                ? own.map { .init(operation: $0.operation, qualityTiers: $0.offer.qualityTiers,
                                  isDefault: isDefault(entry.model.id, for: $0.operation), namedOnly: $0.offer.namedOnly == true) }
                : offered
            return EngineModel(
                id: entry.model.id, title: entry.model.title, summary: entry.plugin.manifest.summary ?? "", license: offer.license,
                optIn: optIn, enabled: entry.plugin.enabled && host.enablement.isEnabled(entry.model.id, optIn: optIn),
                acceptedAt: host.enablement.acceptedAt(entry.model.id),
                roles: roles,
                notes: offer.notes, memoryClass: offer.memoryClass, speedClass: offer.speedClass,
                footprintBytes: lane.map { $0.resolved.persistentBytes + $0.resolved.peakTransientBytes },
                install: bundled ? .builtIn : .notDownloaded(bytes: nil), resident: resident.contains(entry.model.id),
                source: entry.model.sourceRepo, sourceURL: URL(string: entry.plugin.repo),
                tags: entry.model.lanes.map { $0.id + ($0.default ? " (default)" : "") },
                plugin: EngineModel.Plugin(id: entry.plugin.id, title: entry.plugin.title), version: entry.plugin.version,
                update: row?.latestVersion.map { EngineUpdate(version: $0, notes: row?.latestNotes, publishedAt: row?.latestPublishedAt,
                                                              url: row?.latestURL.flatMap(URL.init(string:))) })
        }
    }

    public func setEnabled(_ enabled: Bool, model id: String) async throws {
        guard let entry = await host.engine.catalog().first(where: { $0.model.id == id }) else {
            throw MESError(.notFound, "No model \(id).")
        }
        try host.enablement.set(id, enabled: enabled, optIn: entry.offer.isOptIn)
        await host.server.reloadDescriptors()
    }

    public func unload(model id: String) async { await host.scheduler.unload(model: id) }
}

/// The Plugins page (UI-3) over Gaea's plugin manager and its trust list (AB-T-0411): a release signed by a team that
/// isn't trusted comes back as a trust question, and the operator's answer approves the team or drops the download. A
/// quarantined plugin (G-26, AB-T-0417) shows why, and switching it on clears it.
public struct GaeaPluginBackend: EnginePluginBackend {
    let host: GaeaHost

    public init(host: GaeaHost) { self.host = host }

    /// Each team as its certificate names it: the operator's approved name, else the holder on a signature recorded at
    /// install, else the team id.
    func teams() async -> [String: EngineTeam] {
        var names: [String: String] = [:]
        for row in (try? host.database.plugins()) ?? [] where names[row.team] == nil {
            let signature = try? host.database.version(row.id, row.activeVersion)?.signature
            names[row.team] = signature.flatMap { PluginVerifier.Signature.holder($0.components(separatedBy: ", id ").first ?? "") }
        }
        for team in (try? host.database.trustedTeams()) ?? [] { names[team.team] = team.name }
        var teams = Dictionary(uniqueKeysWithValues: names.map { ($0.key, EngineTeam(id: $0.key, name: $0.value)) })
        if teams[GPP.trustedTeam] == nil { teams[GPP.trustedTeam] = EngineTeam(id: GPP.trustedTeam, name: "Gaea's own team") }
        return teams
    }

    public func plugins() async -> [EnginePlugin] {
        let installed = Dictionary(uniqueKeysWithValues: await host.manager.installed().map { ($0.id, $0) })
        let teams = await self.teams()
        let trusted = await host.manager.trustedTeams()
        return ((try? host.database.plugins()) ?? []).map { row in
            let team = teams[row.team] ?? EngineTeam(id: row.team, name: row.team)
            let state: EnginePlugin.State = if !trusted.contains(row.team) {
                .failed("Signed by \(team.name) (\(row.team)), a team this server doesn't trust. It runs again when you trust the team.")
            } else if let reason = row.quarantineReason {
                // G-26, until MESEngineUI has a quarantined state of its own (AB-A-0247): the On toggle clears it.
                .failed("Quarantined after \(reason). Turn it on to clear the quarantine; gaea crashes shows each crash.")
            } else if let failure = row.failure {
                .failed(failure)
            } else if let pending = row.pendingVersion {
                .pendingSwitch(version: pending)
            } else {
                .ready
            }
            return EnginePlugin(
                id: row.id, title: row.title, summary: row.summary, repository: URL(string: row.repo) ?? URL(string: "https://github.com")!,
                version: row.activeVersion, rollbackVersion: row.previousVersion,
                update: row.latestVersion.map { EngineUpdate(version: $0, notes: row.latestNotes, publishedAt: row.latestPublishedAt,
                                                             url: row.latestURL.flatMap(URL.init(string:))) },
                team: team, enabled: row.enabled, state: state, models: installed[row.id]?.manifest.models.map(\.id) ?? [],
                lastChecked: row.lastChecked)
        }
    }

    public func trustedTeams() async -> [EngineTrustedTeam] {
        let teams = await self.teams()
        let builtIn = host.manager.builtInTeams.sorted().map { EngineTrustedTeam(team: teams[$0] ?? EngineTeam(id: $0, name: $0), builtIn: true) }
        let approved = ((try? host.database.trustedTeams()) ?? []).filter { !host.manager.builtInTeams.contains($0.team) }
            .map { EngineTrustedTeam(team: EngineTeam(id: $0.team, name: $0.name), addedAt: $0.addedAt) }
        return builtIn + approved
    }

    static func request(_ held: HeldRelease) -> PluginTrustRequest {
        PluginTrustRequest(id: held.id, team: EngineTeam(id: held.team, name: held.teamName), pluginID: held.pluginID,
                           pluginTitle: held.title, version: held.version,
                           repository: URL(string: held.repo) ?? URL(string: "https://github.com")!,
                           signingIdentity: held.signingIdentity, notarized: held.notarized, models: held.models)
    }

    public func add(repository: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> PluginInstallOutcome {
        switch try await host.manager.add(repository: repository.absoluteString, progress: progress) {
        case .installed(let plugin):
            guard let shown = await plugins().first(where: { $0.id == plugin.id }) else { throw MESError(.engineError, "Installed, but not listed.") }
            return .installed(shown)
        case .held(let held):
            return .needsTrust(Self.request(held))
        }
    }

    public func trust(_ request: PluginTrustRequest, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.5)
        _ = try await host.manager.approve(request.id)
        progress(1)
    }

    public func decline(_ request: PluginTrustRequest) async { _ = try? await host.manager.decline(request.id) }

    public func update(plugin id: String, to update: EngineUpdate,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> PluginInstallOutcome {
        if case .held(let held) = try await host.manager.update(plugin: id, to: update.version, progress: progress) {
            return .needsTrust(Self.request(held))
        }
        guard let shown = await plugins().first(where: { $0.id == id }) else { throw MESError(.notFound, "No plugin \(id).") }
        return .installed(shown)
    }

    public func rollBack(plugin id: String) async throws { _ = try await host.manager.rollBack(plugin: id) }
    public func setEnabled(_ enabled: Bool, plugin id: String) async throws { try await host.manager.setEnabled(enabled, plugin: id) }
    public func checkForUpdates() async throws { await host.manager.checkForUpdates() }
    public func remove(plugin id: String) async throws { try await host.manager.remove(plugin: id) }
    public func revokeTrust(team id: String) async throws { try await host.manager.revoke(team: id) }
}

extension GaeaHost {
    /// The System page's processes: Gaea itself and every running worker, each read with `proc_pid_rusage` (UI-4). The
    /// detail lines carry the ledger (MEM-4): under Gaea, the budget and what the workers are charged; under each worker,
    /// its models' lanes and its charge, the larger of what it declared and what it measures.
    public var processSource: EngineProcessSource {
        .processes { [scheduler] in
            let ledger = await scheduler.ledger()
            var host = EngineProcess.current(title: "Gaea")
            host.detail = "Budget \(Self.gb(ledger.budgetBytes)) · workers charged \(Self.gb(ledger.chargedBytes)) · "
                + "free \(Self.gb(ledger.availableBytes))" + (ledger.queued > 0 ? " · \(ledger.queued) queued" : "")
            return [host] + ledger.workers.map { worker in
                let lanes = worker.lanes.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                let charge = "charged \(Self.gb(worker.chargedBytes)) (declared \(Self.gb(worker.declaredBytes)))"
                    + (worker.busy ? " · running" : "") + (worker.overrun ? " · past its declaration" : "")
                return EngineProcess(id: worker.pluginID, title: worker.title,
                                     detail: lanes.isEmpty ? charge : "\(lanes) · \(charge)", pid: worker.pid, role: .worker)
            }
        }
    }

    static func gb(_ bytes: UInt64) -> String { String(format: "%.1f GB", Double(bytes) / 1e9) }
}
