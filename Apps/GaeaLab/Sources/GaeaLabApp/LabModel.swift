import Foundation
import GaeaLabCore
import MESClientKit
import MESCore
import Observation
import PixelAgencyRun

/// Gaea Lab's state: Lite's run workflow (pixel-agency-run) over the engines this Mac knows, plus the pool of every
/// usable server as one more engine, "Every server". A run on the pool goes to the server that offers its model and
/// adapters (G-19); a run on one server stays there.
@MainActor @Observable
final class LabModel {
    static let shared = LabModel()

    let folder = WorkingFolder(key: "Gaea.Lab.workingFolder", appName: "Gaea Lab")
    let log = SessionLog()
    let directory: EngineDirectory
    let workflow: RunWorkflow
    let choices = AdapterChoices()
    let pool: EnginePool
    /// The servers in the pool now.
    private(set) var members: [EnginePool.Member] = []
    private var watching: Task<Void, Never>?

    private init() {
        directory = EngineDirectory(credentials: KeychainCredentialStore(prefix: "Gaea.Lab"),
                                    clientName: "Gaea Lab on \(Host.current().localizedName ?? "a Mac")")
        workflow = RunWorkflow(directory: directory, log: log)
        pool = EnginePool(adapters: choices.provider)
    }

    /// Finds servers over Bonjour, and keeps the pool to the ones that can be used (open, or paired).
    func start() {
        directory.startBrowsing()
        guard watching == nil else { return }
        watching = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshPool()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Rebuilds the pool from the directory's usable servers. When its servers change, the pool's operations do too,
    /// so a workflow showing the pool reloads them.
    func refreshPool() async {
        var next: [EnginePool.Member] = []
        for entry in directory.entries where entry.id != pool.id && !entry.isBuiltIn && !entry.needsPairing {
            guard let connection = try? await directory.connect(entry) else { continue }
            guard (try? await connection.health()) != nil else { continue }
            // Servers on one Mac share a host, so the port tells them apart.
            let address = entry.url.map { url in "\(url.host() ?? "")\(url.port.map { ":\($0)" } ?? "")" }
            next.append(.init(id: entry.id, name: entry.name + (address.map { " (\($0))" } ?? ""), connection: connection))
        }
        guard next.map(\.id) != members.map(\.id) else { return }
        members = next
        await pool.setMembers(next)
        if next.isEmpty {
            directory.removeLocal(id: pool.id)
            return
        }
        guard let entry = try? await directory.addLocal(pool) else { return }
        if workflow.engine == nil || workflow.engine?.id == pool.id { await workflow.select(entry) }
    }

    /// Where the current run's job went, when it ran on the pool.
    var currentRoute: EnginePool.Route? {
        guard let id = workflow.current?.job?.id else { return nil }
        return pool.route(of: id)
    }

    /// Ends the session: collected results not saved are deleted; the working folder is released.
    func end() {
        watching?.cancel()
        log.clear()
        folder.stop()
    }
}
