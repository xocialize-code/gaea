import Foundation
import GaeaProtocol
import ImageIO
import MESCore
import MESEngineCore
import MLXToolKit
import PixelAgencyNormalizer
import Synchronization

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

/// A manifest offer Gaea serves as itself (GPP-1 §4.3, AB-T-0364): one model for one MES Image operation, run on its
/// plugin with the request's inputs and params, its images coming back from the spool.
public struct PluginRoute: Sendable {
    public var plugin: InstalledPlugin
    public var model: PluginManifest.Model
    public var manifestOffer: PluginManifest.Offer
    /// The MES offer clients see: the manifest's, kept named-only when the weights are restricted (PLG-11).
    public var offer: ModelOffer
    public var operation: String { manifestOffer.operation }

    /// The offer's own options: each `x-` property of its params is an MES extension of that name (Base §6.2).
    var extensions: [(name: String, schema: GPPValue)] {
        guard let properties = manifestOffer.params?["properties"]?.objectValue else { return [] }
        return properties.keys.sorted().filter { $0.hasPrefix("x-") }.map { ($0, properties[$0]!) }
    }
}

/// Gaea's `MediaEngine`: what MESEngineKit serves (SRV-1). Plugins do the generating; this decides which plugin model
/// a request reaches, and the scheduler runs it.
///
/// **The Image profile goes through the image normalizer** (pixel-agency-normalizer, AB-T-0366): it validates, chooses
/// the model by tier and content, plans the job and applies the profile's rules (sizes, masks kept exact, upright sRGB,
/// alpha, the seed). Its models are the enabled plugin models (`GaeaModelHost`), and each model call runs as that
/// plugin's offer of the capability's operation, whose worker does the model-specific mapping (Plan §3.3).
///
/// **An offer the normalizer doesn't serve runs as itself** (AB-T-0364): the request's inputs reach the worker as spool
/// paths, its params as `params`, the offer's `x-` extensions as `model_params`, and the files the worker writes under
/// `output_dir` become the job's outputs, moved rather than re-encoded.
///
/// Either way the worker's `effective` and warnings travel with the result, under
/// `effective.model_params["x-gaea.worker"]`.
public struct GaeaEngine: MediaEngine {
    let manager: PluginManager
    let scheduler: Scheduler
    let enablement: ModelEnablement
    let offers: PluginOffers
    let normalizer: ImageNormalizer

    /// The extension a request names a lane with (MEM-7, G-23).
    public static let laneExtension = "x-gaea.lane"

    public init(manager: PluginManager, scheduler: Scheduler, enablement: ModelEnablement) {
        self.manager = manager
        self.scheduler = scheduler
        self.enablement = enablement
        let offers = PluginOffers(manager: manager, enablement: enablement)
        self.offers = offers
        // Gaea's scheduler owns memory, so the host keeps the normalizer's residency hooks at their defaults.
        normalizer = ImageNormalizer(host: GaeaModelHost(offers: offers, scheduler: scheduler),
                                     options: .init(enablement: enablement))
    }
    /// Every model of every installed plugin, on or off, with the offer the console lists it under.
    public func catalog() async -> [PluginModelOffer] { await offers.catalog() }

    static func offer(_ model: PluginManifest.Model) -> ModelOffer { PluginOffers.offer(model) }

    /// Every installed plugin's offers of MES Image operations, on or off.
    public func routes() async -> [PluginRoute] { await offers.routes() }

