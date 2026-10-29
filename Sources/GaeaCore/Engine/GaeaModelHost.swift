import CoreGraphics
import Foundation
import GaeaProtocol
import ImageIO
import MESCore
import MESEngineCore
import PixelAgencyNormalizer
import Synchronization
import UniformTypeIdentifiers

/// The image normalizer's models (AB-T-0366, Plan §3.3): every enabled plugin model that offers an MES Image operation.
/// The normalizer (pixel-agency-normalizer) validates, chooses the model, plans the job and applies the Image profile's
/// rules; each model call it makes runs as the plugin's offer of that capability's operation, whose worker does the
/// model-specific mapping. One `ModelCard` per plugin model, with what its offers say: capabilities, licence, envelope.
struct GaeaModelHost: ModelHost {
    let offers: PluginOffers
    let scheduler: Scheduler

    /// The operation whose plugin offer serves each capability.
    static let operations: [ModelCapability: String] = [
        .textToImage: "image.generate", .imageEdit: "image.edit", .imageInpaint: "image.fill",
        .imageUpscale: "image.upscale", .imageRestore: "image.restore", .imageRelight: "image.relight",
        .imageColorize: "image.colorize", .matting: "image.matte", .promptSegment: "image.segment",
        .imageAnalysis: "image.describe", .imageQualityScore: "image.score",
    ]
    static let capabilities = Dictionary(uniqueKeysWithValues: operations.map { ($0.value, $0.key) })
    /// The helper a plugin serves defect detection as (restore's scratches, then inpainting): Gaea calls it, and never
    /// offers it to clients (GPP-1 §4.4).
    static let defectsHelper = "x-gaea.image.defects"
    /// The text input an operation takes the model call's `prompt` as.
    static let textInputs = ["image.generate": "prompt", "image.edit": "instruction", "image.fill": "prompt",
                             "image.describe": "question"]

    func models() async -> [ModelCard] {
        let routes = await offers.liveRoutes()
        let registrations = offers.registrations()
        var cards: [ModelCard] = []
        for (key, group) in Dictionary(grouping: routes, by: { "\($0.plugin.id)/\($0.model.id)" }).sorted(by: { $0.key < $1.key }) {
            _ = key
            guard let first = group.first else { continue }
            cards.append(Self.card(first, all: group, adapters: PluginOffers.adapters(group, registrations: registrations)))
        }
        // The helpers' models: the prompt enhancer's backbones, routed as `llm`, and the defect detector.
        for helper in await offers.liveHelpers() {
            guard let capability = Self.helperCapabilities[helper.helper.operation] else { continue }
            if !cards.contains(where: { $0.id == helper.model.id }) { cards.append(Self.helperCard(helper, capability)) }
        }
        return cards
    }

    /// The capability each helper Gaea calls serves.
    static let helperCapabilities: [String: ModelCapability] = [GaeaPromptEnhancer.operation: .llm, defectsHelper: .defectDetect]

    static func backboneCard(_ helper: PluginOffers.Helper) -> ModelCard { helperCard(helper, .llm) }

    static func helperCard(_ helper: PluginOffers.Helper, _ capability: ModelCapability) -> ModelCard {
        let license = PluginOffers.offer(helper.model).license
        let lane = helper.model.lanes.first(where: \.default) ?? helper.model.lanes.first
        return ModelCard(
            id: helper.model.id, displayName: helper.model.title, capabilities: [capability], maturity: .prod,
            license: .init(license.commercialUse == .yes ? .permissive : .restricted, weights: [license.spdx]),
            sourceRepo: helper.model.sourceRepo, revision: helper.plugin.version,
            envelope: .init(maxPixels: capability == .llm ? 1 : 4096 * 4096, multipleOf: 1, maxInputs: capability == .llm ? 0 : 1),
            footprintBytes: lane?.resolved.persistentBytes, downloaded: true)
    }

