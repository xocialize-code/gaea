import Foundation
import GaeaProtocol
import MESEngineCore
import PixelAgencyNormalizer

/// The operator's side of adapters (GPP-1 §4.8, AB-T-0378): LoRAs added by Hugging Face repo URL for one of the
/// server's models, listed with the adapters plugins ship, and switched on or off.
extension GaeaEngine {
    /// One adapter as the operator lists it.
    public struct AdapterListing: Sendable, Codable {
        public var id: String
        public var title: String
        public var model: String
        public var operations: [String]
        public var kind: String
        public var format: String
        public var license: String
        public var commercialUse: String
        public var status: String
        /// Added by the operator, rather than shipped by the plugin.
        public var registered: Bool
        public var optIn: Bool
        public var enabled: Bool
        public var trigger: String?
        public var repo: String
        public var revision: String
        public var file: String
        public var bytes: Int?
    }

    /// Every adapter of every installed plugin model, shipped or registered, on or off.
    public func adapterListings() async -> [AdapterListing] {
        let registrations = offers.registrations()
        var listings: [AdapterListing] = []
        let routes = await offers.routes()
        for (_, group) in Dictionary(grouping: routes, by: { "\($0.plugin.id)/\($0.model.id)" }).sorted(by: { $0.key < $1.key }) {
            guard let model = group.first?.model else { continue }
            for adapter in PluginOffers.adapters(group, registrations: registrations) {
                let optIn = Adapters.isOptIn(adapter.card)
                let operations = adapter.card.capabilities.compactMap { GaeaModelHost.operations[$0] }.sorted()
                listings.append(AdapterListing(
                    id: adapter.card.id, title: adapter.card.title, model: model.id, operations: operations, kind: adapter.card.kind,
                    format: adapter.format, license: adapter.card.license, commercialUse: adapter.card.commercialUse,
                    status: adapter.card.status, registered: adapter.registered, optIn: optIn,
                    enabled: enablement.isEnabled(Adapters.key(adapter.card.id), optIn: optIn) && !Adapters.isRefused(adapter.card),
                    trigger: adapter.card.trigger, repo: adapter.source.repo, revision: adapter.source.revision,
                    file: adapter.source.file, bytes: adapter.source.bytes))
            }
        }
        // A registration whose model is gone, or no longer takes its format, is still listed, as off.
        for row in registrations where !listings.contains(where: { $0.id == row.id }) {
            listings.append(AdapterListing(
                id: row.id, title: row.title, model: row.modelID, operations: [], kind: row.kind, format: row.format,
                license: row.license, commercialUse: row.commercialUse, status: "operator", registered: true, optIn: true,
                enabled: false, trigger: row.trigger, repo: row.repo, revision: row.revision, file: row.file, bytes: row.bytes))
        }
        return listings
    }

    public struct AdapterError: Error, CustomStringConvertible {
        public let description: String
        init(_ text: String) { description = text }
    }

    /// What the operator may say about a LoRA beyond its URL; the hub's card fills the rest.
    public struct AdapterRequest: Sendable {
        public var url: String
        public var model: String
        public var file: String?
        public var id: String?
        public var title: String?
        public var trigger: String?
        public var format: String?
        public var strength: Double?
        public var notes: String?

        public init(url: String, model: String, file: String? = nil, id: String? = nil, title: String? = nil,
                    trigger: String? = nil, format: String? = nil, strength: Double? = nil, notes: String? = nil) {
            self.url = url; self.model = model; self.file = file; self.id = id; self.title = title; self.trigger = trigger
            self.format = format; self.strength = strength; self.notes = notes
        }
    }