    func liveRoutes() async -> [PluginRoute] { await offers.liveRoutes() }
    /// The normalizer's descriptors, from the enabled plugin models (`GaeaModelHost`), with what Gaea adds: each model's
    /// licence as its plugin's offer states it (a notice, its terms), the image count the offers allow, the lane
    /// extension (MEM-7), and the offers' own options as `x-` extensions (Base §6.2).
    public func descriptors() async -> [Descriptor] {
        let routes = await liveRoutes()
        var descriptors: [Descriptor] = []
        for var descriptor in await normalizer.descriptors() {
            let models = Set(descriptor.models.map(\.id))
            let served = routes.filter { models.contains($0.model.id) }
            for i in descriptor.models.indices {
                let id = descriptor.models[i].id
                if let route = served.first(where: { $0.model.id == id }) {
                    descriptor.models[i].license = route.offer.license
                }
                // The plugin's own say on the offer that runs this operation: named-only stays named-only (Z-Image's
                // image-to-image isn't an instruction editor), and is never the default.
                let runs = served.first { $0.model.id == id && $0.operation == descriptor.operation }
                    ?? served.first { $0.model.id == id && $0.operation == "image.edit" }
                if runs?.offer.namedOnly == true {
                    descriptor.models[i].namedOnly = true
                    descriptor.models[i].isDefault = nil
                }
            }
            if !descriptor.models.contains(where: { $0.isDefault == true }),
               let first = descriptor.models.firstIndex(where: { $0.namedOnly != true }) {
                descriptor.models[first].isDefault = true
            }
            let own = served.filter { $0.operation == descriptor.operation }
            if !own.isEmpty, let most = Self.maxImages(own.map(\.manifestOffer.limits)) {
                for i in descriptor.inputs.indices where descriptor.inputs[i].kind == .image { descriptor.inputs[i].max = most }
            }
            let lanes = Array(Set(served.flatMap { $0.allowedLanes.map(\.id) })).sorted()
            var extensions = descriptor.extensions ?? []
            var seen = Set(extensions.map(\.name))
            if !lanes.isEmpty, seen.insert(Self.laneExtension).inserted {
                extensions.append(ExtensionSpec(name: Self.laneExtension, title: "Lane", schema: [
                    "type": "string", "enum": .array(lanes.map { .string($0) }),
                    "x-mes-ui": ["label": "Lane", "widget": "picker", "advanced": true,
                                 "help": "Run this lane (quant) or refuse; without it Gaea picks the default lane, or a smaller one that fits."],
                ]))
            }
            for route in served {
                for (name, schema) in route.extensions where seen.insert(name).inserted {
                    let title = schema["x-mes-ui"]?["label"]?.stringValue ?? schema["title"]?.stringValue ?? name
                    extensions.append(ExtensionSpec(name: name, title: title, schema: schema.mes))
                }
            }
            descriptor.extensions = extensions.isEmpty ? nil : extensions
            descriptors.append(descriptor)
        }
        return descriptors
    }

    public func validate(_ request: JobRequest, descriptor: Descriptor) throws {
        try normalizer.validate(request, descriptor: descriptor)
    }

    public func defaultModel(for request: JobRequest, descriptor: Descriptor, kitChoice: ModelOffer,
                             candidates: [ModelOffer]) -> ModelOffer? {
        normalizer.defaultModel(for: request, descriptor: descriptor, kitChoice: kitChoice, candidates: candidates)
    }

    /// The descriptor's limits from its offers' (GPP-1 §4.3): the largest each offer allows, when every offer says.
    static func limits(_ offers: [PluginManifest.Limits?], else fallback: Descriptor.Limits?) -> Descriptor.Limits? {
        var limits = fallback ?? Descriptor.Limits()
        let sides = offers.map { $0?.maxSide }
        if !sides.isEmpty, sides.allSatisfy({ $0 != nil }) {
            limits.maxWidth = sides.compactMap(\.self).max()
            limits.maxHeight = limits.maxWidth
        }
        let pixels = offers.map { $0?.maxPixels }
        if !pixels.isEmpty, pixels.allSatisfy({ $0 != nil }) {
            limits.maxMegapixels = Double(pixels.compactMap(\.self).max()!) / 1_000_000
        }
        return limits
    }

    /// How many images an image input takes: the most any offer allows (`max_images`), when every offer says. MES
    /// refuses more at submit (`out_of_limits`); a model that takes fewer than another refuses the rest itself.
    static func maxImages(_ offers: [PluginManifest.Limits?]) -> Int? {
        let counts = offers.map { $0?.maxImages }
        guard !counts.isEmpty, counts.allSatisfy({ $0 != nil }) else { return nil }
        return counts.compactMap(\.self).max()
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
        if context.descriptor.profile == ImageProfile.id {
            let scope = NormalizerScope(jobID: context.jobID,
                                        directory: context.outputDirectory.appending(path: "worker", directoryHint: .isDirectory),
                                        extensions: context.extensions)
            defer { try? FileManager.default.removeItem(at: scope.directory) }
            var output = try await NormalizerScope.$current.withValue(scope) { try await normalizer.run(context) }
            Self.attach(scope.calls, to: &output)
            return output
        }
        guard let route = await liveRoutes().first(where: { $0.operation == context.operation && $0.model.id == context.model.id }) else {
            throw MESError(.modelUnavailable, "\(context.model.id) isn't enabled for \(context.operation).")
        }
        return try await run(route, context)
    }

