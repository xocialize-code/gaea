import Foundation
import GaeaProtocol
import MESCore
import PixelAgencyNormalizer

/// One adapter a plugin model takes (GPP-1 §4.3, §4.8): shipped in the plugin's manifest, or registered by the operator
/// by Hugging Face URL. The card is what the normalizer offers and checks; the rest is what the worker is sent.
struct ModelAdapter: Sendable {
    var card: ModelCard.Adapter
    var format: String
    var source: PluginManifest.AdapterSource
    /// The operator added it (gaea.sqlite), rather than the plugin shipping it.
    var registered: Bool

    /// One `run.adapters` item (GPP-1 §3.3): the request's id and strength, an `ic` adapter's images, and the kind,
    /// format and source the worker fetches and applies.
    func runItem(strength: Double, inputs: [String: GPPValue] = [:]) -> GPPValue {
        var item: [String: GPPValue] = [
            "id": .string(card.id), "strength": .double(strength), "kind": .string(card.kind), "format": .string(format),
            "source": .object([
                "repo": .string(source.repo), "revision": .string(source.revision), "file": .string(source.file),
                "sha256": .string(source.sha256),
            ].merging(source.bytes.map { ["bytes": .int(Int64($0))] } ?? [:]) { a, _ in a }),
        ]
        if !inputs.isEmpty { item["inputs"] = .object(inputs) }
        return .object(item)
    }
}

extension PluginOffers {
    /// The adapters one plugin model takes, given its offers (`routes`, all of the same plugin model) and the operator's
    /// registrations. A shipped adapter applies to the offers that list it; a registered one to the offers whose
    /// `adapter_support` takes its kind and format.
    static func adapters(_ routes: [PluginRoute], registrations: [GaeaDatabase.AdapterRow]) -> [ModelAdapter] {
        var byID: [String: ModelAdapter] = [:]
        var order: [String] = []
        func add(_ adapter: ModelAdapter, _ capability: ModelCapability) {
            if var known = byID[adapter.card.id] {
                if !known.card.capabilities.contains(capability) { known.card.capabilities.append(capability) }
                byID[adapter.card.id] = known
            } else {
                var adapter = adapter
                adapter.card.capabilities = [capability]
                byID[adapter.card.id] = adapter
                order.append(adapter.card.id)
            }
        }
        for route in routes {
            guard let capability = GaeaModelHost.capabilities[route.operation] else { continue }
            let metas = route.manifestOffer.adapterMetas
            for offer in route.offer.adapters ?? [] {
                guard let meta = metas[offer.id] else { continue }
                add(Self.shipped(offer, meta), capability)
            }
            guard let support = route.manifestOffer.adapterSupport else { continue }
            for row in registrations where row.modelID == route.model.id
                && support.formats.contains(row.format) && support.kinds.contains(row.kind) {
                add(Self.registered(row), capability)
            }
        }
        return order.compactMap { byID[$0] }
    }

    static func shipped(_ offer: AdapterOffer, _ meta: PluginManifest.AdapterMeta) -> ModelAdapter {
        let use: String = switch offer.license.commercialUse {
        case .yes: offer.license.notice == nil ? "allowed" : "conditional"
        case .no: "prohibited"
        default: "unknown"
        }
        let card = ModelCard.Adapter(
            id: offer.id, title: offer.title, kind: offer.kind.rawValue, capabilities: [], trigger: meta.trigger,
            promptTemplate: meta.promptTemplate, license: offer.license.spdx, commercialUse: use,
            licenseGated: offer.license.acceptedRequired == true, notice: offer.license.notice, licenseURL: offer.license.termsURL,
            defaultStrength: offer.strength.defaultValue, strengthMin: offer.strength.min, strengthMax: offer.strength.max,
            conditioning: (offer.slots ?? []).map { .init(role: $0.role, media: $0.kind.rawValue, required: $0.isRequired, note: $0.notes) },
            status: meta.status ?? "verified", bytes: (meta.bytes ?? meta.source.bytes).map(UInt64.init))
        return ModelAdapter(card: card, format: meta.format, source: meta.source, registered: false)
    }

    static func registered(_ row: GaeaDatabase.AdapterRow) -> ModelAdapter {
        let card = ModelCard.Adapter(
            id: row.id, title: row.title, kind: row.kind, capabilities: [], trigger: row.trigger, promptTemplate: row.promptTemplate,
            license: row.license, commercialUse: row.commercialUse, licenseGated: row.licenseGated, notice: row.notes,
            licenseURL: row.licenseURL, defaultStrength: row.strengthDefault, strengthMin: row.strengthMin,
            strengthMax: row.strengthMax, status: "operator", bytes: row.bytes.map(UInt64.init))
        return ModelAdapter(card: card, format: row.format,
                            source: .init(repo: row.repo, revision: row.revision, file: row.file, sha256: row.sha256, bytes: row.bytes),
                            registered: true)
    }

    /// The operator's registrations; none when the database can't be read.
    func registrations() -> [GaeaDatabase.AdapterRow] { (try? manager.database.adapters()) ?? [] }
}
