import Foundation
import GaeaProtocol
import MESCore
import PixelAgencyNormalizer
import Synchronization

/// The image normalizer's prompt enhancer (Image §1.9, G-10, AB-T-0370): the profiles the LLM plugin's helper serves,
/// and its rewrite. The profiles stay in the plugin; its manifest lists the facts their decision reads (GPP-1 §4.4), so
/// Gaea decides here whether a prompt needs the model at all and calls the helper, `x-gaea.prompt.enhance`, only when
/// it does. When to rewrite (the mode, the licence policy, a backbone being offered) is the normalizer's
/// (`PromptEnhancement`); what the rewrite says is the plugin's.
///
/// `PromptEnhancing` reads its lists synchronously, so they come from a snapshot of the live helpers, which the engine
/// refreshes before the normalizer reads descriptors or runs a job (`refresh`).
public struct GaeaPromptEnhancer: PromptEnhancing {
    public static let operation = "x-gaea.prompt.enhance"
    /// The sampling pixel-agency-image-engine rewrites with (KitPromptEnhancer).
    static let temperature = 0.7

    let scheduler: Scheduler
    let snapshot = Shared()

    /// The snapshot, shared by every copy of the enhancer.
    final class Shared: Sendable {
        private let state = Mutex(Snapshot())
        func withLock<T>(_ body: (inout Snapshot) -> T) -> T { state.withLock { body(&$0) } }
    }

    struct Snapshot: Sendable {
        /// Backbone model ids, small first.
        var backbones: [String] = []
        /// Each profile in the normalizer's terms, and the facts its decision reads.
        var profiles: [(PromptProfile, PluginManifest.PromptProfile)] = []
        /// The plugin serving each backbone.
        var plugins: [String: String] = [:]
    }

    init(scheduler: Scheduler) { self.scheduler = scheduler }

    /// Reads the live helpers' profiles: one snapshot per descriptors or run.
    func refresh(_ offers: PluginOffers) async {
        let helpers = await offers.liveHelpers().filter { $0.helper.operation == Self.operation }
            .sorted { ($0.model.lanes.first(where: \.default)?.resolved.persistentBytes ?? 0)
                < ($1.model.lanes.first(where: \.default)?.resolved.persistentBytes ?? 0) }
        var next = Snapshot()
        for helper in helpers {
            next.backbones.append(helper.model.id)
            next.plugins[helper.model.id] = helper.plugin.id
            for facts in helper.helper.profiles ?? [] where !next.profiles.contains(where: { $0.0.id == facts.id }) {
                next.profiles.append((Self.profile(facts, backbone: helper.model.id), facts))
            }
        }
        snapshot.withLock { $0 = next }
    }

    static func profile(_ facts: PluginManifest.PromptProfile, backbone: String) -> PromptProfile {
        let policy: PromptProfile.Policy = switch facts.policy {
        case .required: .required
        case .recommended: .recommended
        case .optional: .optional
        }
        return PromptProfile(id: facts.id, version: facts.version, title: facts.title, models: facts.models, policy: policy,
                             structured: facts.structured, suggestsSize: facts.suggestsSize, laysOutCanvas: facts.laysOutCanvas,
                             backbone: backbone, large: facts.large)
    }

    /// The backbones the image normalizer and Pixel Agency's engines know, small first. The normalizer fixes its
    /// preview's backbones when it is made, before any plugin is read, so these are always listed; one is offered only
    /// while a plugin serves it (the host has no model card for it otherwise).
    static let knownBackbones = ["qwen3.5-4b", "qwen3.5-9b"]

    public var backboneIDs: [String] {
        let live = snapshot.withLock { $0.backbones }
        return Self.knownBackbones + live.filter { !Self.knownBackbones.contains($0) }
    }
    public var profiles: [PromptProfile] { snapshot.withLock { $0.profiles.map(\.0) } }

    public func profile(forModel model: String) -> PromptProfile? {
        snapshot.withLock { $0.profiles.first { $0.0.models.contains(model) }?.0 }
    }

    /// prompt-enhance-kit's decision (`PromptEnhancer.decision`, prompt-enhance-kit-swift 0.7.0), over the facts the
    /// plugin lists: no instructions for the task, an edit (it would need to see the image), a prompt that is already
    /// JSON where the profile passes those through, then under `auto` the policy and the detailed-prompt length.
    public func skip(_ prompt: String, profile: PromptProfile, task: PromptTask, always: Bool) -> PromptOutcome? {
        guard let facts = snapshot.withLock({ $0.profiles.first { $0.0.id == profile.id }?.1 }) else { return nil }
        return Self.decision(prompt, facts: facts, task: task, always: always)
    }

