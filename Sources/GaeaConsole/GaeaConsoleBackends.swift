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
            let optIn = entry.offer.namedOnly == true
            let lane = entry.model.lanes.first(where: \.default)
            let row = rows[entry.plugin.id]
            let bundled = lane.map { $0.resolved.materialization == .bundled || $0.resolved.weightSources.isEmpty } ?? true
            // A model with offers of its own (AB-T-0364) shows each; one without runs through the mock's image.generate.
            let own = routes.filter { $0.plugin.id == entry.plugin.id && $0.model.id == entry.model.id }
            let offer = own.first?.offer ?? entry.offer
            let roles: [EngineModel.Role] = own.isEmpty
                ? [.init(operation: GaeaEngine.mockOperation, qualityTiers: entry.offer.qualityTiers,
                         isDefault: isDefault(entry.model.id, for: GaeaEngine.mockOperation), namedOnly: optIn)]
                : own.map { .init(operation: $0.operation, qualityTiers: $0.offer.qualityTiers,
                                  isDefault: isDefault(entry.model.id, for: $0.operation), namedOnly: $0.offer.namedOnly == true) }
            return EngineModel(
                id: entry.model.id, title: entry.model.title, summary: entry.plugin.manifest.summary ?? "", license: offer.license,
                optIn: optIn, enabled: entry.plugin.enabled && host.enablement.isEnabled(entry.model.id, optIn: optIn),
                acceptedAt: host.enablement.acceptedAt(entry.model.id),
                roles: roles,
                notes: offer.notes, memoryClass: offer.memoryClass, speedClass: offer.speedClass,
                footprintBytes: lane.map { $0.resolved.persistentBytes + $0.resolved.peakTransientBytes },
                install: bundled ? .builtIn : .notDownloaded(bytes: nil), resident: resident.contains(entry.model.id),
                source: entry.model.package.provenance.sourceRepo, sourceURL: URL(string: entry.plugin.repo),
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
        try host.enablement.set(id, enabled: enabled, optIn: entry.offer.namedOnly == true)
        await host.server.reloadDescriptors()
    }

    public func unload(model id: String) async { await host.scheduler.unload(model: id) }
}

/// The Plugins page (UI-3) over Gaea's plugin manager. v1 trusts only Gaea's own team and has no trust list (G-22):
/// another team's plugin is refused with that reason rather than asking.
public struct GaeaPluginBackend: EnginePluginBackend {
    let host: GaeaHost

    public init(host: GaeaHost) { self.host = host }

    /// Gaea's own team, named as on the certificate of a plugin it installed (the signature recorded at install).
    func ownTeam() -> EngineTeam {
        let signatures = ((try? host.database.plugins()) ?? []).compactMap { try? host.database.version($0.id, $0.activeVersion)?.signature }
        let holder = signatures.lazy.compactMap { PluginVerifier.Signature.holder($0.components(separatedBy: ", id ").first ?? "") }.first
        return EngineTeam(id: GPP.trustedTeam, name: holder ?? "Gaea's own team")
    }

    public func plugins() async -> [EnginePlugin] {
        let installed = Dictionary(uniqueKeysWithValues: await host.manager.installed().map { ($0.id, $0) })
        let ownTeam = ownTeam()
        return ((try? host.database.plugins()) ?? []).map { row in
            let state: EnginePlugin.State = if let failure = row.failure {
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
                team: row.team == GPP.trustedTeam ? ownTeam : EngineTeam(id: row.team, name: row.team), enabled: row.enabled,
                state: state, models: installed[row.id]?.manifest.models.map(\.id) ?? [], lastChecked: row.lastChecked)
        }
    }

    public func trustedTeams() async -> [EngineTrustedTeam] { [EngineTrustedTeam(team: ownTeam(), builtIn: true)] }

    public func add(repository: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> PluginInstallOutcome {
        let plugin = try await host.manager.add(repository: repository.absoluteString, progress: progress)
        guard let shown = await plugins().first(where: { $0.id == plugin.id }) else { throw MESError(.engineError, "Installed, but not listed.") }
        return .installed(shown)
    }

    public func trust(_ request: PluginTrustRequest, progress: @escaping @Sendable (Double) -> Void) async throws {
        throw MESError(.forbidden, "Gaea v1 runs only plugins signed by \(GPP.trustedTeam); the trust list comes later (G-22).")
    }

    public func update(plugin id: String, to update: EngineUpdate,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> PluginInstallOutcome {
        _ = try await host.manager.update(plugin: id, to: update.version, progress: progress)
        guard let shown = await plugins().first(where: { $0.id == id }) else { throw MESError(.notFound, "No plugin \(id).") }
        return .installed(shown)
    }

    public func rollBack(plugin id: String) async throws { _ = try await host.manager.rollBack(plugin: id) }
    public func setEnabled(_ enabled: Bool, plugin id: String) async throws { try await host.manager.setEnabled(enabled, plugin: id) }
    public func checkForUpdates() async throws { await host.manager.checkForUpdates() }
    public func remove(plugin id: String) async throws { try await host.manager.remove(plugin: id) }

    public func revokeTrust(team id: String) async throws {
        throw MESError(.forbidden, "Gaea v1 trusts only its own team, which can't be removed (G-22).")
    }
}

extension GaeaHost {
    /// The System page's processes: Gaea itself and every running worker, each read with `proc_pid_rusage` (UI-4).
    public var processSource: EngineProcessSource {
        .processes { [scheduler] in
            [EngineProcess.current(title: "Gaea")] + (await scheduler.processes()).map {
                EngineProcess(id: $0.pluginID, title: $0.title, detail: $0.models.joined(separator: ", "), pid: $0.pid, role: .worker)
            }
        }
    }
}