    static func card(_ route: PluginRoute, all: [PluginRoute], adapters: [ModelAdapter] = []) -> ModelCard {
        let capabilities = all.compactMap { capabilities[$0.operation] }
        let license = route.offer.license
        let limits = all.compactMap(\.manifestOffer.limits)
        let envelope = ModelCard.Envelope(maxPixels: limits.compactMap(\.maxPixels).max() ?? 1024 * 1024,
                                          multipleOf: limits.compactMap(\.sizeMultiple).max() ?? 16,
                                          maxInputs: limits.compactMap(\.maxImages).max() ?? 1)
        let defaultLane = route.model.lanes.first(where: \.default) ?? route.model.lanes.first
        return ModelCard(
            id: route.model.id, displayName: route.model.title, capabilities: capabilities, maturity: .prod,
            license: .init(license.commercialUse == .yes ? .permissive : .restricted, weights: [license.spdx]),
            sourceRepo: route.model.sourceRepo, revision: route.plugin.version, envelope: envelope,
            defaults: .init(steps: param(all, suffix: ".steps")?.intValue, guidance: param(all, suffix: ".guidance")?.doubleValue),
            footprintBytes: defaultLane?.resolved.persistentBytes, downloaded: true, adapters: adapters.map(\.card))
    }

    /// What the offer's surface accepts of adapters (GPP-1 §4.3), in the normalizer's terms.
    static func adapterSupport(_ route: PluginRoute) -> ModelRoute.AdapterSupport? {
        guard let support = route.manifestOffer.adapterSupport else { return nil }
        return .init(kinds: support.kinds, maxCount: support.maxCount, strengthMin: support.strength.min,
                     strengthMax: support.strength.max)
    }

    /// The default of the offers' first `x-` param named `….suffix` (a plugin's steps, its guidance).
    static func param(_ routes: [PluginRoute], suffix: String) -> GPPValue? {
        for route in routes {
            guard let properties = route.manifestOffer.params?["properties"]?.objectValue else { continue }
            if let key = properties.keys.sorted().first(where: { $0.hasSuffix(suffix) }), let value = properties[key]?["default"] {
                return value
            }
        }
        return nil
    }

    func route(_ capability: ModelCapability, model: String?) async throws -> ModelRoute {
        if let operation = Self.helperCapabilities.first(where: { $0.value == capability })?.key {
            let helpers = await offers.liveHelpers().filter { $0.helper.operation == operation }
            guard let helper = helpers.first(where: { model == nil || $0.model.id == model }) else {
                throw MESError(.modelUnavailable, capability == .llm ? "No prompt enhancer backbone \(model ?? "") is enabled."
                                                                     : "No plugin model serves \(operation).")
            }
            let card = Self.helperCard(helper, capability)
            return ModelRoute(id: card.id, packageID: "\(helper.plugin.id)/\(helper.model.id)", capability: capability,
                              displayName: card.displayName, license: card.license, envelope: card.envelope,
                              revision: helper.plugin.version, footprintBytes: card.footprintBytes)
        }
        guard let operation = Self.operations[capability] else {
            throw MESError(.modelUnavailable, "No plugin serves \(capability).")
        }
        let routes = await offers.liveRoutes().filter { $0.operation == operation }
        let chosen: PluginRoute?
        if let model {
            chosen = routes.first { $0.model.id == model }
        } else {
            chosen = routes.first { $0.offer.isDefault == true && $0.offer.namedOnly != true } ?? routes.first { $0.offer.namedOnly != true }
        }
        guard let chosen else {
            throw MESError(.modelUnavailable, model.map { "\($0) isn't enabled for \(operation)." } ?? "No plugin model offers \(operation).")
        }
        let all = await offers.liveRoutes().filter { $0.plugin.id == chosen.plugin.id && $0.model.id == chosen.model.id }
        let adapters = PluginOffers.adapters(all, registrations: offers.registrations())
        let card = Self.card(chosen, all: all, adapters: adapters)
        return ModelRoute(id: card.id, packageID: "\(chosen.plugin.id)/\(chosen.model.id)", capability: capability,
                          displayName: card.displayName, license: card.license, envelope: card.envelope, defaults: card.defaults,
                          revision: chosen.plugin.version, footprintBytes: card.footprintBytes,
                          adapterSupport: Self.adapterSupport(chosen),
                          adapterRevisions: Dictionary(adapters.map { ($0.card.id, $0.source.revision) }) { a, _ in a })
    }

    /// Nothing to do ahead of the run: the scheduler admits and prepares the lane when the job reaches the worker.
    func prepare(_ route: ModelRoute, progress: @escaping @Sendable (ModelProgress) -> Void) async throws {}

