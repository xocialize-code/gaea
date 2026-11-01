import Darwin
import Foundation
import GaeaProtocol
import MESCore
import MESEngineCore

/// `release.json`, as `scripts/release.sh` publishes it beside each release's zip (G-24).
public struct GaeaReleaseFacts: Codable, Sendable, Equatable {
    public var name: String
    public var version: String
    public var tag: String
    public var zip: String
    public var sha256: String
    public var minimumMacOS: String
    public var gpp: [Int]
    /// The `manifest_version`s the release reads; releases before 0.12.0 didn't say, and read 1.
    public var manifest: [Int]?
    public var team: String
    public var notarized: Bool

    enum CodingKeys: String, CodingKey {
        case name, version, tag, zip, sha256, minimumMacOS = "minimum_macos", gpp, manifest, team, notarized
    }
}

/// Gaea updates itself from its own GitHub releases (DST-3, G-24): it checks for a newer release, downloads and verifies
/// it as plugins are verified, waits until no job is running or waiting, swaps the app bundle, keeps the version it
/// replaced, and relaunches. Full releases only, unless the operator opts into pre-releases or names a version.
public actor GaeaUpdater {
    public enum UpdateError: Error, CustomStringConvertible {
        case notAnApp(String)
        case translocated(String)
        case readOnly(String)
        case noRelease(String)
        case noUpdate(String)
        case assets(String)
        case checksum(expected: String, actual: String)
        case refused(String)
        case incompatible([String])
        case noRollback
        case busy(String)

        public var description: String {
            switch self {
            case .notAnApp(let path): "Gaea isn't running from Gaea.app (\(path)), so it can't replace itself."
            case .translocated(let path):
                "Gaea is running from a translocated copy (\(path)). Move Gaea.app to /Applications, open it from there, and update again."
            case .readOnly(let folder): "Gaea can't write to \(folder), the folder Gaea.app is in."
            case .noRelease(let version): "\(Gaea.releases) has no release \(version)."
            case .noUpdate(let why): why
            case .assets(let why): "Refused: \(why)"
            case let .checksum(expected, actual): "Refused: sha256 mismatch (release says \(expected.prefix(12))…, download is \(actual.prefix(12))…)."
            case .refused(let why): "Refused: \(why)"
            case .incompatible(let plugins):
                "Refused: the update would stop installed plugins running: " + plugins.joined(separator: "; ")
                    + ". Update or remove them first."
            case .noRollback: "No earlier Gaea is kept to roll back to."
            case .busy(let what): "An update is already in progress: \(what). Cancel it with: gaea update --cancel"
            }
        }
    }

    /// What `gaea update --check` and Settings show.
    public struct Status: Codable, Sendable {
        public var current: String
        public var latest: String?
        public var latestPrerelease: Bool?
        public var latestURL: String?
        public var latestPublishedAt: Date?
        public var lastChecked: Date?
        public var checkError: String?
        public var prereleases: Bool
        /// The version staged to install, and what it waits for.
        public var staged: String?
        public var rollingBack: Bool
        public var waitingFor: String?
        /// The version kept for rollback.
        public var kept: String?
        /// The app this Gaea runs from, and why it can't replace itself if it can't.
        public var app: String?
        public var cannotUpdate: String?
        public var lastFailure: String?
    }

    static let prereleasesSetting = "update.prereleases"
    /// How often Gaea checks on its own.
    static let checkInterval: TimeInterval = 6 * 3600

    let database: GaeaDatabase
    let paths: GaeaPaths
    let source: GitHubReleaseSource
    let log: HostLog
    let appBundle: URL?
    /// Held outputs younger than this keep an update waiting, so their clients can fetch them.
    let grace: TimeInterval
    var plugins: @Sendable () async -> [InstalledPlugin] = { [] }
    var activity: @Sendable () async -> EngineActivity? = { nil }
    var relaunch: @Sendable (URL) async -> Void = { _ in }

    var latest: PluginRelease?
    var lastChecked: Date?
    var checkError: String?
    var lastFailure: String?
    var staged: (version: String, app: URL, rollback: Bool)?
    var waitingFor: String?
    var waiter: Task<Void, Never>?

    public init(database: GaeaDatabase, paths: GaeaPaths, source: GitHubReleaseSource = GitHubReleaseSource(), log: HostLog,
                appBundle: URL? = Bundle.main.bundleURL, grace: TimeInterval = 60) {
        self.database = database
        self.paths = paths
        self.source = source
        self.log = log
        self.appBundle = appBundle
        self.grace = grace
    }

    /// The host's parts the updater needs: installed plugins (for compatibility), the MES server's jobs (to wait until
    /// none runs), and the relaunch, which stops serving and starts the swapped app.
    public func attach(plugins: @escaping @Sendable () async -> [InstalledPlugin],
                       activity: @escaping @Sendable () async -> EngineActivity?,
                       relaunch: @escaping @Sendable (URL) async -> Void) {
        self.plugins = plugins
        self.activity = activity
        self.relaunch = relaunch
    }

    var prereleases: Bool { ((try? database.setting(Self.prereleasesSetting)) ?? nil) == "on" }

    public func setPrereleases(_ on: Bool) throws {
        try database.setSetting(Self.prereleasesSetting, on ? "on" : nil)
        log("update: pre-releases \(on ? "included" : "skipped")")
        latest = nil
    }

    public func status() -> Status {
        var cannotUpdate: String?
        do { _ = try bundleToReplace() } catch { cannotUpdate = "\(error)" }
        return Status(current: Gaea.version, latest: latest?.version.description, latestPrerelease: latest?.prerelease,
                      latestURL: latest?.htmlURL?.absoluteString, latestPublishedAt: latest?.publishedAt, lastChecked: lastChecked,
                      checkError: checkError, prereleases: prereleases, staged: staged?.version, rollingBack: staged?.rollback ?? false,
                      waitingFor: waitingFor, kept: keptBundle().map(\.version), app: appBundle?.path, cannotUpdate: cannotUpdate,
                      lastFailure: lastFailure)
    }

    // MARK: - Checking

    /// Reads Gaea's releases and remembers the newest one this Gaea would install, if newer than itself.
    @discardableResult
    public func check() async -> PluginRelease? {
        lastChecked = Date()
        do {
            latest = Self.choose(try await source.releases(Gaea.releases), current: SemVer(Gaea.version)!, prereleases: prereleases)
            checkError = nil
            if let latest { log("update: Gaea \(latest.version)\(latest.prerelease ? " (pre-release)" : "") is available") }
        } catch {
            checkError = "\(error)"
            log("update: check failed: \(error)")
        }
        return latest
    }

    /// Checks when the last check is older than six hours. The host calls it on a timer.
    public func checkIfDue() async {
        if lastChecked.map({ Date().timeIntervalSince($0) >= Self.checkInterval }) ?? true { await check() }
    }

    /// The newest release newer than `current` that carries a release's three assets: full releases only, unless
    /// `prereleases`.
    static func choose(_ releases: [PluginRelease], current: SemVer, prereleases: Bool) -> PluginRelease? {
        releases.filter { $0.version > current && (prereleases || !$0.prerelease) && assets($0) != nil }.max { $0.version < $1.version }
    }

    /// A Gaea release's zip, its `.sha256` and `release.json`.
    static func assets(_ release: PluginRelease) -> (zip: PluginRelease.Asset, checksum: PluginRelease.Asset, facts: PluginRelease.Asset)? {
        guard let zip = release.assets.first(where: { $0.name == "Gaea-\(release.version).zip" }),
              let checksum = release.assets.first(where: { $0.name == "Gaea-\(release.version).zip.sha256" }),
              let facts = release.assets.first(where: { $0.name == "release.json" }) else { return nil }
        return (zip, checksum, facts)
    }

    // MARK: - Installing

    /// Downloads and verifies the newest release (or the one `version` names, a pre-release too), then installs it once
    /// no job is running or waiting. Returns at once with what it's waiting for.
    public func install(version: String? = nil) async throws -> String {
        if let staged { throw UpdateError.busy("\(staged.rollback ? "rolling back to" : "installing") \(staged.version)") }
        let target = try bundleToReplace()
        let release: PluginRelease
        if let version {
            guard let wanted = SemVer(version) else { throw UpdateError.noRelease(version) }
            guard let named = try await source.releases(Gaea.releases).first(where: { $0.version == wanted }) else {
                throw UpdateError.noRelease(version)
            }
            guard named.version != SemVer(Gaea.version) else { throw UpdateError.noUpdate("Gaea is already \(Gaea.version).") }
            release = named
        } else {
            guard let newest = await check() else {
                throw UpdateError.noUpdate(checkError.map { "Couldn't read \(Gaea.releases)'s releases: \($0)" }
                    ?? "Gaea \(Gaea.version) is the newest release\(prereleases ? "" : " (pre-releases are skipped)").")
            }
            release = newest
        }
        let (app, info) = try await stage(release)
        do { try await compatible(info) } catch {
            try? FileManager.default.removeItem(at: Self.stagingFolder(of: app))
            throw error
        }
        log("update: Gaea \(info.version) downloaded and verified; installing when no job is running or waiting")
        database.record("update", version: info.version, "staged from \(release.tag), replacing \(Gaea.version)")
        return await begin(app, version: info.version, replacing: target, rollback: false)
    }

    /// Goes back to the version the last update replaced, once no job is running or waiting. The version it leaves is
    /// kept in turn.
    public func rollBack() async throws -> String {
        if let staged { throw UpdateError.busy("\(staged.rollback ? "rolling back to" : "installing") \(staged.version)") }
        let target = try bundleToReplace()
        guard let kept = keptBundle() else { throw UpdateError.noRollback }
        // The kept app ran here before; it must still be ours and unbroken, notarized or not (a local build).
        let signature = try PluginVerifier.verify(kept.app)
        guard signature.identifier == Gaea.bundleIdentifier else { throw UpdateError.refused("\(kept.app.path) is \(signature.identifier)") }
        let info = buildInfo(of: kept.app)
        try await compatible(info)
        log("update: rolling back to Gaea \(kept.version) when no job is running or waiting")
        database.record("update", version: kept.version, "rolling back from \(Gaea.version)")
        return await begin(kept.app, version: kept.version, replacing: target, rollback: true)
    }

    /// Drops a staged update that is still waiting.
    public func cancel() -> String {
        guard let staged else { return "No update is waiting." }
        waiter?.cancel()
        waiter = nil
        if !staged.rollback { try? FileManager.default.removeItem(at: Self.stagingFolder(of: staged.app)) }
        self.staged = nil
        waitingFor = nil
        log("update: cancelled \(staged.version)")
        return "Cancelled \(staged.rollback ? "the rollback to" : "the update to") \(staged.version)."
    }

    func begin(_ app: URL, version: String, replacing target: URL, rollback: Bool) async -> String {
        staged = (version, app, rollback)
        let now = Self.quiet(await activity(), now: Date(), grace: grace)
        waiter = Task { await self.waitThenSwap(app, version: version, replacing: target, rollback: rollback) }
        let verb = rollback ? "Rolling back to" : "Installing"
        return "\(verb) Gaea \(version)" + (now.map { " once no job is running or waiting (now: \($0))" } ?? "")
            + "; Gaea relaunches itself. gaea update --cancel stops it."
    }

    func waitThenSwap(_ app: URL, version: String, replacing target: URL, rollback: Bool) async {
        while !Task.isCancelled {
            waitingFor = Self.quiet(await activity(), now: Date(), grace: grace)
            if waitingFor == nil { break }
            try? await Task.sleep(for: .seconds(1))
        }
        guard !Task.isCancelled else { return }
        do {
            let kept = try swap(app, replacing: target, rollback: rollback)
            database.record("update", version: version, "installed, replacing \(kept); relaunching")
            log("update: Gaea \(version) is in place (kept \(kept)); relaunching")
            await relaunch(target)
        } catch {
            lastFailure = "\(error)"
            log("update: installing \(version) failed: \(error)")
            database.record("update", version: version, "failed: \(error)")
            if !rollback { try? FileManager.default.removeItem(at: Self.stagingFolder(of: app)) }
            staged = nil
            waitingFor = nil
        }
    }

    /// What an update waits for, or nil when Gaea is quiet: no job received, fetching, waiting or running, and no held
    /// output finished less than `grace` ago (its client may still be fetching it).
    static func quiet(_ activity: EngineActivity?, now: Date, grace: TimeInterval) -> String? {
        guard let activity else { return nil }
        let running = activity.jobs.filter { $0.outcome == nil && $0.state == .running }.count
        let upcoming = activity.upcoming.count
        let held = activity.jobs.filter { $0.state == .holding && ($0.finishedAt.map { now.timeIntervalSince($0) < grace } ?? false) }.count
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if upcoming > 0 { parts.append("\(upcoming) waiting") }
        if held > 0 { parts.append("\(held) just finished, held for its client") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The Gaea.app this process runs from, if it can replace itself.
    nonisolated func bundleToReplace() throws -> URL {
        guard let app = appBundle, app.pathExtension == "app",
              Self.info(app)?["CFBundleIdentifier"] as? String == Gaea.bundleIdentifier else { throw UpdateError.notAnApp(appBundle?.path ?? "?") }
        if app.path.contains("/AppTranslocation/") { throw UpdateError.translocated(app.path) }
        let folder = app.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else { throw UpdateError.readOnly(folder.path) }
        return app
    }

    /// Downloads a release and checks it: both digests, the Developer ID signature of our team with hardened runtime,
    /// notarization, the bundle identifier, the version, the macOS it needs, and what the staged app says it speaks.
    func stage(_ release: PluginRelease) async throws -> (URL, Gaea.BuildInfo) {
        guard let assets = Self.assets(release) else {
            throw UpdateError.assets("\(release.tag) lacks Gaea-\(release.version).zip, its .sha256 or release.json")
        }
        let facts: GaeaReleaseFacts
        do {
            facts = try JSONDecoder().decode(GaeaReleaseFacts.self, from: try await source.data(assets.facts))
        } catch {
            throw UpdateError.assets("\(release.tag)'s release.json doesn't decode (\(error))")
        }
        guard SemVer(facts.version) == release.version, facts.zip == assets.zip.name else {
            throw UpdateError.assets("release.json describes \(facts.version) (\(facts.zip)), not \(release.tag)")
        }
        guard facts.team == GPP.trustedTeam else { throw UpdateError.refused("release.json names team \(facts.team)") }
        guard Self.runsHere(minimum: facts.minimumMacOS) else {
            throw UpdateError.refused("Gaea \(facts.version) needs macOS \(facts.minimumMacOS)")
        }
        // Refuse before downloading when the release says it drops what a plugin uses; the staged app is asked again.
        try await compatible(Gaea.BuildInfo(version: facts.version, gpp: facts.gpp, manifest: facts.manifest ?? [1]))

        let fm = FileManager.default
        let staging = paths.staging.appending(path: "gaea-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let zip = staging.appending(path: assets.zip.name)
            try await source.download(assets.zip, to: zip)
            let published = String(decoding: try await source.data(assets.checksum), as: UTF8.self)
                .split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
            let digest = try PluginManager.sha256(file: zip)
            guard digest == published else { throw UpdateError.checksum(expected: published, actual: digest) }
            guard digest == facts.sha256.lowercased() else { throw UpdateError.checksum(expected: facts.sha256, actual: digest) }

            let unpacked = staging.appending(path: "unpacked", directoryHint: .isDirectory)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
            try? fm.removeItem(at: zip)
            let apps = try fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
            guard apps.count == 1, let app = apps.first else { throw UpdateError.assets("expected one .app in the zip, found \(apps.count)") }

            let signature = try PluginVerifier.verify(app)
            guard signature.identifier == Gaea.bundleIdentifier else {
                throw UpdateError.refused("the app is signed as \(signature.identifier), not \(Gaea.bundleIdentifier)")
            }
            guard signature.notarized else { throw UpdateError.refused("Gaea \(release.version) isn't notarized") }
            let bundleVersion = Self.version(of: app)
            guard bundleVersion.flatMap(SemVer.init) == release.version else {
                throw UpdateError.refused("the app is version \(bundleVersion ?? "?"), not \(release.version)")
            }
            let info = buildInfo(of: app)
            guard SemVer(info.version) == release.version else {
                throw UpdateError.refused("the app says it is \(info.version), not \(release.version)")
            }
            log("update: verified Gaea \(release.version): sha256 \(digest.prefix(12))…, \(signature)")
            return (app, info)
        } catch {
            try? fm.removeItem(at: staging)
            database.record("update", version: release.version.description, "refused: \(error)")
            throw error
        }
    }

    /// Whether `info`'s protocols cover every installed plugin. Throws naming the plugins it would strand.
    func compatible(_ info: Gaea.BuildInfo) async throws {
        let problems = Self.incompatibilities(await plugins().map { ($0.id, $0.version, $0.manifest.protocol, $0.manifest.manifestVersion) },
                                              info: info)
        if !problems.isEmpty { throw UpdateError.incompatible(problems) }
    }

    static func incompatibilities(_ plugins: [(id: String, version: String, gpp: Int, manifest: Int)], info: Gaea.BuildInfo) -> [String] {
        plugins.flatMap { p -> [String] in
            var problems: [String] = []
            if !info.gpp.contains(p.gpp) {
                problems.append("\(p.id) \(p.version) speaks GPP \(p.gpp), and Gaea \(info.version) speaks \(info.gpp.map(String.init).joined(separator: ", "))")
            }
            if !info.manifest.contains(p.manifest) {
                problems.append("\(p.id) \(p.version) has manifest version \(p.manifest), and Gaea \(info.version) reads \(info.manifest.map(String.init).joined(separator: ", "))")
            }
            return problems
        }
    }

    /// What a Gaea.app says it is (`Gaea --version`). A Gaea from before 0.12.0 doesn't answer, and spoke GPP 1 and
    /// manifest version 1.
    nonisolated func buildInfo(of app: URL) -> Gaea.BuildInfo {
        let process = Process()
        process.executableURL = app.appending(path: "Contents/MacOS/Gaea")
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0, let info = try? JSONDecoder().decode(Gaea.BuildInfo.self, from: data) { return info }
        }
        return Gaea.BuildInfo(version: Self.version(of: app) ?? "?", gpp: [1], manifest: [1])
    }

    /// An app's Info.plist, read from disk each time (`Bundle` caches by path, and a swap changes what a path holds).
    nonisolated static func info(_ app: URL) -> [String: Any]? {
        NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")) as? [String: Any]
    }

    nonisolated static func version(of app: URL) -> String? { info(app)?["CFBundleShortVersionString"] as? String }

    /// The folder `stage` made for a download: `…/staging/gaea-<uuid>/unpacked/Gaea.app`.
    static func stagingFolder(of app: URL) -> URL { app.deletingLastPathComponent().deletingLastPathComponent() }

    static func runsHere(minimum: String) -> Bool {
        let parts = minimum.split(separator: ".").compactMap { Int($0) }
        let needed = OperatingSystemVersion(majorVersion: parts.first ?? 0, minorVersion: parts.dropFirst().first ?? 0,
                                            patchVersion: parts.dropFirst(2).first ?? 0)
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(needed)
    }

    // MARK: - Swapping

    /// The app kept for rollback, if one is.
    func keptBundle() -> (app: URL, version: String)? {
        let apps = (try? FileManager.default.contentsOfDirectory(at: paths.updates, includingPropertiesForKeys: nil)) ?? []
        guard let app = apps.first(where: { $0.pathExtension == "app" }),
              let version = Self.version(of: app) else { return nil }
        return (app, version)
    }

    /// Puts `app` where `target` is, in one atomic exchange, and keeps the app it replaces in Gaea's Updates folder
    /// (replacing any kept before). Returns the version it kept.
    func swap(_ app: URL, replacing target: URL, rollback: Bool) throws -> String {
        let fm = FileManager.default
        let replaced = Self.version(of: target) ?? "?"
        // Beside the target first, so the exchange is a rename on one volume.
        let beside = target.deletingLastPathComponent().appending(path: ".Gaea-\(UUID().uuidString).app", directoryHint: .isDirectory)
        try fm.moveItem(at: app, to: beside)
        if !rollback { try? fm.removeItem(at: Self.stagingFolder(of: app)) }
        do {
            let signature = try PluginVerifier.verify(beside)
            guard signature.identifier == Gaea.bundleIdentifier else { throw UpdateError.refused("the moved app is \(signature.identifier)") }
            guard renamex_np(beside.path, target.path, UInt32(RENAME_SWAP)) == 0 else {
                throw UpdateError.refused("couldn't exchange \(target.lastPathComponent): \(String(cString: strerror(errno)))")
            }
        } catch {
            if rollback { try? fm.moveItem(at: beside, to: app) } else { try? fm.removeItem(at: beside) }
            throw error
        }
        // `beside` now holds the app that was running. Keep it, and only it.
        try fm.createDirectory(at: paths.updates, withIntermediateDirectories: true)
        for old in (try? fm.contentsOfDirectory(at: paths.updates, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: old)
        }
        try fm.moveItem(at: beside, to: paths.updates.appending(path: "Gaea-\(replaced).app", directoryHint: .isDirectory))
        return replaced
    }

    static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.assets("\(tool) exited \(process.terminationStatus)") }
    }
}