    static func decision(_ prompt: String, facts: PluginManifest.PromptProfile, task: PromptTask, always: Bool) -> PromptOutcome? {
        guard facts.tasks.contains(task.rawValue) else { return .noInstruction }
        if task.needsVision { return .needsVision }
        if facts.passThroughStructured, isStructured(prompt) { return .passedThrough }
        guard !always else { return nil }
        switch facts.policy {
        case .required: return nil
        case .optional: return .notRecommended
        case .recommended:
            if let words = facts.detailedAtWords, wordCount(prompt) >= words { return .passedThrough }
            return nil
        }
    }

    /// Whitespace-separated words, with CJK ideographs counted two to a word, as the kit counts them.
    static func wordCount(_ text: String) -> Int {
        func ideograph(_ scalar: Unicode.Scalar) -> Bool { (0x4E00...0x9FFF).contains(scalar.value) }
        let ideographs = text.unicodeScalars.filter(ideograph).count
        let words = text.split(whereSeparator: \.isWhitespace).filter { !$0.unicodeScalars.allSatisfy(ideograph) }.count
        return words + (ideographs + 1) / 2
    }

    /// A prompt that is already a JSON object or array.
    static func isStructured(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
    }

    /// The rewrite: the helper on the backbone's plugin, through the scheduler like any job. Cancellation is rethrown;
    /// any other failure is a `failed` outcome, and the image model runs with the prompt as typed.
    public func enhance(_ prompt: String, profile: PromptProfile, task: PromptTask, always: Bool,
                        targetSize: (width: Int, height: Int)?, seed: UInt64, timeout: Duration,
                        backbone: ModelRoute) async throws -> PromptRewrite {
        guard let pluginID = snapshot.withLock({ $0.plugins[backbone.id] }) else {
            return PromptRewrite(prompt: prompt, outcome: .failed, failure: "no plugin serves \(backbone.id)")
        }
        let scope = NormalizerScope.current
        let directory = (scope?.directory ?? FileManager.default.temporaryDirectory)
            .appending(path: "enhance-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let input = directory.appending(path: "prompt-0.txt")
            try Data(prompt.utf8).write(to: input)
            var params: [String: GPPValue] = [
                "profile": .string(profile.id), "task": .string(task.rawValue), "mode": .string(always ? "always" : "auto"),
                "temperature": .double(Self.temperature),
                "timeout_s": .double(Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18),
            ]
            if let targetSize { params["target_size"] = ["width": .int(Int64(targetSize.width)), "height": .int(Int64(targetSize.height))] }
            let job = WorkerJob(job: "\(scope?.jobID ?? "job_enhance")-enhance", pluginID: pluginID, model: backbone.id,
                                operation: Self.operation, params: params, inputs: ["prompt": .string(input.path)],
                                seed: Int(clamping: seed), outputDir: directory.appending(path: "out", directoryHint: .isDirectory))
            let ran = try await GaeaEngine.schedule(job, scheduler: scheduler, title: "Prompt enhancer") { _ in }
            let values = Dictionary((ran.result["outputs"]?.arrayValue ?? []).compactMap { o in
                o["name"]?.stringValue.map { ($0, o["value"] ?? .null) }
            }, uniquingKeysWith: { a, _ in a })
            let outcome = values["outcome"]?.stringValue.flatMap(PromptOutcome.init(rawValue:)) ?? .failed
            let suggested = values["suggested_size"].map {
                SuggestedSize(width: $0["width"]?.intValue, height: $0["height"]?.intValue, aspectRatio: $0["aspect_ratio"]?.stringValue)
            }
            let canvas = values["canvas"].flatMap { c in c["width"]?.intValue.flatMap { w in c["height"]?.intValue.map { CanvasSize(width: w, height: $0) } } }
            return PromptRewrite(prompt: values["prompt"]?.stringValue ?? prompt, outcome: outcome,
                                 attempts: values["attempts"]?.intValue ?? 1, failure: values["failure"]?.stringValue,
                                 suggestedSize: suggested, canvas: canvas)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            return PromptRewrite(prompt: prompt, outcome: .failed, failure: "\(error)")
        }
    }
}
