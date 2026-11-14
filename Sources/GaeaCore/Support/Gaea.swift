import Foundation
import GaeaOperator

/// Gaea's identity and the folders it uses.
public enum Gaea {
    /// This build's version, compared with a plugin manifest's `min_gaea`.
    public static let version = "1.7.0"
    /// GPP protocol versions this host speaks (GPP-1 §6).
    public static let protocols: ClosedRange<Int> = 1...1
    /// The `manifest_version`s this host reads.
    public static let manifestVersions: ClosedRange<Int> = 1...1
    /// Gaea.app's bundle identifier, which an update must carry.
    public static let bundleIdentifier = "com.xocialize.gaea"
    /// Where Gaea's own releases are published (G-24). `GAEA_UPDATE_REPO` points the updater at another repo (tests).
    public static var releases: PluginRepository {
        ProcessInfo.processInfo.environment["GAEA_UPDATE_REPO"].flatMap(PluginRepository.init) ?? PluginRepository("xocialize-code/gaea")!
    }

    /// What `Gaea --version` prints, and what the updater reads from a staged app before it installs it.
    public struct BuildInfo: Codable, Sendable, Equatable {
        public var version: String
        public var gpp: [Int]
        public var manifest: [Int]
    }

    public static var buildInfo: BuildInfo {
        BuildInfo(version: version, gpp: Array(protocols), manifest: Array(manifestVersions))
    }
}

/// Every path Gaea reads or writes. Only Gaea opens `gaea.sqlite` (G-16).
public struct GaeaPaths: Sendable {
    /// `~/Library/Application Support/Gaea`, or `GAEA_HOME`.
    public var root: URL
    /// The shared weights folder, `~/Library/Application Support/MLXEngine/Models` (G-9, MEM-8).
    public var modelsRoot: URL
    /// Spool, per-plugin caches and worker logs live under here.
    public var caches: URL
    public var logs: URL

    public init(root: URL = GaeaHome.applicationSupport, modelsRoot: URL? = nil, caches: URL? = nil, logs: URL? = nil) {
        self.root = root
        let home = FileManager.default.homeDirectoryForCurrentUser
        let isDefault = root.standardizedFileURL.path == home.appending(path: "Library/Application Support/Gaea").standardizedFileURL.path
        self.modelsRoot = modelsRoot ?? home.appending(path: "Library/Application Support/MLXEngine/Models", directoryHint: .isDirectory)
        self.caches = caches ?? (isDefault ? home.appending(path: "Library/Caches/Gaea", directoryHint: .isDirectory)
                                           : root.appending(path: "Caches", directoryHint: .isDirectory))
        self.logs = logs ?? (isDefault ? home.appending(path: "Library/Logs/Gaea", directoryHint: .isDirectory)
                                       : root.appending(path: "Logs", directoryHint: .isDirectory))
    }

    public var database: URL { root.appending(path: "gaea.sqlite") }
    public var plugins: URL { root.appending(path: "Plugins", directoryHint: .isDirectory) }
    public var socket: URL { root.appending(path: "operator.sock") }
    /// The Gaea.app an update replaced, kept for `gaea update --rollback`.
    public var updates: URL { root.appending(path: "Updates", directoryHint: .isDirectory) }
    /// Releases held for the operator's answer because their team isn't trusted (AB-T-0411).
    public var held: URL { root.appending(path: "Held", directoryHint: .isDirectory) }
    /// The macOS crash reports of crashed workers, copied as `<crash id>-<report>.ips` (SRV-8).
    public var crashes: URL { root.appending(path: "Crashes", directoryHint: .isDirectory) }
    /// MES pairing and TLS state (never the spool, which is wiped at start).
    public var serverState: URL { root.appending(path: "Server", directoryHint: .isDirectory) }
    public var spool: URL { caches.appending(path: "spool", directoryHint: .isDirectory) }
    /// Downloads in flight, removed when an install finishes or fails.
    public var staging: URL { caches.appending(path: "staging", directoryHint: .isDirectory) }
    /// The GPP sessions Gaea records (one transcript per worker launch), for `tools/validate.py --transcript`.
    public var sessions: URL { logs.appending(path: "sessions", directoryHint: .isDirectory) }

    public func pluginCache(_ id: String) -> URL { caches.appending(path: "plugins/\(id)", directoryHint: .isDirectory) }
    public func pluginLog(_ id: String) -> URL { logs.appending(path: "plugins/\(id).log") }
    public var hostLog: URL { logs.appending(path: "gaea.log") }
    public func installDirectory(plugin id: String, version: String) -> URL {
        plugins.appending(path: "\(id)/\(version)", directoryHint: .isDirectory)
    }

    /// Creates every folder, owner-only where it holds state.
    public func create() throws {
        let fm = FileManager.default
        for url in [root, plugins, held, serverState, caches, spool, staging, logs, sessions, logs.appending(path: "plugins")] {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }
}
