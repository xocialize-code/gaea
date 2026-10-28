import CryptoKit
import Foundation
import GaeaProtocol
import MLXToolKit

/// A plugin version on disk, verified, with its sealed manifest decoded.
public struct InstalledPlugin: Sendable {
    public var id: String
    public var version: String
    public var title: String
    public var repo: String
    public var enabled: Bool
    public var bundle: URL
    public var manifest: PluginManifest
    public var manifestData: Data

    public func model(_ id: String) -> PluginManifest.Model? { manifest.models.first { $0.id == id } }
}

/// What the scheduler does for the plugin manager: switch versions only when a plugin is idle, and stop its worker.
public protocol WorkerControl: Sendable {
    func isIdle(plugin id: String) async -> Bool
    /// Stops the plugin's worker, if it runs, through the escalation ladder.
    func retire(plugin id: String) async
}

/// Adds plugins by Git repo URL and keeps them: GitHub Releases, sha256, the Developer ID signature, the sealed
/// manifest, versions side by side, updates switched in when idle, rollback, and enabling (Plan §2.1, PLG-1 to PLG-5).
public actor PluginManager {
    public enum ManagerError: Error, CustomStringConvertible {
        case badRepository(String)
        case noCompatibleRelease(PluginRepository, [String])
        case alreadyAdded(String)
        case unknownPlugin(String)
        case checksum(expected: String, actual: String)
        case manifest(String)
        case extract(String)
        case noRollback(String)
        case noUpdate(String)

        public var description: String {
            switch self {
            case .badRepository(let text): "\(text) isn't a GitHub repo URL (https://github.com/owner/repo)."
            case let .noCompatibleRelease(repo, reasons):
                "\(repo) has no release Gaea \(Gaea.version) can install" + (reasons.isEmpty ? "." : ": " + reasons.joined(separator: "; "))
            case .alreadyAdded(let id): "\(id) is already added; update it instead."
            case .unknownPlugin(let id): "No plugin \(id)."
            case let .checksum(expected, actual): "Refused: sha256 mismatch (release says \(expected.prefix(12))…, download is \(actual.prefix(12))…)."
            case .manifest(let why): "Refused: \(why)"
            case .extract(let why): "Couldn't unpack the release: \(why)"
            case .noRollback(let id): "\(id) has no previous version kept to roll back to."
            case .noUpdate(let id): "\(id) has no newer compatible release."
            }
        }
    }

    let database: GaeaDatabase
    let paths: GaeaPaths
    let source: GitHubReleaseSource
    let log: HostLog
    var workers: (any WorkerControl)?
    var cache: [String: InstalledPlugin] = [:]
    /// Called after anything that changes what Gaea offers (the server reloads its descriptors).
    var onChange: (@Sendable () async -> Void)?

    public init(database: GaeaDatabase, paths: GaeaPaths, source: GitHubReleaseSource = GitHubReleaseSource(), log: HostLog) {
        self.database = database
        self.paths = paths
        self.source = source
        self.log = log
    }

    public func attach(workers: any WorkerControl, onChange: @escaping @Sendable () async -> Void) {
        self.workers = workers
        self.onChange = onChange
    }

    // MARK: - Reading

    public func rows() throws -> [GaeaDatabase.PluginRow] { try database.plugins() }

    /// Every installed plugin's active version, on or off, with its manifest. A version whose bundle can't be read is
    /// left out and marked failed.
    public func installed() -> [InstalledPlugin] {
        ((try? database.plugins()) ?? []).compactMap { row in
            if let cached = cache[row.id], cached.version == row.activeVersion {
                var plugin = cached
                plugin.enabled = row.enabled
                return plugin
            }
            guard let version = try? database.version(row.id, row.activeVersion) else { return nil }
            let bundle = URL(fileURLWithPath: version.bundlePath)
            guard let data = try? Data(contentsOf: bundle.appending(path: "Contents/Resources/manifest.json")),
                  let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
                try? database.updatePlugin(row.id) { $0.failure = "Its manifest can't be read." }
                return nil
            }
            let plugin = InstalledPlugin(id: row.id, version: row.activeVersion, title: row.title, repo: row.repo, enabled: row.enabled,
                                         bundle: bundle, manifest: manifest, manifestData: data)
            cache[row.id] = plugin
            return plugin
        }
    }

    /// The active version, checked again before a launch (PLG-3). A signature that no longer verifies marks the plugin
    /// failed and throws.
    public func launchable(_ id: String) throws -> InstalledPlugin {
        guard let plugin = installed().first(where: { $0.id == id }) else { throw ManagerError.unknownPlugin(id) }
        do {
            _ = try PluginVerifier.verify(plugin.bundle)
        } catch {
            try? database.updatePlugin(id) { $0.failure = "\(error)" }
            database.record("refused", plugin: id, version: plugin.version, "launch check: \(error)")
            throw error
        }
        if (try? database.plugin(id))??.failure != nil { try? database.updatePlugin(id) { $0.failure = nil } }
        return plugin
    }

    // MARK: - Adding

    /// Adds a plugin from its repo: the newest compatible release (or the release `version` names, a pre-release
    /// included), downloaded, checked (sha256, signature, manifest) and installed enabled. Another team's release is
    /// refused (G-22): v1 has no trust list.
    @discardableResult
    public func add(repository text: String, version: String? = nil,
                    progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> InstalledPlugin {
        guard let repo = PluginRepository(text) else { throw ManagerError.badRepository(text) }
        progress(0.02)
        let (release, releaseManifest) = if let version {
            try await named(repo, version: version)
        } else {
            try await newestCompatible(repo, newerThan: nil)
        }
        if let existing = try database.plugin(releaseManifest.id) {
            throw ManagerError.alreadyAdded("\(existing.title) (\(existing.id))")
        }
        let record = try await install(release, expected: releaseManifest, repo: repo, progress: progress)
        try database.insertPlugin(id: releaseManifest.id, repo: repo.url.absoluteString, title: releaseManifest.title,
                                  summary: releaseManifest.summary ?? "", team: releaseManifest.team, version: record)
        database.record("installed", plugin: releaseManifest.id, version: record.version,
                        "added from \(repo) (\(release.tag)); \(record.signature)")
        log("plugins: added \(releaseManifest.id) \(record.version) from \(repo)")
        progress(1)
        await onChange?()
        return try launchable(releaseManifest.id)
    }

    /// The newest release whose manifest this Gaea can run (`compatibility`), newer than `current` when given.
    ///
    /// **Pre-releases are skipped**, as GitHub's own "latest" skips them: Gaea installs and offers updates only from full
    /// releases unless the operator names a pre-release's version (`add … version`, `update … version`).
    func newestCompatible(_ repo: PluginRepository, newerThan current: SemVer?) async throws -> (PluginRelease, PluginManifest) {
        let releases = try await source.releases(repo).sorted { $0.version > $1.version }
        var reasons: [String] = []
        var skipped: [String] = []
        for release in releases {
            if let current, release.version <= current { break }
            if release.prerelease {
                skipped.append(release.tag)
                continue
            }
            switch await compatibility(release) {
            case .success(let manifest): return (release, manifest)
            case .failure(let reason): reasons.append(reason.description)
            }
        }
        if !skipped.isEmpty { reasons.append("pre-releases \(skipped.joined(separator: ", ")) are installed only by version") }
        if current != nil, reasons.allSatisfy({ $0.hasPrefix("pre-releases") }) { throw ManagerError.noUpdate(repo.description) }
        throw ManagerError.noCompatibleRelease(repo, reasons)
    }

    /// The release tagged `version` (a pre-release too), if this Gaea can run it.
    func named(_ repo: PluginRepository, version: String) async throws -> (PluginRelease, PluginManifest) {
        guard let wanted = SemVer(version) else { throw ManagerError.noCompatibleRelease(repo, ["\(version) isn't a version"]) }
        guard let release = try await source.releases(repo).first(where: { $0.version == wanted }) else {
            throw ManagerError.noCompatibleRelease(repo, ["no release \(version)"])
        }
        switch await compatibility(release) {
        case .success(let manifest): return (release, manifest)
        case .failure(let reason): throw ManagerError.noCompatibleRelease(repo, [reason.description])
        }
    }

    struct Incompatible: Error, CustomStringConvertible { let description: String }

    /// Whether this Gaea can run a release, from its published manifest: the three assets, GPP protocol, `min_gaea`, and
    /// the trusted team (G-22).
    func compatibility(_ release: PluginRelease) async -> Result<PluginManifest, Incompatible> {
        guard release.zip != nil, release.checksum != nil, let manifestAsset = release.manifest else {
            return .failure(Incompatible(description: "\(release.tag) lacks the .gaeaplugin.zip, its .sha256 or manifest.json"))
        }
        let manifest: PluginManifest
        do {
            manifest = try JSONDecoder().decode(PluginManifest.self, from: try await source.data(manifestAsset))
        } catch {
            return .failure(Incompatible(description: "\(release.tag)'s manifest doesn't decode (\(error))"))
        }
        guard Gaea.protocols.contains(manifest.protocol) else {
            return .failure(Incompatible(description: "\(release.tag) speaks GPP \(manifest.protocol)"))
        }
        guard let minGaea = SemVer(manifest.minGaea), minGaea <= SemVer(Gaea.version)! else {
            return .failure(Incompatible(description: "\(release.tag) needs Gaea \(manifest.minGaea)"))
        }
        guard manifest.team == GPP.trustedTeam else {
            return .failure(Incompatible(description: "\(release.tag) is from team \(manifest.team); Gaea v1 runs only plugins signed by "
                + "\(GPP.trustedTeam), and third-party plugins come with the trust list later (G-22)"))
        }
        return .success(manifest)
    }

    /// Downloads, checks and installs one release beside any versions already there. Nothing reaches the plugin folder
    /// unless every check passes.
    func install(_ release: PluginRelease, expected: PluginManifest, repo: PluginRepository,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> GaeaDatabase.VersionRecord {
        let fm = FileManager.default
        let staging = paths.staging.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        guard let zipAsset = release.zip, let checksumAsset = release.checksum else { throw ManagerError.manifest("assets missing") }
        let zip = staging.appending(path: zipAsset.name)
        progress(0.1)
        try await source.download(zipAsset, to: zip)
        progress(0.6)
        let expectedDigest = String(decoding: try await source.data(checksumAsset), as: UTF8.self)
            .split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
        let digest = try Self.sha256(file: zip)
        guard digest == expectedDigest else {
            database.record("refused", plugin: expected.id, version: release.version.description, "sha256 mismatch")
            throw ManagerError.checksum(expected: expectedDigest, actual: digest)
        }

        let unpacked = staging.appending(path: "unpacked", directoryHint: .isDirectory)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpacked.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw ManagerError.extract("ditto exited \(ditto.terminationStatus)") }
        let bundles = try fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil).filter { $0.pathExtension == "gaeaplugin" }
        guard bundles.count == 1, let staged = bundles.first else {
            throw ManagerError.extract("expected one .gaeaplugin in the zip, found \(bundles.count)")
        }
        progress(0.75)

        let signature: PluginVerifier.Signature
        do {
            signature = try PluginVerifier.verify(staged)
        } catch {
            database.record("refused", plugin: expected.id, version: release.version.description, "\(error)")
            log("plugins: refused \(expected.id) \(release.tag): \(error)")
            throw error
        }
        let manifestData = try Data(contentsOf: staged.appending(path: "Contents/Resources/manifest.json"))
        let manifest: PluginManifest
        do {
            manifest = try JSONDecoder().decode(PluginManifest.self, from: manifestData)
            try Self.check(manifest, expected: expected, release: release, repo: repo, signature: signature, bundle: staged)
        } catch {
            database.record("refused", plugin: expected.id, version: release.version.description, "\(error)")
            throw error
        }

        let destination = paths.installDirectory(plugin: manifest.id, version: manifest.version)
        try? fm.removeItem(at: destination)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let bundle = destination.appending(path: staged.lastPathComponent)
        try fm.moveItem(at: staged, to: bundle)
        _ = try PluginVerifier.verify(bundle)
        progress(0.95)
        return GaeaDatabase.VersionRecord(
            version: manifest.version, bundlePath: bundle.path, zipSHA256: digest,
            manifestSHA256: SHA256.hash(data: manifestData).map { String(format: "%02x", $0) }.joined(),
            signature: signature.description, notarized: signature.notarized)
    }

    /// The sealed manifest agrees with the release, the signature and the repo it was added from, and declares nothing
    /// Gaea refuses (remote providers, G-12).
    static func check(_ manifest: PluginManifest, expected: PluginManifest, release: PluginRelease, repo: PluginRepository,
                      signature: PluginVerifier.Signature, bundle: URL) throws {
        func refuse(_ why: String) -> ManagerError { .manifest(why) }
        guard manifest.id == expected.id, manifest.version == expected.version else {
            throw refuse("the bundle's manifest (\(manifest.id) \(manifest.version)) isn't the release's (\(expected.id) \(expected.version))")
        }
        guard SemVer(manifest.version) == release.version else {
            throw refuse("the manifest's version \(manifest.version) isn't the release tag \(release.tag)")
        }
        guard manifest.team == signature.team else {
            throw refuse("the manifest names team \(manifest.team) but the bundle is signed by \(signature.team)")
        }
        guard signature.identifier == manifest.id else {
            throw refuse("the bundle is signed as \(signature.identifier), not \(manifest.id)")
        }
        guard Gaea.protocols.contains(manifest.protocol) else { throw refuse("GPP \(manifest.protocol) isn't supported") }
        guard let declared = PluginRepository(manifest.repo), declared.matches(repo) else {
            throw refuse("the manifest's repo \(manifest.repo) isn't \(repo), the repo it was added from")
        }
        guard !manifest.offers.contains(where: { $0.model["remote_provider"] != nil }) else {
            throw refuse("an offer declares a remote provider; Gaea runs only local models (G-12)")
        }
        let executable = bundle.appending(path: "Contents/MacOS/\(manifest.executable)")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw refuse("no executable \(manifest.executable) in Contents/MacOS")
        }
        for model in manifest.models where model.lanes.filter(\.default).count != 1 {
            throw refuse("model \(model.id) doesn't have exactly one default lane")
        }
    }

    static func sha256(file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Updates

    /// Reads every plugin's repo for a newer compatible release and records what it finds.
    public func checkForUpdates() async {
        for row in (try? database.plugins()) ?? [] {
            await check(row)
        }
    }

    @discardableResult
    func check(_ row: GaeaDatabase.PluginRow) async -> PluginRelease? {
        guard let repo = PluginRepository(row.repo) else { return nil }
        do {
            let (release, _) = try await newestCompatible(repo, newerThan: SemVer(row.activeVersion))
            try database.updatePlugin(row.id) {
                $0.latestVersion = release.version.description
                $0.latestNotes = release.notes
                $0.latestURL = release.htmlURL?.absoluteString
                $0.latestPublishedAt = release.publishedAt
                $0.lastChecked = Date()
            }
            return release
        } catch {
            try? database.updatePlugin(row.id) {
                $0.latestVersion = nil
                $0.latestNotes = nil
                $0.latestURL = nil
                $0.latestPublishedAt = nil
                $0.lastChecked = Date()
            }
            if case ManagerError.noUpdate = error {} else { log("plugins: update check for \(row.id): \(error)") }
            return nil
        }
    }

    public enum SwitchOutcome: Sendable, Equatable {
        /// The plugin now runs `version`.
        case switched(String)
        /// `version` is installed; Gaea switches to it when the plugin's models are idle.
        case pending(String)
    }

    /// Installs a newer release beside the current one, then switches to it when the plugin is idle, keeping the version
    /// it replaces for rollback (PLG-4). `version` picks a release; nil takes the newest compatible.
    public func update(plugin id: String, to version: String? = nil,
                       progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> SwitchOutcome {
        guard let row = try database.plugin(id), let repo = PluginRepository(row.repo) else { throw ManagerError.unknownPlugin(id) }
        let current = SemVer(row.activeVersion)
        let release: PluginRelease
        let manifest: PluginManifest
        if let version {
            (release, manifest) = try await named(repo, version: version)
        } else {
            (release, manifest) = try await newestCompatible(repo, newerThan: current)
        }
        guard manifest.id == id else { throw ManagerError.manifest("the release is \(manifest.id), not \(id)") }
        if manifest.version == row.activeVersion { throw ManagerError.noUpdate(id) }

        try database.updatePlugin(id) { $0.failure = nil }
        let record: GaeaDatabase.VersionRecord
        if let existing = try database.version(id, manifest.version) {
            record = GaeaDatabase.VersionRecord(version: existing.version, bundlePath: existing.bundlePath, zipSHA256: existing.zipSHA256,
                                                manifestSHA256: existing.manifestSHA256, signature: existing.signature,
                                                notarized: existing.notarized)
        } else {
            record = try await install(release, expected: manifest, repo: repo, progress: progress)
            try database.insertVersion(record, plugin: id)
        }
        database.record("staged", plugin: id, version: record.version, "installed beside \(row.activeVersion) from \(release.tag)")
        log("plugins: staged \(id) \(record.version) beside \(row.activeVersion)")
        progress(1)
        return try await switchWhenIdle(id, to: record.version)
    }

    /// Switches back to the version kept on disk; the version it leaves is kept in turn.
    public func rollBack(plugin id: String) async throws -> SwitchOutcome {
        guard let row = try database.plugin(id) else { throw ManagerError.unknownPlugin(id) }
        guard let previous = row.previousVersion, try database.version(id, previous) != nil else { throw ManagerError.noRollback(id) }
        database.record("rollback", plugin: id, version: previous, "rolling back from \(row.activeVersion)")
        return try await switchWhenIdle(id, to: previous)
    }

    func switchWhenIdle(_ id: String, to version: String) async throws -> SwitchOutcome {
        if await workers?.isIdle(plugin: id) ?? true {
            try await switchNow(id, to: version)
            return .switched(version)
        }
        try database.updatePlugin(id) { $0.pendingVersion = version }
        log("plugins: \(id) is busy; switching to \(version) when idle")
        return .pending(version)
    }

    /// The scheduler calls this when a plugin's last job ends: a pending switch happens now.
    public func pluginBecameIdle(_ id: String) async {
        guard let row = try? database.plugin(id), let pending = row.pendingVersion else { return }
        try? await switchNow(id, to: pending)
    }

    func switchNow(_ id: String, to version: String) async throws {
        guard let row = try database.plugin(id) else { throw ManagerError.unknownPlugin(id) }
        await workers?.retire(plugin: id)
        let from = row.activeVersion
        try database.updatePlugin(id) {
            $0.previousVersion = from
            $0.activeVersion = version
            $0.pendingVersion = nil
            $0.failure = nil
            if $0.latestVersion.flatMap(SemVer.init).map({ $0 <= SemVer(version)! }) == true {
                $0.latestVersion = nil
                $0.latestNotes = nil
                $0.latestURL = nil
                $0.latestPublishedAt = nil
            }
        }
        cache[id] = nil
        if let manifest = installed().first(where: { $0.id == id })?.manifest {
            try database.updatePlugin(id) {
                $0.title = manifest.title
                $0.summary = manifest.summary ?? ""
            }
        }
        // Keep the active version and the one it replaced; older ones go.
        for old in try database.versions(of: id) where old.version != version && old.version != from {
            try? FileManager.default.removeItem(at: paths.installDirectory(plugin: id, version: old.version))
            try database.deleteVersion(plugin: id, version: old.version)
        }
        database.record("switched", plugin: id, version: version, "now runs \(version); kept \(from) for rollback")
        log("plugins: \(id) switched \(from) → \(version)")
        await onChange?()
    }

    // MARK: - Enabling and removing

    /// Switches a whole plugin on or off (PLG-5). Off, its models leave the descriptors and its worker stops.
    public func setEnabled(_ enabled: Bool, plugin id: String) async throws {
        guard try database.plugin(id) != nil else { throw ManagerError.unknownPlugin(id) }
        try database.updatePlugin(id) { $0.enabled = enabled }
        cache[id]?.enabled = enabled
        if !enabled { await workers?.retire(plugin: id) }
        database.record(enabled ? "enabled" : "disabled", plugin: id, enabled ? "switched on" : "switched off")
        log("plugins: \(id) \(enabled ? "enabled" : "disabled")")
        await onChange?()
    }

    public func remove(plugin id: String) async throws {
        guard try database.plugin(id) != nil else { throw ManagerError.unknownPlugin(id) }
        await workers?.retire(plugin: id)
        try? FileManager.default.removeItem(at: paths.plugins.appending(path: id))
        try database.deletePlugin(id)
        cache[id] = nil
        database.record("removed", plugin: id, "removed with its versions")
        log("plugins: removed \(id)")
        await onChange?()
    }
}