    /// One plugin offer, run as itself.
    func run(_ route: PluginRoute, _ context: RunContext) async throws -> RunOutput {
        let workerDirectory = context.outputDirectory.appending(path: "worker", directoryHint: .isDirectory)
        let inputs = try Self.inputPaths(context.inputs, writingTextTo: context.outputDirectory.appending(path: "worker-inputs",
                                                                                                          directoryHint: .isDirectory))
        // The offer's defaults (GPP-1 §4.3) under what the request sent.
        var params = route.manifestOffer.defaults?.objectValue ?? [:]
        for (key, value) in context.params { params[key] = value.gpp }
        let names = Set(route.extensions.map(\.name))
        let modelParams = context.extensions.filter { names.contains($0.key) }.mapValues(\.gpp)
        let adapters: [GPPValue] = context.adapters.map { .object(["id": .string($0.id), "strength": .double($0.strength)]) }
        let job = WorkerJob(
            job: context.jobID, pluginID: route.plugin.id, model: route.model.id, operation: route.operation,
            namedLane: context.extensions[Self.laneExtension]?.stringValue, lanes: route.manifestOffer.lanes,
            params: params, inputs: inputs, modelParams: modelParams, adapters: adapters, seed: context.param("seed")?.intValue,
            outputDir: workerDirectory)

        let chunks = Mutex<[[String: GPPValue]]>([])
        let ran = try await schedule(job, title: route.plugin.title, context: context) { line in
            if line["type"]?.stringValue == "chunk" { chunks.withLock { $0.append(line) } }
        }
        let outputs = try Self.producedOutputs(result: ran.result, chunks: chunks.withLock { $0 }, workerDirectory: workerDirectory,
                                               outputDirectory: context.outputDirectory, specs: context.descriptor.outputs)
        let effective = ran.result["effective"]?.objectValue?.mapValues(\.mes) ?? [:]
        var output = RunOutput(outputs: outputs, effective: effective,
                               seed: effective["seed"]?.intValue ?? context.param("seed")?.intValue)
        Self.attach(ran, plugin: route.plugin, model: route.model.id, operation: route.operation, to: &output)
        return output
    }

    /// Runs a job through the scheduler, reporting the worker's progress, and turns its refusals into MES errors.
    func schedule(_ job: WorkerJob, title: String, context: RunContext,
                  onLine: @escaping @Sendable ([String: GPPValue]) -> Void = { _ in }) async throws -> WorkerJobResult {
        let reporter = context.reporter
        return try await Self.schedule(job, scheduler: scheduler, title: title) { line in
            onLine(line)
            guard line["type"]?.stringValue == "progress" else { return }
            let step = line["step"]?.intValue, of = line["of"]?.intValue
            let stage = line["stage"]?.stringValue ?? "running"
            Task { await reporter.progress(.running, step: step, steps: of, fraction: line["fraction"]?.doubleValue, message: stage) }
        }
    }

    /// Runs a job through the scheduler and turns its refusals into MES errors: a lane that doesn't fit is
    /// `no_capacity`, an unknown one `unsupported_parameter`, a worker's refusal of the request `invalid_request`.
    static func schedule(_ job: WorkerJob, scheduler: Scheduler, title: String,
                         onLine: @escaping @Sendable ([String: GPPValue]) -> Void) async throws -> WorkerJobResult {
        let ran: WorkerJobResult
        do {
            ran = try await scheduler.run(job, progress: onLine)
        } catch let refusal as LaneChoice.Refusal {
            switch refusal {
            case .unknownLane: throw MESError(.unsupportedParameter, refusal.description, param: Self.laneExtension)
            case .namedDoesNotFit, .nothingFits, .policy: throw MESError(.noCapacity, refusal.description)
            }
        } catch let failure as WorkerFailure {
            if failure.code == "cancelled" || Task.isCancelled { throw CancellationError() }
            if failure.code == "invalid_request" || failure.code == "unsupported_parameter" {
                throw MESError(.invalidRequest, "\(title): \(failure.message)")
            }
            throw MESError(.engineError, "\(title): \(failure.message)")
        } catch let refusal as PluginVerifier.Refusal {
            throw MESError(.modelUnavailable, refusal.description)
        }
        try Task.checkCancellation()
        return ran
    }