    func run(_ work: ModelWork, progress: @escaping @Sendable (ModelProgress) -> Void) async throws -> ModelResult {
        let call: Callee
        if let operation = Self.operations[work.route.capability],
           let route = await offers.liveRoutes().first(where: { $0.operation == operation && $0.model.id == work.route.id }) {
            call = Callee(route)
        } else if work.route.capability != .llm,
                  let operation = Self.helperCapabilities.first(where: { $0.value == work.route.capability })?.key,
                  let helper = await offers.liveHelpers().first(where: { $0.helper.operation == operation && $0.model.id == work.route.id }) {
            call = Callee(helper)
        } else {
            throw MESError(.modelUnavailable, "\(work.route.id) isn't enabled for \(work.route.capability).")
        }
        let operation = call.operation
        let scope = NormalizerScope.current ?? NormalizerScope(jobID: "job_\(UUID().uuidString.prefix(8).lowercased())",
                                                                 directory: FileManager.default.temporaryDirectory, extensions: [:])
        let index = scope.nextCall()
        let directory = scope.directory.appending(path: "worker-\(index)", directoryHint: .isDirectory)
        let inputDirectory = directory.appending(path: "inputs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Inputs travel as spool paths (GPP-1 §1): images as the PNGs the normalizer made, the prompt as a text file.
        // An `ic` adapter's images (`adapter<n>.<role>`) travel with the adapter instead (GPP-1 §3.3).
        var inputs: [String: GPPValue] = [:]
        // An input with no images is left out, not sent empty: an ic edit whose images all fill the adapter's slots has
        // none of its own (IMAGE-013).
        for (name, images) in work.inputs.sorted(by: { $0.key < $1.key }) where !images.isEmpty {
            var paths: [GPPValue] = []
            for (i, image) in images.enumerated() {
                let url = inputDirectory.appending(path: "\(name)-\(i).\(image.format == .jpeg ? "jpg" : "png")")
                try Self.encoded(image).write(to: url)
                paths.append(.string(url.path))
            }
            inputs[name] = paths.count == 1 ? paths[0] : .array(paths)
        }
        if let prompt = work.params["prompt"]?.stringValue, let name = Self.textInputs[operation] {
            let url = inputDirectory.appending(path: "\(name)-0.txt")
            try Data(prompt.utf8).write(to: url)
            inputs[name] = .string(url.path)
        }

        // The size the normalizer asks for, run at the offer's smallest side when it is smaller and brought back after.
        let limits = call.limits
        var asked: (width: Int, height: Int)?
        if let w = work.width, let h = work.height { asked = (w, h) }
        // An edit that asks no size sends none: the model chooses, as on v0.9.1 (Klein draws 1024²), and the normalizer
        // brings it back to the first image's size (AB-T-0383).
        let run = work.route.capability == .imageEdit && asked == nil
            ? nil : Self.runSize(asked: asked, first: work.inputs["images"]?.first ?? work.inputs["image"]?.first, limits: limits)
        var params: [String: GPPValue] = call.defaults
        params["count"] = 1
        if let run { params["size"] = ["width": .int(Int64(run.width)), "height": .int(Int64(run.height))] }
        if let negative = work.params["negativePrompt"]?.stringValue { params["negative_prompt"] = .string(negative) }
        // The call's own params (`scale`, `kind`, `strength`, `points`, `pointLabels`, …) and its mode (MI-GAN is LaMa's
        // `fast`) go as they are: the worker maps them onto its capability (GPP-1 §3.3).
        for (key, value) in work.params where key != "prompt" && key != "negativePrompt" { params[key] = value.gpp }
        if let mode = work.mode { params["mode"] = .string(mode) }

        let names = Set(call.extensions)
        let modelParams = scope.extensions.filter { names.contains($0.key) }.mapValues(\.gpp)
        let adapters = try await runAdapters(work, call: call, inputs: &inputs)
        let workerDirectory = directory.appending(path: "out", directoryHint: .isDirectory)
        let job = WorkerJob(job: "\(scope.jobID)-\(index)", pluginID: call.plugin.id, model: call.model.id, operation: operation,
                            namedLane: scope.extensions[GaeaEngine.laneExtension]?.stringValue, lanes: call.lanes,
                            params: params, inputs: inputs, modelParams: modelParams, adapters: adapters,
                            seed: Int(clamping: work.seed), outputDir: workerDirectory)
        let ran = try await GaeaEngine.schedule(job, scheduler: scheduler, title: call.plugin.title) { line in
            guard line["type"]?.stringValue == "progress" else { return }
            progress(ModelProgress(phase: line["stage"]?.stringValue ?? "running", fraction: line["fraction"]?.doubleValue,
                                   step: line["step"]?.intValue, totalSteps: line["of"]?.intValue))
        }
        if let route = call.route { scope.record(route, ran) }

        // A describe answers with text and a score with a value (`ImageAnalysisResponse.text`,
        // `ImageQualityScoreResponse.score` and its `subscores`); everything else with a file.
        let outputs = ran.result["outputs"]?.arrayValue ?? []
        func value(_ name: String) -> GPPValue? { outputs.first { $0["name"]?.stringValue == name }?["value"] }
        switch work.route.capability {
        case .imageQualityScore:
            guard let score = value("score")?.doubleValue else { throw MESError(.engineError, "\(call.plugin.title) returned no score.") }
            let subscores = (value("subscores")?.objectValue ?? [:]).compactMapValues { $0.doubleValue.map(Float.init) }
            return .score(Float(score), subscores: subscores)
        case .imageAnalysis:
            guard let text = value("text")?.stringValue ?? outputs.lazy.compactMap({ $0["value"]?.stringValue }).first else {
                throw MESError(.engineError, "\(call.plugin.title) returned no text.")
            }
            return .text(text)
        default:
            break
        }
        guard let output = outputs.first(where: { $0["path"] != nil }), let path = output["path"]?.stringValue else {
            throw MESError(.engineError, "\(call.plugin.title) returned no output.")
        }
        let root = workerDirectory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let source = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard source.path.hasPrefix(root) else { throw MESError(.engineError, "The plugin wrote \(path), outside its output_dir.") }
        var data = try Data(contentsOf: source)
        var size = GaeaEngine.pixelSize(source)
        if let asked, let got = size, (got.width, got.height) != (asked.width, asked.height) {
            data = try Self.resized(data, to: asked)                       // the size the normalizer asked for
            size = asked
        }
        // A matte or a mask comes back as one (matte, segment), with the model's score when it gives one.
        if [.matting, .promptSegment, .defectDetect].contains(work.route.capability) {
            let score = outputs.first { $0["name"]?.stringValue == "score" }?["value"]?.doubleValue
            return .matte(ModelMatte(data: data, width: size?.width, height: size?.height), score: score.map(Float.init))
        }
        let format: ModelImage.Format = source.pathExtension.lowercased() == "jpg" || source.pathExtension.lowercased() == "jpeg" ? .jpeg : .png
        let image = ModelImage(format: format, data: data, width: size?.width, height: size?.height)
        // An upscale that ran behind a guard or a chain says which models made it (`upscale_model`).
        if let model = value("upscale_model")?.stringValue { return .upscaled(image, model: model) }
        return .image(image)
    }

    /// The call's adapters as `run.adapters` items (GPP-1 §3.3), each with the kind, format and source the worker needs.
    /// An `ic` adapter's slot images move from the job's inputs onto the adapter. The normalizer has already checked the
    /// ids, counts and strengths against the offer and applied the triggers.
    func runAdapters(_ work: ModelWork, call: Callee, inputs: inout [String: GPPValue]) async throws -> [GPPValue] {
        guard let chosen = work.adapters, !chosen.isEmpty else { return [] }
        guard let route = call.route else { throw MESError(.invalidRequest, "\(call.model.id) takes no adapters.") }
        let routes = await offers.liveRoutes().filter { $0.plugin.id == route.plugin.id && $0.model.id == route.model.id }
        let known = PluginOffers.adapters(routes, registrations: offers.registrations())
        return try chosen.map { choice in
            guard let adapter = known.first(where: { $0.card.id == choice.id }) else {
                throw MESError(.invalidRequest, "\(call.model.id) has no adapter \(choice.id).")
            }
            var slots: [String: GPPValue] = [:]
            for (role, name) in choice.conditioning.sorted(by: { $0.key < $1.key }) {
                if let path = inputs.removeValue(forKey: name) { slots[role] = path }
            }
            return adapter.runItem(strength: choice.strength ?? adapter.card.defaultStrength, inputs: slots)
        }
    }

    /// What a model call goes to: a plugin's offer of the operation, or a helper Gaea calls (the defect detector).
    struct Callee {
        var plugin: InstalledPlugin
        var model: PluginManifest.Model
        var operation: String
        /// The offer, for the job's record; nil for a helper.
        var route: PluginRoute?
        var limits: PluginManifest.Limits?
        var defaults: [String: GPPValue]
        var lanes: [String]?
        var extensions: [String]

        init(_ route: PluginRoute) {
            plugin = route.plugin; model = route.model; operation = route.operation; self.route = route
            limits = route.manifestOffer.limits; defaults = route.manifestOffer.defaults?.objectValue ?? [:]
            lanes = route.manifestOffer.lanes; extensions = route.extensions.map(\.name)
        }

        init(_ helper: PluginOffers.Helper) {
            plugin = helper.plugin; model = helper.model; operation = helper.helper.operation; route = nil
            limits = nil; defaults = [:]; lanes = nil; extensions = []
        }
    }

    /// The size to run at: the one asked, or for an image input without one, the first image's; scaled up, keeping the
    /// aspect, when its shorter side is under the offer's smallest. nil leaves the size to the worker.
    static func runSize(asked: (width: Int, height: Int)?, first: ModelImage?, limits: PluginManifest.Limits?) -> (width: Int, height: Int)? {
        let base = asked ?? first.flatMap { image in image.width.flatMap { w in image.height.map { (w, $0) } } }
        guard let base, base.0 > 0, base.1 > 0 else { return asked }
        let minSide = limits?.minSide ?? 0
        let shorter = min(base.0, base.1)
        guard shorter < minSide else { return asked }
        let scale = Double(minSide) / Double(shorter)
        let multiple = max(limits?.sizeMultiple ?? 16, 1)
        func up(_ v: Int) -> Int { Int((Double(v) * scale / Double(multiple)).rounded(.up)) * multiple }
        return (up(base.0), up(base.1))
    }

    /// PNG or JPEG bytes for a model image; raw pixels are encoded as PNG.
    static func encoded(_ image: ModelImage) throws -> Data {
        switch image.format {
        case .png, .jpeg: return image.data
        case .rawBGRA8, .rawRGBA16:
            throw MESError(.engineError, "Raw pixels don't travel to plugins yet (\(image.format.rawValue)).")
        }
    }

    /// An image resampled to `size`, as PNG.
    static func resized(_ data: Data, to size: (width: Int, height: Int)) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw MESError(.engineError, "The plugin's image couldn't be read.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let scaled = context.makeImage() else { throw MESError(.engineError, "The plugin's image couldn't be resized.") }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            throw MESError(.engineError, "PNG encoding failed.")
        }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { throw MESError(.engineError, "PNG encoding failed.") }
        return out as Data
    }
}

