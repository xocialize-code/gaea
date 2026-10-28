import Foundation
import GRDB
import MESEngineCore

/// `~/Library/Application Support/Gaea/gaea.sqlite`. Only Gaea opens it (G-5, G-16): plugins reach their own store
/// through GPP `storage.*`, and the console and CLI through Gaea. No job media or job state goes in it.
public final class GaeaDatabase: Sendable {
    let queue: DatabaseQueue

    public init(path: URL) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.label = "gaea.sqlite"
        queue = try DatabaseQueue(path: path.path, configuration: configuration)
        try Self.migrator.migrate(queue)
    }

    /// An in-memory database, for tests.
    public init() throws {
        queue = try DatabaseQueue()
        try Self.migrator.migrate(queue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            // One row per plugin added by repo URL (G-18).
            try db.create(table: "plugin") { t in
                t.primaryKey("id", .text)
                t.column("repo", .text).notNull()
                t.column("title", .text).notNull()
                t.column("summary", .text).notNull().defaults(to: "")
                t.column("team", .text).notNull()
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("active_version", .text).notNull()
                t.column("previous_version", .text)
                t.column("pending_version", .text)
                t.column("latest_version", .text)
                t.column("latest_notes", .text)
                t.column("latest_url", .text)
                t.column("latest_published_at", .datetime)
                t.column("last_checked", .datetime)
                t.column("failure", .text)
                t.column("added_at", .datetime).notNull()
            }
            // Versions installed side by side (PLG-4).
            try db.create(table: "plugin_version") { t in
                t.column("plugin_id", .text).notNull().references("plugin", onDelete: .cascade)
                t.column("version", .text).notNull()
                t.column("bundle_path", .text).notNull()
                t.column("zip_sha256", .text).notNull()
                t.column("manifest_sha256", .text).notNull()
                t.column("signature", .text).notNull()
                t.column("notarized", .boolean).notNull().defaults(to: false)
                t.column("installed_at", .datetime).notNull()
                t.primaryKey(["plugin_id", "version"])
            }
            // The enabled set (ModelEnablement's store), replacing enabled-models.json.
            try db.create(table: "model_choice") { t in
                t.primaryKey("model_id", .text)
                t.column("state", .text).notNull() // "disabled" (a default model switched off) or "enabled" (an opt-in one on)
                t.column("accepted_at", .datetime)
            }
            // Gaea's settings and each plugin's operator settings (`plugin:<id>:<key>`), values as JSON.
            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            // Each plugin's own store (GPP-1 §3.6), namespaced by plugin and namespace.
            try db.create(table: "plugin_store") { t in
                t.column("plugin_id", .text).notNull()
                t.column("namespace", .text).notNull()
                t.column("key", .text).notNull()
                t.column("value", .text).notNull()
                t.column("updated_at", .datetime).notNull()
                t.primaryKey(["plugin_id", "namespace", "key"])
            }
            try db.create(table: "plugin_store_schema") { t in
                t.primaryKey("plugin_id", .text)
                t.column("schema_version", .integer).notNull()
                t.column("migrations", .text).notNull()
            }
            // Installs, updates, rollbacks, refusals, and workers that ran past their declared memory (MEM-4).
            try db.create(table: "event") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("at", .datetime).notNull()
                t.column("plugin_id", .text)
                t.column("version", .text)
                t.column("kind", .text).notNull()
                t.column("message", .text).notNull()
            }
        }
        return migrator
    }

    // MARK: - Plugins

    public struct PluginRow: Sendable, Equatable {
        public var id: String
        public var repo: String
        public var title: String
        public var summary: String
        public var team: String
        public var enabled: Bool
        public var activeVersion: String
        public var previousVersion: String?
        public var pendingVersion: String?
        public var latestVersion: String?
        public var latestNotes: String?
        public var latestURL: String?
        public var latestPublishedAt: Date?
        public var lastChecked: Date?
        public var failure: String?
        public var addedAt: Date

        init(_ row: Row) {
            id = row["id"]; repo = row["repo"]; title = row["title"]; summary = row["summary"]; team = row["team"]
            enabled = row["enabled"]; activeVersion = row["active_version"]; previousVersion = row["previous_version"]
            pendingVersion = row["pending_version"]; latestVersion = row["latest_version"]; latestNotes = row["latest_notes"]
            latestURL = row["latest_url"]; latestPublishedAt = row["latest_published_at"]; lastChecked = row["last_checked"]
            failure = row["failure"]; addedAt = row["added_at"]
        }
    }

    public struct VersionRow: Sendable, Equatable {
        public var pluginID: String
        public var version: String
        public var bundlePath: String
        public var zipSHA256: String
        public var manifestSHA256: String
        public var signature: String
        public var notarized: Bool
        public var installedAt: Date

        init(_ row: Row) {
            pluginID = row["plugin_id"]; version = row["version"]; bundlePath = row["bundle_path"]
            zipSHA256 = row["zip_sha256"]; manifestSHA256 = row["manifest_sha256"]; signature = row["signature"]
            notarized = row["notarized"]; installedAt = row["installed_at"]
        }
    }

    public func plugins() throws -> [PluginRow] {
        try queue.read { db in try Row.fetchAll(db, sql: "SELECT * FROM plugin ORDER BY title").map(PluginRow.init) }
    }

    public func plugin(_ id: String) throws -> PluginRow? {
        try queue.read { db in try Row.fetchOne(db, sql: "SELECT * FROM plugin WHERE id = ?", arguments: [id]).map(PluginRow.init) }
    }

    public func versions(of id: String) throws -> [VersionRow] {
        try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM plugin_version WHERE plugin_id = ?", arguments: [id]).map(VersionRow.init)
        }
    }

    public func version(_ id: String, _ version: String) throws -> VersionRow? {
        try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM plugin_version WHERE plugin_id = ? AND version = ?", arguments: [id, version])
                .map(VersionRow.init)
        }
    }

    /// Records a newly added plugin and its first version, active and enabled.
    public func insertPlugin(id: String, repo: String, title: String, summary: String, team: String, version: VersionRecord) throws {
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO plugin (id, repo, title, summary, team, enabled, active_version, added_at, last_checked)
                VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?)
                """, arguments: [id, repo, title, summary, team, version.version, Date(), Date()])
            try Self.insert(version, plugin: id, db)
        }
    }

    public struct VersionRecord: Sendable {
        public var version: String
        public var bundlePath: String
        public var zipSHA256: String
        public var manifestSHA256: String
        public var signature: String
        public var notarized: Bool
    }

    public func insertVersion(_ version: VersionRecord, plugin id: String) throws {
        try queue.write { db in try Self.insert(version, plugin: id, db) }
    }

    static func insert(_ v: VersionRecord, plugin id: String, _ db: GRDB.Database) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO plugin_version (plugin_id, version, bundle_path, zip_sha256, manifest_sha256, signature, notarized, installed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [id, v.version, v.bundlePath, v.zipSHA256, v.manifestSHA256, v.signature, v.notarized, Date()])
    }

    public func deleteVersion(plugin id: String, version: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM plugin_version WHERE plugin_id = ? AND version = ?", arguments: [id, version])
        }
    }

    /// Updates a plugin's row in one transaction.
    public func updatePlugin(_ id: String, _ change: @escaping @Sendable (inout PluginRow) -> Void) throws {
        try queue.write { db in
            guard var row = try Row.fetchOne(db, sql: "SELECT * FROM plugin WHERE id = ?", arguments: [id]).map(PluginRow.init) else {
                return
            }
            change(&row)
            try db.execute(sql: """
                UPDATE plugin SET repo = ?, title = ?, summary = ?, team = ?, enabled = ?, active_version = ?, previous_version = ?,
                  pending_version = ?, latest_version = ?, latest_notes = ?, latest_url = ?, latest_published_at = ?, last_checked = ?,
                  failure = ? WHERE id = ?
                """, arguments: [row.repo, row.title, row.summary, row.team, row.enabled, row.activeVersion, row.previousVersion,
                                 row.pendingVersion, row.latestVersion, row.latestNotes, row.latestURL, row.latestPublishedAt,
                                 row.lastChecked, row.failure, id])
        }
    }

    public func deletePlugin(_ id: String) throws {
        try queue.write { db in try db.execute(sql: "DELETE FROM plugin WHERE id = ?", arguments: [id]) }
    }

    // MARK: - Events

    public struct Event: Sendable {
        public var at: Date
        public var pluginID: String?
        public var version: String?
        public var kind: String
        public var message: String
    }

    public func record(_ kind: String, plugin: String? = nil, version: String? = nil, _ message: String) {
        try? queue.write { db in
            try db.execute(sql: "INSERT INTO event (at, plugin_id, version, kind, message) VALUES (?, ?, ?, ?, ?)",
                           arguments: [Date(), plugin, version, kind, message])
        }
    }

    public func events(plugin: String? = nil, limit: Int = 100) throws -> [Event] {
        try queue.read { db in
            let rows = if let plugin {
                try Row.fetchAll(db, sql: "SELECT * FROM event WHERE plugin_id = ? ORDER BY id DESC LIMIT ?", arguments: [plugin, limit])
            } else {
                try Row.fetchAll(db, sql: "SELECT * FROM event ORDER BY id DESC LIMIT ?", arguments: [limit])
            }
            return rows.reversed().map { Event(at: $0["at"], pluginID: $0["plugin_id"], version: $0["version"], kind: $0["kind"],
                                               message: $0["message"]) }
        }
    }

    // MARK: - Settings

    public func setting(_ key: String) throws -> String? {
        try queue.read { db in try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key]) }
    }

    public func setSetting(_ key: String, _ value: String?) throws {
        try queue.write { db in
            if let value {
                try db.execute(sql: "INSERT OR REPLACE INTO setting (key, value) VALUES (?, ?)", arguments: [key, value])
            } else {
                try db.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: [key])
            }
        }
    }

    // MARK: - Plugin stores (GPP-1 §3.6)

    public func storeGet(plugin: String, namespace: String, key: String) throws -> String? {
        try queue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM plugin_store WHERE plugin_id = ? AND namespace = ? AND key = ?",
                                arguments: [plugin, namespace, key])
        }
    }

    public func storePut(plugin: String, namespace: String, key: String, value: String) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO plugin_store (plugin_id, namespace, key, value, updated_at) VALUES (?, ?, ?, ?, ?)",
                           arguments: [plugin, namespace, key, value, Date()])
        }
    }

    public func storeDelete(plugin: String, namespace: String, key: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM plugin_store WHERE plugin_id = ? AND namespace = ? AND key = ?",
                           arguments: [plugin, namespace, key])
        }
    }

    /// Keys in order, after `after`, starting with `prefix`; `more` when the limit cut the list short.
    public func storeQuery(plugin: String, namespace: String, prefix: String?, after: String?, limit: Int) throws
        -> (items: [(key: String, value: String)], more: Bool)
    {
        try queue.read { db in
            var sql = "SELECT key, value FROM plugin_store WHERE plugin_id = ? AND namespace = ?"
            var arguments: StatementArguments = [plugin, namespace]
            if let prefix, !prefix.isEmpty {
                sql += " AND substr(key, 1, ?) = ?"
                _ = arguments.append(contentsOf: [prefix.count, prefix])
            }
            if let after {
                sql += " AND key > ?"
                _ = arguments.append(contentsOf: [after])
            }
            sql += " ORDER BY key LIMIT ?"
            _ = arguments.append(contentsOf: [limit + 1])
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            let items = rows.prefix(limit).map { (key: $0["key"] as String, value: $0["value"] as String) }
            return (Array(items), rows.count > limit)
        }
    }

    /// The store schema a plugin's data was last migrated to.
    public func storeSchema(plugin: String) throws -> (version: Int, migrations: [String])? {
        try queue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM plugin_store_schema WHERE plugin_id = ?", arguments: [plugin]) else {
                return nil
            }
            let migrations = (try? JSONDecoder().decode([String].self, from: Data((row["migrations"] as String).utf8))) ?? []
            return (row["schema_version"], migrations)
        }
    }

    public func setStoreSchema(plugin: String, version: Int, migrations: [String]) throws {
        let text = String(decoding: try JSONEncoder().encode(migrations), as: UTF8.self)
        try queue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO plugin_store_schema (plugin_id, schema_version, migrations) VALUES (?, ?, ?)",
                           arguments: [plugin, version, text])
        }
    }
}

/// The enabled set kept in gaea.sqlite (`ModelEnablement(store:)`), so no JSON file holds it.
public struct DatabaseEnablementStore: ModelEnablementStore {
    let database: GaeaDatabase

    public init(_ database: GaeaDatabase) { self.database = database }

    public func load() throws -> ModelEnablement.Choices {
        try database.queue.read { db in
            var choices = ModelEnablement.Choices()
            for row in try Row.fetchAll(db, sql: "SELECT * FROM model_choice") {
                let id: String = row["model_id"]
                if row["state"] as String == "enabled" {
                    choices.enabled.insert(id)
                    choices.accepted[id] = row["accepted_at"]
                } else {
                    choices.disabled.insert(id)
                }
            }
            return choices
        }
    }

    public func save(_ choices: ModelEnablement.Choices) throws {
        try database.queue.write { db in
            try db.execute(sql: "DELETE FROM model_choice")
            for id in choices.disabled {
                try db.execute(sql: "INSERT INTO model_choice (model_id, state) VALUES (?, 'disabled')", arguments: [id])
            }
            for id in choices.enabled {
                try db.execute(sql: "INSERT OR REPLACE INTO model_choice (model_id, state, accepted_at) VALUES (?, 'enabled', ?)",
                               arguments: [id, choices.accepted[id]])
            }
        }
    }
}