    /// The worker's side of the result: its `effective`, outputs and timing under `model_params["x-gaea.worker"]`, its
    /// warnings, a `lane_fallback` warning when a smaller lane ran (G-23), and the plugin version as the revision.
    static func attach(_ ran: WorkerJobResult, plugin: InstalledPlugin, model: String, operation: String, to output: inout RunOutput) {
        var worker: [String: MESValue] = [
            "plugin": .string(plugin.id), "version": .string(plugin.version), "lane": .string(ran.lane),
            "operation": .string(operation),
        ]
        if let effective = ran.result["effective"] { worker["effective"] = effective.mes }
        if let outputs = ran.result["outputs"] { worker["outputs"] = outputs.mes }
        if let seconds = ran.result["seconds"]?.doubleValue { worker["seconds"] = .number(seconds) }
        if ran.requeued { worker["requeued"] = true }
        var modelParams = output.effective["model_params"]?.objectValue ?? [:]
        modelParams["x-gaea.worker"] = .object(worker)
        output.effective["model_params"] = .object(modelParams)
        for warning in ran.result["warnings"]?.arrayValue ?? [] {
            if let code = warning["code"]?.stringValue, let message = warning["message"]?.stringValue {
                output.warnings.append(Warning(code: code, message: message, param: warning["param"]?.stringValue))
            }
        }
        if let message = ran.fallbackMessage {
            output.warnings.append(Warning(code: "lane_fallback", message: message, param: Self.laneExtension))
        }
        output.revisions[model] = plugin.version
    }

    /// The normalizer's model calls on the result: the first call's worker facts under `x-gaea.worker` (with `calls` and
    /// their seconds summed when there were several), the worker's `x-` options in `effective`, its warnings except
    /// `size_snapped` (the normalizer's sizes stand), a `lane_fallback` warning, and the plugin version as the revision.
    static func attach(_ calls: [NormalizerScope.Call], to output: inout RunOutput) {
        guard let first = calls.first else { return }
        for call in calls {
            var one = RunOutput(outputs: [], effective: [:])
            attach(call.ran, plugin: call.route.plugin, model: call.route.model.id, operation: call.route.operation, to: &one)
            for warning in one.warnings where warning.code != "size_snapped"
                && !output.warnings.contains(where: { $0.code == warning.code && $0.message == warning.message }) {
                output.warnings.append(warning)
            }
            for (model, revision) in one.revisions { output.revisions[model] = revision }
        }
        var worker = RunOutput(outputs: [], effective: [:])
        attach(first.ran, plugin: first.route.plugin, model: first.route.model.id, operation: first.route.operation, to: &worker)
        if var facts = worker.effective["model_params"]?.objectValue?["x-gaea.worker"]?.objectValue {
            if calls.count > 1 {
                facts["calls"] = .number(Double(calls.count))
                facts["seconds"] = .number(calls.compactMap { $0.ran.result["seconds"]?.doubleValue }.reduce(0, +))
            }
            var modelParams = output.effective["model_params"]?.objectValue ?? [:]
            modelParams["x-gaea.worker"] = .object(facts)
            output.effective["model_params"] = .object(modelParams)
            for (key, value) in facts["effective"]?.objectValue ?? [:] where key.hasPrefix("x-") && output.effective[key] == nil {
                output.effective[key] = value
            }
        }
    }

    // MARK: - Spool

    /// The request's inputs as GPP sends them, spool paths (GPP-1 §1): files stay where the kit put them; text and JSON
    /// are written to files of their own under `directory`, since media never travels in JSON.
    static func inputPaths(_ inputs: [String: [RunInput]], writingTextTo directory: URL) throws -> [String: GPPValue] {
        var paths: [String: GPPValue] = [:]
        for (name, values) in inputs.sorted(by: { $0.key < $1.key }) {
            var list: [GPPValue] = []
            for (i, value) in values.enumerated() {
                switch value {
                case .file(let url, _):
                    list.append(.string(url.path))
                case .text(let text):
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let url = directory.appending(path: "\(name)-\(i).txt")
                    try Data(text.utf8).write(to: url)
                    list.append(.string(url.path))
                case .data(let json):
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let url = directory.appending(path: "\(name)-\(i).json")
                    try JSONEncoder().encode(json).write(to: url)
                    list.append(.string(url.path))
                }
            }
            paths[name] = list.count == 1 ? list[0] : .array(list)
        }
        return paths
    }

