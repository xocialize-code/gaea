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
    /// The text input an operation takes the model call's `prompt` as.
    static let textInputs = ["image.generate": "prompt", "image.edit": "instruction", "image.fill": "prompt",
                             "image.describe": "question"]

    func models() async -> [ModelCard] {
        let routes = await offers.liveRoutes()
        var cards: [ModelCard] = []
        for (key, group) in Dictionary(grouping: routes, by: { "\($0.plugin.id)/\($0.model.id)" }).sorted(by: { $0.key < $1.key }) {
            _ = key
            guard let first = group.first else { continue }
            cards.append(Self.card(first, all: group))
        }
        return cards
    }

    static func card(_ route: PluginRoute, all: [PluginRoute]) -> ModelCard {
        let capabilities = all.compactMap { capabilities[$0.operation] }
        let license = route.offer.license
        let limits = all.compactMap(\.manifestOffer.limits)
        let envelope = ModelCard.Envelope(maxPixels: limits.compactMap(\.maxPixels).max() ?? 1024 * 1024,
                                          multipleOf: limits.compactMap(\.sizeMultiple).max() ?? 16,
                                          maxInputs: limits.compactMap(\.maxImages).max() ?? 1)
        let provenance = route.model.package.provenance
        let defaultLane = route.model.lanes.first(where: \.default) ?? route.model.lanes.first
        return ModelCard(
            id: route.model.id, displayName: route.model.title, capabilities: capabilities, maturity: .prod,
            license: .init(license.commercialUse == .yes ? .permissive : .restricted, weights: [license.spdx]),
            sourceRepo: provenance.sourceRepo, revision: route.plugin.version, envelope: envelope,
            defaults: .init(steps: param(all, suffix: ".steps")?.intValue, guidance: param(all, suffix: ".guidance")?.doubleValue),
            footprintBytes: defaultLane?.resolved.persistentBytes, downloaded: true)
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
        let card = Self.card(chosen, all: all)
        return ModelRoute(id: card.id, packageID: "\(chosen.plugin.id)/\(chosen.model.id)", capability: capability,
                          displayName: card.displayName, license: card.license, envelope: card.envelope, defaults: card.defaults,
                          revision: chosen.plugin.version, footprintBytes: card.footprintBytes)
    }

    /// Nothing to do ahead of the run: the scheduler admits and prepares the lane when the job reaches the worker.
    func prepare(_ route: ModelRoute, progress: @escaping @Sendable (ModelProgress) -> Void) async throws {}

    func run(_ work: ModelWork, progress: @escaping @Sendable (ModelProgress) -> Void) async throws -> ModelResult {
        guard let operation = Self.operations[work.route.capability],
              let route = await offers.liveRoutes().first(where: { $0.operation == operation && $0.model.id == work.route.id }) else {
            throw MESError(.modelUnavailable, "\(work.route.id) isn't enabled for \(work.route.capability).")
        }
        let scope = NormalizerScope.current ?? NormalizerScope(jobID: "job_\(UUID().uuidString.prefix(8).lowercased())",
                                                                 directory: FileManager.default.temporaryDirectory, extensions: [:])
        let call = scope.nextCall()
        let directory = scope.directory.appending(path: "worker-\(call)", directoryHint: .isDirectory)
        let inputDirectory = directory.appending(path: "inputs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Inputs travel as spool paths (GPP-1 §1): images as the PNGs the normalizer made, the prompt as a text file.
        var inputs: [String: GPPValue] = [:]
        for (name, images) in work.inputs.sorted(by: { $0.key < $1.key }) {
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

        // The size the normalizer asks for, run at the offer's smallest side when it is smaller and brought back after;
        // an edit without one keeps its first image's size, which the normalizer restores.
        let limits = route.manifestOffer.limits
        var asked: (width: Int, height: Int)?
        if let w = work.width, let h = work.height { asked = (w, h) }
        let run = Self.runSize(asked: asked, first: work.inputs["images"]?.first ?? work.inputs["image"]?.first, limits: limits)
        var params: [String: GPPValue] = route.manifestOffer.defaults?.objectValue ?? [:]
        params["count"] = 1
        if let run { params["size"] = ["width": .int(Int64(run.width)), "height": .int(Int64(run.height))] }
        if let negative = work.params["negativePrompt"]?.stringValue { params["negative_prompt"] = .string(negative) }
        if let strength = work.params["strength"]?.numberValue { params["strength"] = .double(strength) }
        for key in ["scale", "kind"] { if let value = work.params[key] { params[key] = value.gpp } }

        let names = Set(route.extensions.map(\.name))
        let modelParams = scope.extensions.filter { names.contains($0.key) }.mapValues(\.gpp)
        let workerDirectory = directory.appending(path: "out", directoryHint: .isDirectory)
        let job = WorkerJob(job: "\(scope.jobID)-\(call)", pluginID: route.plugin.id, model: route.model.id, operation: operation,
                            namedLane: scope.extensions[GaeaEngine.laneExtension]?.stringValue, lanes: route.manifestOffer.lanes,
                            params: params, inputs: inputs, modelParams: modelParams, seed: Int(clamping: work.seed),
                            outputDir: workerDirectory)
        let ran = try await GaeaEngine.schedule(job, scheduler: scheduler, title: route.plugin.title) { line in
            guard line["type"]?.stringValue == "progress" else { return }
            progress(ModelProgress(phase: line["stage"]?.stringValue ?? "running", fraction: line["fraction"]?.doubleValue,
                                   step: line["step"]?.intValue, totalSteps: line["of"]?.intValue))
        }
        scope.record(route, ran)

        guard let output = ran.result["outputs"]?.arrayValue?.first, let path = output["path"]?.stringValue else {
            if let text = ran.result["outputs"]?.arrayValue?.first?["value"]?.stringValue { return .text(text) }
            throw MESError(.engineError, "\(route.plugin.title) returned no output.")
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
        let format: ModelImage.Format = source.pathExtension.lowercased() == "jpg" || source.pathExtension.lowercased() == "jpeg" ? .jpeg : .png
        return .image(ModelImage(format: format, data: data, width: size?.width, height: size?.height))
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
