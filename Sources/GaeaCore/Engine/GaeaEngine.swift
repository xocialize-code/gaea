import Foundation
import GaeaProtocol
import MESCore
import MESEngineCore
import MLXToolKit
import MockEngineCore

typealias MESValue = MESCore.JSONValue
typealias GPPValue = GaeaProtocol.JSONValue

extension GPPValue {
    /// The same JSON as MES's value type.
    var mes: MESValue { (try? MESValue(encoding: self)) ?? .null }
}

extension MESValue {
    var gpp: GPPValue { (try? GPPValue(encoding: self)) ?? .null }
}

/// A model an enabled plugin provides, as the normalizer offers it.
public struct PluginModelOffer: Sendable {
    public var plugin: InstalledPlugin
    public var model: PluginManifest.Model
    public var offer: ModelOffer
    /// The plugin operation that does the model's GPU work: its first helper, else its first offer.
    public var operation: String
    /// That operation's own params schema, from the manifest.
    public var params: GaeaProtocol.JSONValue?
}

/// Gaea's `MediaEngine`: what MESEngineKit serves (SRV-1). Plugins do the generating; this decides which plugin model
/// a request reaches, and the scheduler runs it.
///
/// **The G0 mock normalizer** (Plan §5 G0, AB-T-0355). The real image normalizer arrives in G1 (AB-T-0359). Until then,
/// every enabled plugin model is offered for `image.generate`: the run's GPU stage is the model's own plugin operation,
/// sent over GPP through the scheduler (one GPU job at a time, the ledger, lane choice), and the image itself comes from
/// MESKit's `MockImageEngine`, which follows the Image profile's rules. The worker's `effective` and warnings travel with
/// the result, under `effective.model_params["x-gaea.worker"]`. The operation's own options arrive as the request's
/// `x-` extension named after it (`extensionName`) and reach the worker as its `params`.
public struct GaeaEngine: MediaEngine {
    let manager: PluginManager
    let scheduler: Scheduler
    let enablement: ModelEnablement
    let pixels = MockImageEngine(steps: 1)

    /// The operation the mock normalizer offers.
    public static let mockOperation = "image.generate"
    /// The extension a request names a lane with (MEM-7, G-23).
    public static let laneExtension = "x-gaea.lane"

    public init(manager: PluginManager, scheduler: Scheduler, enablement: ModelEnablement) {
        self.manager = manager
        self.scheduler = scheduler
        self.enablement = enablement
    }

    /// Every model of every installed plugin, on or off, with the offer the normalizer makes for it.
    public func catalog() async -> [PluginModelOffer] {
        var offers: [PluginModelOffer] = []
        for plugin in await manager.installed() {
            for model in plugin.manifest.models {
                let helper = plugin.manifest.helpers?.first { $0.model == model.id }
                let manifestOffer = plugin.manifest.offers.first { $0.modelID == model.id }
                guard let operation = helper?.operation ?? manifestOffer?.operation else { continue }
                offers.append(PluginModelOffer(plugin: plugin, model: model, offer: Self.offer(model), operation: operation,
                                               params: helper?.params ?? manifestOffer?.params))
            }
        }
        return offers
    }

    static func offer(_ model: PluginManifest.Model) -> ModelOffer {
        let weights = model.package.license.weightLicense
        let permissive = weights.isPermissive
        let license = License(spdx: weights.identifier, commercialUse: permissive ? .yes : .no,
                              notice: weights.requiredDisplayText, acceptedRequired: permissive ? nil : true)
        let need = model.lanes.first(where: \.default).map(LaneChoice.need) ?? 0
        let memory: ModelOffer.MemoryClass = switch need {
        case ..<(4 << 30): .small
        case ..<(16 << 30): .medium
        case ..<(48 << 30): .large
        default: .xlarge
        }
        var offer = ModelOffer(id: model.id, title: model.title, license: license, memoryClass: memory, speedClass: .standard,
                               qualityTiers: [.draft, .standard, .best])
        offer.namedOnly = permissive ? nil : true
        offer.notes = "Gaea G0: the GPU stage runs on this plugin; the image is MESKit's mock (AB-T-0355)."
        return offer
    }

    /// The offers clients see: enabled plugins' enabled models. A research or otherwise restricted model is opt-in and
    /// named-only (PLG-11).
    func liveOffers() async -> [PluginModelOffer] {
        await catalog().filter { candidate in
            candidate.plugin.enabled && enablement.isEnabled(candidate.model.id, optIn: candidate.offer.namedOnly == true)
        }
    }

