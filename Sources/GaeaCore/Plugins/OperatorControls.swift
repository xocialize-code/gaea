import Foundation
import GaeaProtocol
import MESCore
import Synchronization

/// The memory budget, shared by the scheduler and the offers it decides: the operator can change it while Gaea runs.
public final class BudgetValue: Sendable {
    private let bytes: Mutex<UInt64>
    public init(_ bytes: UInt64) { self.bytes = Mutex(bytes) }
    public var value: UInt64 { bytes.withLock { $0 } }
    func set(_ value: UInt64) { bytes.withLock { $0 = value } }
}

/// What an operator narrows on a plugin's models, kept in gaea.sqlite (Gaea 1.5.0): lanes switched off, and caps on what
/// an offer takes. A preview server keeps to its quick work with them: Klein to 2048² instead of 4096², LTX to 5 s, a
/// model to its int4 lane.
///
/// - **Lanes off** are never chosen: not by default, not as a fallback, and a request that names one is refused. A model
///   with every lane off isn't offered. The default moves to the first lane left.
/// - **Caps** narrow the offer clients see (its MES `limits`) and the limits Gaea itself plans by (the manifest offer's),
///   to the smaller of the plugin's and the operator's. A request past a cap is refused like one past the plugin's own
///   limit. A cap never widens what a plugin offers.
public struct OperatorControls: Sendable {
    let database: GaeaDatabase

    public init(database: GaeaDatabase) { self.database = database }

    /// The caps an operator may set, by their MES limit names, and what each narrows in the manifest offer.
    public static let capFields: [String: String] = [
        "max_megapixels": "pixels of an image or a frame (the manifest's max_pixels)",
        "max_side": "an image's or a frame's longest side (max_width and max_height; the manifest's max_side)",
        "max_duration_s": "seconds of audio or video made (the manifest's max_seconds)",
        "max_frames": "frames of video made (the manifest's max_frames)",
        "max_count": "results in one job",
        "max_faces": "a mesh's faces",
        "max_texture_size": "a mesh's texture side",
        "max_text_chars": "characters of text to speak",
        "max_source_s": "seconds of a source video or audio",
        "max_layer_count": "layers of a decomposition",
    ]

    static func capsKey(plugin: String, model: String) -> String { "plugin:\(plugin):caps:\(model)" }
    static func lanesOffKey(plugin: String, model: String) -> String { "plugin:\(plugin):lanes_off:\(model)" }
    /// The gaea.sqlite setting for the operator's budget, in bytes.
    public static let budgetSetting = "memory.budget_bytes"

    // MARK: Reading and setting

    public func caps(plugin: String, model: String) -> [String: Double] {
        guard let text = (try? database.setting(Self.capsKey(plugin: plugin, model: model))) ?? nil,
              let caps = try? JSONDecoder().decode([String: Double].self, from: Data(text.utf8)) else { return [:] }
        return caps
    }

    /// Sets one cap (nil removes it).
    public func setCap(plugin: String, model: String, field: String, value: Double?) throws {
        var caps = caps(plugin: plugin, model: model)
        caps[field] = value
        let text = caps.isEmpty ? nil : String(decoding: try JSONEncoder().encode(caps), as: UTF8.self)
        try database.setSetting(Self.capsKey(plugin: plugin, model: model), text)
    }

    public func lanesOff(plugin: String, model: String) -> Set<String> {
        guard let text = (try? database.setting(Self.lanesOffKey(plugin: plugin, model: model))) ?? nil,
              let lanes = try? JSONDecoder().decode([String].self, from: Data(text.utf8)) else { return [] }
        return Set(lanes)
    }

    public func setLane(plugin: String, model: String, lane: String, on: Bool) throws {
        var off = lanesOff(plugin: plugin, model: model)
        if on { off.remove(lane) } else { off.insert(lane) }
        let text = off.isEmpty ? nil : String(decoding: try JSONEncoder().encode(off.sorted()), as: UTF8.self)
        try database.setSetting(Self.lanesOffKey(plugin: plugin, model: model), text)
    }

    /// The operator's budget, if one is kept.
    public var storedBudget: UInt64? { (try? database.setting(Self.budgetSetting)).flatMap { $0 }.flatMap(UInt64.init) }

    // MARK: Applying

    /// `model` without its switched-off lanes; the default moves to the first lane left when it was switched off.
    public func applying(to model: PluginManifest.Model, plugin: String) -> PluginManifest.Model {
        Self.applying(lanesOff: lanesOff(plugin: plugin, model: model.id), to: model)
    }

    public static func applying(lanesOff off: Set<String>, to model: PluginManifest.Model) -> PluginManifest.Model {
        guard !off.isEmpty else { return model }
        var model = model
        model.lanes = model.lanes.filter { !off.contains($0.id) }
        if !model.lanes.isEmpty, !model.lanes.contains(where: \.default) {
            for i in model.lanes.indices { model.lanes[i].default = i == 0 }
        }
        return model
    }

    /// An offer with `caps` applied: each MES limit the smaller of the plugin's and the operator's, and the manifest
    /// offer's limits Gaea plans by narrowed to match.
    public static func applying(_ caps: [String: Double], to manifestOffer: PluginManifest.Offer, offer: ModelOffer)
        -> (PluginManifest.Offer, ModelOffer)
    {
        guard !caps.isEmpty else { return (manifestOffer, offer) }
        func smaller(_ a: Double?, _ b: Double?) -> Double? {
            switch (a, b) {
            case let (a?, b?): min(a, b)
            case let (a?, nil): a
            case let (nil, b?): b
            default: nil
            }
        }
        var offer = offer
        var limits = offer.limits ?? Descriptor.Limits()
        for (field, cap) in caps {
            switch field {
            case "max_megapixels": limits.maxMegapixels = smaller(limits.maxMegapixels, cap)
            case "max_side":
                limits.maxWidth = smaller(limits.maxWidth.map(Double.init), cap).map { Int($0) }
                limits.maxHeight = smaller(limits.maxHeight.map(Double.init), cap).map { Int($0) }
            case "max_duration_s": limits.maxDurationSeconds = smaller(limits.maxDurationSeconds, cap)
            case "max_count": limits.maxCount = smaller(limits.maxCount.map(Double.init), cap).map { Int($0) }
            default: limits.profile[field] = smaller(limits.profile[field], cap)
            }
        }
        offer.limits = limits
        var manifestOffer = manifestOffer
        var model = manifestOffer.model.objectValue ?? [:]
        if let encoded = try? JSONDecoder().decode(GPPValue.self, from: JSONEncoder().encode(limits)) { model["limits"] = encoded }
        manifestOffer.model = .object(model)
        var planned = manifestOffer.limits ?? PluginManifest.Limits()
        func smallerInt(_ a: Int?, _ b: Double?) -> Int? { smaller(a.map(Double.init), b).map { Int($0) } }
        if let mp = caps["max_megapixels"] { planned.maxPixels = smallerInt(planned.maxPixels, (mp * 1_000_000).rounded(.down)) }
        if let side = caps["max_side"] { planned.maxSide = smallerInt(planned.maxSide, side) }
        if let seconds = caps["max_duration_s"] { planned.maxSeconds = smaller(planned.maxSeconds, seconds) }
        if let frames = caps["max_frames"] { planned.maxFrames = smallerInt(planned.maxFrames, frames) }
        if let layers = caps["max_layer_count"] { planned.maxLayerCount = smallerInt(planned.maxLayerCount, layers) }
        manifestOffer.limits = planned == PluginManifest.Limits() ? manifestOffer.limits : planned
        return (manifestOffer, offer)
    }
}