    /// A worker's outputs as the job's (GPP-1 §3.3): the `result`'s, plus any `chunk` the result doesn't list again, in
    /// order. A file must lie under the run's `output_dir`; it is moved into the job's output folder, never re-encoded.
    /// A `value` is a `data` output.
    static func producedOutputs(result: [String: GPPValue], chunks: [[String: GPPValue]], workerDirectory: URL,
                                outputDirectory: URL, specs: [OutputSpec]) throws -> [ProducedOutput] {
        var entries = result["outputs"]?.arrayValue ?? []
        let listed = Set(entries.compactMap { $0["path"]?.stringValue })
        let streamed = chunks.filter { $0["path"]?.stringValue.map { !listed.contains($0) } ?? false }
            .sorted { ($0["output"]?.stringValue ?? "", $0["index"]?.intValue ?? 0) < ($1["output"]?.stringValue ?? "", $1["index"]?.intValue ?? 0) }
        entries += streamed.map { chunk in
            .object(["name": chunk["output"] ?? .null, "path": chunk["path"] ?? .null, "media_type": chunk["media_type"] ?? .null])
        }

        let root = workerDirectory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        var counts: [String: Int] = [:]
        var outputs: [ProducedOutput] = []
        for entry in entries {
            let name = entry["name"]?.stringValue ?? specs.first?.name ?? "output"
            if let value = entry["value"], entry["path"] == nil {
                outputs.append(.data(value.mes, name: name))
                continue
            }
            guard let path = entry["path"]?.stringValue else {
                throw MESError(.engineError, "The plugin returned an output with neither a path nor a value.")
            }
            let source = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            guard source.path.hasPrefix(root) else {
                throw MESError(.engineError, "The plugin wrote \(path), outside its output_dir.")
            }
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw MESError(.engineError, "The plugin listed \(path), which doesn't exist.")
            }
            let mediaType = entry["media_type"]?.stringValue ?? "application/octet-stream"
            let index = counts[name, default: 0]
            counts[name] = index + 1
            let target = outputDirectory.appending(path: "\(name)-\(index).\(source.pathExtension.isEmpty ? "bin" : source.pathExtension)")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: source, to: target)
            let kind = specs.first { $0.name == name }?.kind ?? (mediaType.hasPrefix("image/") ? .image
                : mediaType.hasPrefix("audio/") ? .audio : mediaType.hasPrefix("video/") ? .video : .data)
            let size = kind == .image || kind == .mask ? Self.pixelSize(target) : nil
            outputs.append(.file(target, name: name, kind: kind, mediaType: mediaType, width: size?.width, height: size?.height))
        }
        return outputs
    }

    /// An image's size from its header, without decoding it.
    static func pixelSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}

extension PluginRoute {
    /// The model's lanes this offer may run on (GPP-1 §4.3: all of them unless the offer names some).
    var allowedLanes: [PluginManifest.Lane] {
        guard let lanes = manifestOffer.lanes else { return model.lanes }
        return model.lanes.filter { lanes.contains($0.id) }
    }
}

/// The plugins' models and offers, on or off, as the engine and the normalizer's host read them.
struct PluginOffers: Sendable {
    let manager: PluginManager
    let enablement: ModelEnablement


    /// Every model of every installed plugin, on or off, with the offer the console lists it under.
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
        return offer
    }

    /// Every installed plugin's offers of MES Image operations, on or off. An offer whose `model` isn't a valid MES
    /// offer, or that names a model the plugin doesn't declare, is left out and logged by the validator at build time.
    public func routes() async -> [PluginRoute] {
        var routes: [PluginRoute] = []
        for plugin in await manager.installed() {
            for manifestOffer in plugin.manifest.offers {
                guard manifestOffer.profile == ImageProfile.id, ImageProfile.operations.operations[manifestOffer.operation] != nil,
                      let id = manifestOffer.modelID, let model = plugin.model(id),
                      var offer = try? JSONDecoder().decode(ModelOffer.self, from: JSONEncoder().encode(manifestOffer.model))
                else { continue }
                if Self.offer(model).namedOnly == true { offer.namedOnly = true }
                routes.append(PluginRoute(plugin: plugin, model: model, manifestOffer: manifestOffer, offer: offer))
            }
        }
        return routes
    }

    func isLive(_ plugin: InstalledPlugin, _ model: PluginManifest.Model) -> Bool {
        plugin.enabled && enablement.isEnabled(model.id, optIn: Self.offer(model).namedOnly == true)
    }

    func liveRoutes() async -> [PluginRoute] {
        await routes().filter { isLive($0.plugin, $0.model) }
    }
}