    /// Adds a LoRA by its Hugging Face repo URL for `request.model` (GPP-1 §4.8): pins the revision, takes the file's
    /// sha256 and size from the hub, reads the licence from the card, and checks that the model takes its format. The
    /// weights are fetched by the worker, into the models root, on first use.
    public func registerAdapter(_ request: AdapterRequest) async throws -> GaeaDatabase.AdapterRow {
        guard var reference = HuggingFaceAdapter.Reference(request.url) else {
            throw AdapterError("\(request.url) isn't a Hugging Face model repo URL (https://huggingface.co/owner/repo).")
        }
        if let file = request.file { reference.file = file }
        let routes = await offers.routes().filter { $0.model.id == request.model }
        guard !routes.isEmpty else { throw AdapterError("No installed plugin has a model \(request.model).") }
        let supports = routes.compactMap(\.manifestOffer.adapterSupport)
        guard let support = supports.first else {
            let takers = Set(await offers.routes().filter { $0.manifestOffer.adapterSupport != nil }.map(\.model.id)).sorted()
            throw AdapterError("\(request.model) takes no adapters." + (takers.isEmpty ? "" : " These do: \(takers.joined(separator: ", "))."))
        }
        let hub = try await HuggingFaceAdapter.resolve(reference)
        guard let format = request.format ?? hub.format else {
            throw AdapterError("\(hub.file)'s tensor names don't say its format; pass --format (\(support.formats.joined(separator: ", "))).")
        }
        guard supports.contains(where: { $0.formats.contains(format) && $0.kinds.contains("plain") }) else {
            throw AdapterError("\(request.model) takes \(support.formats.joined(separator: ", ")) adapters, and \(hub.file) is \(format).")
        }
        let id = request.id ?? "\(support.baseModel):\(Self.slug(hub.repo.split(separator: "/").last.map(String.init) ?? hub.repo))"
        let existing = PluginOffers.adapters(routes, registrations: [])
        guard !existing.contains(where: { $0.card.id == id }) else {
            throw AdapterError("\(request.model)'s plugin already ships an adapter \(id); pass --id to name this one.")
        }
        if let other = try manager.database.adapter(id), other.repo != hub.repo || other.modelID != request.model {
            throw AdapterError("\(id) is already \(other.repo) for \(other.modelID); pass --id to name this one.")
        }
        if let strength = request.strength, !(support.strength.min...support.strength.max).contains(strength) {
            throw AdapterError("\(request.model) applies strengths \(support.strength.min) to \(support.strength.max).")
        }
        let row = GaeaDatabase.AdapterRow(
            id: id, modelID: request.model, title: request.title ?? hub.repo.split(separator: "/").last.map(String.init) ?? id,
            kind: "plain", format: format, repo: hub.repo, revision: hub.revision, file: hub.file, sha256: hub.sha256,
            bytes: hub.bytes, trigger: request.trigger ?? hub.trigger, license: hub.license, commercialUse: hub.commercialUse,
            licenseGated: hub.licenseGated, licenseURL: hub.licenseURL, notes: request.notes,
            strengthDefault: request.strength ?? 1, strengthMin: support.strength.min, strengthMax: support.strength.max)
        try manager.database.saveAdapter(row)
        manager.database.record("adapter", plugin: routes[0].plugin.id, version: nil,
                                "\(id): \(hub.repo)@\(hub.revision.prefix(12)) \(hub.file) for \(request.model), \(hub.license)")
        return row
    }

    /// Removes a registration. A shipped adapter can't be removed, only switched off.
    public func removeAdapter(_ id: String) throws {
        guard try manager.database.adapter(id) != nil else {
            throw AdapterError("\(id) isn't an adapter the operator added; a plugin's own adapters can only be switched off.")
        }
        try manager.database.deleteAdapter(id)
    }

    /// Switches an adapter on or off for clients. An opt-in one (unknown, research or gated terms, or not yet judged)
    /// starts off, and switching it on accepts its terms.
    public func setAdapter(_ id: String, enabled: Bool) async throws {
        guard let listing = await adapterListings().first(where: { $0.id == id }) else { throw AdapterError("No adapter \(id).") }
        try enablement.set(Adapters.key(id), enabled: enabled, optIn: listing.optIn)
    }

    static func slug(_ text: String) -> String {
        let lowered = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(lowered).split(separator: "-").joined(separator: "-")
    }
}