    public func descriptors() async -> [Descriptor] {
        let live = await liveOffers()
        guard !live.isEmpty,
              var descriptor = await pixels.descriptors().first(where: { $0.operation == Self.mockOperation }) else { return [] }
        var models = live.map(\.offer)
        if let first = models.firstIndex(where: { $0.namedOnly != true }) { models[first].isDefault = true }
        descriptor.models = models
        descriptor.summary = "Gaea G0's mock normalizer: the GPU stage runs on a plugin over GPP; the image is synthetic."
        let lanes = Array(Set(live.flatMap { $0.model.lanes.map(\.id) })).sorted()
        var extensions = [ExtensionSpec(name: Self.laneExtension, title: "Lane", schema: [
            "type": "string", "enum": .array(lanes.map { .string($0) }),
            "x-mes-ui": ["label": "Lane", "widget": "picker", "advanced": true,
                         "help": "Run this lane (quant) or refuse; without it Gaea picks the default lane, or a smaller one that fits."],
        ])]
        // Each plugin operation's own options travel as an `x-` extension named after it, unchanged (SRV-4, G-3).
        var seen: Set<String> = []
        for candidate in live where seen.insert(candidate.operation).inserted {
            guard let params = candidate.params, params["type"]?.stringValue == "object" else { continue }
            extensions.append(ExtensionSpec(name: Self.extensionName(candidate.operation), title: "\(candidate.plugin.title) options",
                                            schema: params.mes))
        }
        descriptor.extensions = extensions
        return [descriptor]
    }

    /// The MES extension that carries a plugin operation's options. MES names are `x-<vendor>.<name>` with one dot
    /// (Base §6.2), so `x-gaea.demo.matmul` travels as `x-gaea.demo_matmul`.
    public static func extensionName(_ operation: String) -> String {
        let parts = operation.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return operation }
        let name = parts[1].lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return "\(parts[0]).\(String(name))"
    }

    public func residentModels() async -> [String] { await scheduler.residentModels() }

    public func run(_ context: RunContext) async throws -> RunOutput {
        guard let target = await liveOffers().first(where: { $0.model.id == context.model.id }) else {
            throw MESError(.modelUnavailable, "\(context.model.id) isn't enabled.")
        }
        let named = context.extensions[Self.laneExtension]?.stringValue
        let job = WorkerJob(
            job: context.jobID, pluginID: target.plugin.id, model: target.model.id, operation: target.operation, namedLane: named,
            params: context.extensions[Self.extensionName(target.operation)]?.objectValue?.mapValues(\.gpp) ?? [:],
            seed: context.param("seed")?.intValue,
            outputDir: context.outputDirectory.appending(path: "worker", directoryHint: .isDirectory))
        let reporter = context.reporter
        let ran: WorkerJobResult
        do {
            ran = try await scheduler.run(job) { line in
                guard line["type"]?.stringValue == "progress" else { return }
                let step = line["step"]?.intValue, of = line["of"]?.intValue
                let stage = line["stage"]?.stringValue ?? "running"
                Task { await reporter.progress(.running, step: step, steps: of, fraction: line["fraction"]?.doubleValue, message: stage) }
            }
        } catch let refusal as LaneChoice.Refusal {
            switch refusal {
            case .unknownLane: throw MESError(.unsupportedParameter, refusal.description, param: Self.laneExtension)
            case .namedDoesNotFit, .nothingFits: throw MESError(.noCapacity, refusal.description)
            }
        } catch let failure as WorkerFailure {
            if failure.code == "cancelled" || Task.isCancelled { throw CancellationError() }
            throw MESError(.engineError, "\(target.plugin.title): \(failure.message)")
        } catch let refusal as PluginVerifier.Refusal {
            throw MESError(.modelUnavailable, refusal.description)
        }
        try Task.checkCancellation()

        var output = try await pixels.run(context)
        var worker: [String: MESValue] = [
            "plugin": .string(target.plugin.id), "version": .string(target.plugin.version), "lane": .string(ran.lane),
            "operation": .string(target.operation),
        ]
        if let effective = ran.result["effective"] { worker["effective"] = effective.mes }
        if let outputs = ran.result["outputs"] { worker["outputs"] = outputs.mes }
        if let seconds = ran.result["seconds"]?.doubleValue { worker["seconds"] = .number(seconds) }
        if ran.requeued { worker["requeued"] = true }
        output.effective["model_params"] = .object(["x-gaea.worker": .object(worker)])
        for warning in ran.result["warnings"]?.arrayValue ?? [] {
            if let code = warning["code"]?.stringValue, let message = warning["message"]?.stringValue {
                output.warnings.append(Warning(code: code, message: message, param: warning["param"]?.stringValue))
            }
        }
        if let message = ran.fallbackMessage {
            output.warnings.append(Warning(code: "lane_fallback", message: message, param: Self.laneExtension))
        }
        output.revisions[target.model.id] = target.plugin.version
        return output
    }
}
