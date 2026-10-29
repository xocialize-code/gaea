import Foundation
import MESCore
import Synchronization

/// The adapters (LoRAs) chosen for the next run of each operation (Base §6.3), which `EnginePool` puts on a request that
/// names none. MESFormsUI renders the descriptor's params and extensions but not its adapters, so Gaea Lab keeps them
/// here: the LoRA panel and `lab-run --adapter` write them.
public final class AdapterChoices: Sendable {
    private let chosen = Mutex<[String: [AdapterRequest]]>([:])

    public init() {}

    public func adapters(for operation: String) -> [AdapterRequest] { chosen.withLock { $0[operation] ?? [] } }

    public func set(_ adapters: [AdapterRequest], for operation: String) { chosen.withLock { $0[operation] = adapters } }

    /// Adds `id` (or changes its strength); nil takes it off.
    public func choose(_ id: String, strength: Double?, on: Bool, for operation: String) {
        chosen.withLock { all in
            var list = all[operation] ?? []
            list.removeAll { $0.id == id }
            if on { list.append(AdapterRequest(id: id, strength: strength)) }
            all[operation] = list
        }
    }

    /// For `EnginePool(adapters:)`.
    public var provider: @Sendable (JobRequest) -> [AdapterRequest]? {
        { [self] request in
            let list = adapters(for: request.operation)
            return list.isEmpty ? nil : list
        }
    }

    /// The adapters a descriptor offers on `model` (or on every model, for automatic choice), each with its model.
    public static func offered(by descriptor: Descriptor, model: String?) -> [(model: String, adapter: AdapterOffer)] {
        descriptor.models.filter { model == nil || $0.id == model }
            .flatMap { offer in (offer.adapters ?? []).map { (offer.id, $0) } }
    }
}