/// What one job's model calls share while the normalizer runs it: where they write, the request's lane and plugin
/// options, and the worker runs made, which the result reports (`GaeaEngine.attach`).
final class NormalizerScope: Sendable {
    @TaskLocal static var current: NormalizerScope?

    struct Call: Sendable {
        var route: PluginRoute
        var ran: WorkerJobResult
    }

    let jobID: String
    let directory: URL
    let extensions: [String: MESValue]
    private let state = Mutex<(calls: [Call], next: Int)>(([], 0))

    init(jobID: String, directory: URL, extensions: [String: MESValue]) {
        self.jobID = jobID
        self.directory = directory
        self.extensions = extensions
    }

    func nextCall() -> Int { state.withLock { $0.next += 1; return $0.next } }
    func record(_ route: PluginRoute, _ ran: WorkerJobResult) { state.withLock { $0.calls.append(Call(route: route, ran: ran)) } }
    var calls: [Call] { state.withLock { $0.calls } }
}

extension PluginManifest.Model {
    /// Where the model's weights come from, for its licence link (`terms_url`) and the console: the default lane's
    /// checkpoint, else its package's provenance. A package may name one repo for every size it serves:
    /// mlx-qwen-llm-swift names `mlx-community/Qwen3.5-0.8B-MLX-8bit` for the 4B and the 9B too (AB-T-0373).
    public var sourceRepo: String {
        let lane = lanes.first(where: \.default) ?? lanes.first
        return lane?.resolved.weightSources.first { $0.role == "checkpoint" }?.repo ?? package.provenance.sourceRepo
    }
}
