import Foundation
import GRDB

/// LoRAs the operator added by Hugging Face repo URL (GPP-1 §4.8, AB-T-0378).
extension GaeaDatabase {
    public struct AdapterRow: Sendable, Equatable, Codable {
        public var id: String
        /// The Gaea model it was added for.
        public var modelID: String
        public var title: String
        /// `plain` or `ic`.
        public var kind: String
        /// `diffusers-peft`, `kohya`, `bfl-fused`, …
        public var format: String
        public var repo: String
        /// A 40-hex commit.
        public var revision: String
        public var file: String
        public var sha256: String
        public var bytes: Int?
        public var trigger: String?
        public var promptTemplate: String?
        /// An SPDX id, or `NOASSERTION`.
        public var license: String
        /// `allowed`, `conditional`, `prohibited` or `unknown`.
        public var commercialUse: String
        public var licenseGated: Bool
        public var licenseURL: String?
        public var notes: String?
        public var strengthDefault: Double
        public var strengthMin: Double?
        public var strengthMax: Double?
        public var addedAt: Date

        public init(id: String, modelID: String, title: String, kind: String = "plain", format: String, repo: String,
                    revision: String, file: String, sha256: String, bytes: Int? = nil, trigger: String? = nil,
                    promptTemplate: String? = nil, license: String, commercialUse: String, licenseGated: Bool = false,
                    licenseURL: String? = nil, notes: String? = nil, strengthDefault: Double = 1, strengthMin: Double? = nil,
                    strengthMax: Double? = nil, addedAt: Date = Date()) {
            self.id = id; self.modelID = modelID; self.title = title; self.kind = kind; self.format = format; self.repo = repo
            self.revision = revision; self.file = file; self.sha256 = sha256; self.bytes = bytes; self.trigger = trigger
            self.promptTemplate = promptTemplate; self.license = license; self.commercialUse = commercialUse
            self.licenseGated = licenseGated; self.licenseURL = licenseURL; self.notes = notes
            self.strengthDefault = strengthDefault; self.strengthMin = strengthMin; self.strengthMax = strengthMax
            self.addedAt = addedAt
        }

        init(_ row: Row) {
            id = row["id"]; modelID = row["model_id"]; title = row["title"]; kind = row["kind"]; format = row["format"]
            repo = row["repo"]; revision = row["revision"]; file = row["file"]; sha256 = row["sha256"]; bytes = row["bytes"]
            trigger = row["trigger"]; promptTemplate = row["prompt_template"]; license = row["license"]
            commercialUse = row["commercial_use"]; licenseGated = row["license_gated"]; licenseURL = row["license_url"]
            notes = row["notes"]; strengthDefault = row["strength_default"]; strengthMin = row["strength_min"]
            strengthMax = row["strength_max"]; addedAt = row["added_at"]
        }
    }

    public func adapters() throws -> [AdapterRow] {
        try queue.read { db in try Row.fetchAll(db, sql: "SELECT * FROM adapter ORDER BY model_id, id").map(AdapterRow.init) }
    }

    public func adapter(_ id: String) throws -> AdapterRow? {
        try queue.read { db in try Row.fetchOne(db, sql: "SELECT * FROM adapter WHERE id = ?", arguments: [id]).map(AdapterRow.init) }
    }

    /// Adds a registration, or replaces the one with the same id.
    public func saveAdapter(_ a: AdapterRow) throws {
        try queue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO adapter (id, model_id, title, kind, format, repo, revision, file, sha256, bytes, trigger,
                    prompt_template, license, commercial_use, license_gated, license_url, notes, strength_default, strength_min,
                    strength_max, added_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [a.id, a.modelID, a.title, a.kind, a.format, a.repo, a.revision, a.file, a.sha256, a.bytes,
                                 a.trigger, a.promptTemplate, a.license, a.commercialUse, a.licenseGated, a.licenseURL, a.notes,
                                 a.strengthDefault, a.strengthMin, a.strengthMax, a.addedAt])
        }
    }

    /// Removes a registration and its enablement. The weights stay in the models root.
    public func deleteAdapter(_ id: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM adapter WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM model_choice WHERE model_id = ?", arguments: ["adapter:\(id)"])
        }
    }
}
