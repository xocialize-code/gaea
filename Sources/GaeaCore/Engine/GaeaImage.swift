import Foundation
import GaeaProtocol
import MESCore
import MESEngineCore

// MARK: - Image operations whose offers run as themselves

/// Image operations the image normalizer has no table entry for. Most of Image 0.1 goes through
/// pixel-agency-normalizer, which plans the run and picks the models. An operation it doesn't list is served here from
/// MESKit's own table, each plugin offer run as itself, as audio, video and mesh offers are.
///
/// `image.locate` (Image §3.4, RFC 0010, media-engine-spec v0.15.0; AB-T-0483) is the first: a picture and a prompt in,
/// boxes out. What Gaea does around the worker:
/// - **The image upright.** A box is a share of the upright image, so the worker gets it upright (an upright PNG or JPEG
///   as sent, anything else as an upright PNG), as `mesh.generate_part`'s is.
/// - **`count`**: what the request sent, else 1, sent to the worker and reported in `effective`.
/// MESKit serves the boxes (`ImageProfileRules.finish`): each kept inside the image, sorted by score, cut to `count`,
/// with `nothing_found` on an empty list. A worker returns what its model gave, as the `boxes` output's value.
extension GaeaEngine {
    /// The Image operations served here and not by the normalizer.
    static let ownImageOperations: Set<String> = [ImageProfile.locate]

    /// One descriptor per own Image operation some enabled plugin offers.
    func ownImageDescriptors(_ routes: [PluginRoute]) -> [Descriptor] {
        let own = routes.filter { $0.manifestOffer.profile == ImageProfile.id && Self.ownImageOperations.contains($0.operation) }
        return Set(own.map(\.operation)).sorted().compactMap { operation in
            Self.ownImageDescriptor(operation, routes: own.filter { $0.operation == operation })
        }
    }

    static func ownImageDescriptor(_ operation: String, routes: [PluginRoute]) -> Descriptor? {
        guard let spec = ImageProfile.operations.operations[operation], !routes.isEmpty else { return nil }
        let models = Self.audioModels(routes)
        let inputs = spec.inputs.sorted { $0.key < $1.key }.map { name, io in
            InputSpec(name: name, kind: io.kind, required: io.required ?? false, max: io.kind == .text ? nil : 1,
                      mediaTypes: io.kind == .image ? ["image/png", "image/jpeg", "image/webp", "image/heic", "image/tiff"] : nil)
        }
        let limits = audioLimits(models)
        var properties: [String: MESValue] = [:]
        for (order, name) in spec.vocabulary.enumerated() {
            guard case .object(var schema)? = ImageProfile.vocabularySchema(name, operation: operation) else { continue }
            // The most boxes any offer returns is the descriptor's `count` maximum (§3.4).
            if operation == ImageProfile.locate, name == ImageProfile.Param.count, let most = limits?.maxCount {
                schema["maximum"] = .number(Double(most))
            }
            var hints: [String: MESValue] = ["label": .string(name == ImageProfile.Param.count ? "Most boxes" : name.capitalized),
                                             "order": .number(Double(order))]
            hints["widget"] = name == "seed" ? "seed" : "stepper"
            if name == "seed" { hints["advanced"] = true }
            schema["x-mes-ui"] = .object(hints)
            properties[name] = .object(schema)
        }
        let outputs = spec.outputs.sorted { $0.key < $1.key }.map { name, io in
            OutputSpec(name: name, kind: io.kind, mediaTypes: io.kind == .data ? ["application/json"] : ["image/png"], min: 1, max: 1)
        }
        let tiers = QualityTier.allCases.filter { tier in models.contains { $0.qualityTiers.contains(tier) } }
        return Descriptor(
            operation: operation, profile: ImageProfile.id, profileVersion: ImageProfile.version,
            title: [ImageProfile.locate: "Locate"][operation] ?? operation,
            summary: [ImageProfile.locate: "Where something is in a picture, as boxes."][operation], inputs: inputs,
            params: .object(["type": "object", "additionalProperties": false, "properties": .object(properties)]),
            outputs: outputs, limits: limits, qualityTiers: tiers, models: models, remote: .init(possible: false))
    }

    /// One own Image offer, run as itself.
    func runOwnImage(_ route: PluginRoute, _ context: RunContext) async throws -> RunOutput {
        typealias P = ImageProfile.Param
        let workerDirectory = context.outputDirectory.appending(path: "worker", directoryHint: .isDirectory)
        let inputDirectory = context.outputDirectory.appending(path: "worker-inputs", directoryHint: .isDirectory)
        var params = route.manifestOffer.defaults?.objectValue ?? [:]
        for (key, value) in context.params { params[key] = value.gpp }
        var inputs = context.inputs
        guard case .file(let url, _)? = context.inputs["image"]?.first else {
            throw MESError(.invalidRequest, "Input 'image' is missing.", param: "image")
        }
        if let upright = try Self.uprightImage(url, into: inputDirectory) {
            inputs["image"] = [.file(upright, mediaType: "image/png")]
        }
        let count = context.param(P.count)?.intValue ?? 1
        if route.operation == ImageProfile.locate { params[P.count] = .int(Int64(count)) }

        let names = Set(route.extensions.map(\.name))
        let modelParams = context.extensions.filter { names.contains($0.key) }.mapValues(\.gpp)
        let job = WorkerJob(
            job: context.jobID, pluginID: route.plugin.id, model: route.model.id, operation: route.operation,
            namedLane: context.extensions[Self.laneExtension]?.stringValue, lanes: route.manifestOffer.lanes,
            params: params, inputs: try Self.inputPaths(inputs, writingTextTo: inputDirectory), modelParams: modelParams,
            seed: context.param(P.seed)?.intValue, outputDir: workerDirectory)
        let ran = try await schedule(job, title: route.plugin.title, context: context)
        let outputs = try Self.producedOutputs(result: ran.result, chunks: [], workerDirectory: workerDirectory,
                                               outputDirectory: context.outputDirectory, specs: context.descriptor.outputs)
        var effective = ran.result["effective"]?.objectValue?.mapValues(\.mes) ?? [:]
        if route.operation == ImageProfile.locate { effective[P.count] = .number(Double(count)) }
        var output = RunOutput(outputs: outputs, effective: effective,
                               seed: effective["seed"]?.intValue ?? context.param(P.seed)?.intValue)
        Self.attach(ran, plugin: route.plugin, model: route.model.id, operation: route.operation, to: &output)
        try? FileManager.default.removeItem(at: inputDirectory)
        return output
    }
}
