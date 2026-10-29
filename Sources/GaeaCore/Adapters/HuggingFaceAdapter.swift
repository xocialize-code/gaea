import Foundation

/// A LoRA on the Hugging Face hub, resolved for registration (GPP-1 §4.8): the repo's revision pinned to a commit, the
/// weight file's sha256 and size from the hub's LFS record, the licence from the model card, and the format from the
/// file's safetensors header.
///
/// - A gated repo needs a token in the environment: `HF_TOKEN` (or `HUGGING_FACE_HUB_TOKEN`). Gaea reads it per request
///   and never stores it.
/// - `GAEA_HF_ENDPOINT` points the reader at another hub (a local stand-in for tests).
public struct HuggingFaceAdapter: Sendable, Equatable {
    public var repo: String
    public var revision: String
    public var file: String
    public var sha256: String
    public var bytes: Int?
    /// An SPDX id where the hub's licence id has one, else the hub's id; `NOASSERTION` when the card says nothing.
    public var license: String
    /// `allowed`, `conditional`, `prohibited` or `unknown`.
    public var commercialUse: String
    public var licenseGated: Bool
    public var licenseURL: String
    /// `diffusers-peft`, `kohya`, `diffusers-legacy` or `bfl-fused`; nil when the tensor names don't say.
    public var format: String?
    /// The card's `instance_prompt`, the usual trigger.
    public var trigger: String?
    /// The card's `base_model`s.
    public var baseModels: [String]

    /// `https://huggingface.co/owner/repo`, with `/blob/<rev>/<file>`, `/resolve/<rev>/<file>` or `/tree/<rev>`, or `owner/repo`.
    public struct Reference: Sendable, Equatable {
        public var repo: String
        public var revision: String?
        public var file: String?

        public init?(_ text: String) {
            var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.contains("://") {
                guard let url = URL(string: s), let host = url.host()?.lowercased(),
                      host == "huggingface.co" || host == "www.huggingface.co" || host == "hf.co" else { return nil }
                s = url.path
            }
            var parts = s.split(separator: "/").map(String.init)
            if parts.first == "models" { parts.removeFirst() }
            guard parts.count >= 2, parts[0...1].allSatisfy({ !$0.isEmpty && !$0.contains(" ") }) else { return nil }
            repo = "\(parts[0])/\(parts[1])"
            if parts.count >= 4, ["blob", "resolve", "tree"].contains(parts[2]) {
                revision = parts[3]
                file = parts.count > 4 ? parts[4...].joined(separator: "/") : nil
            } else if parts.count == 2 {
                revision = nil; file = nil
            } else {
                return nil
            }
        }
    }

    public enum ResolveError: Error, CustomStringConvertible {
        case http(Int, String)
        case noWeights(String)
        case severalWeights(String, [String])
        case notLFS(String)

        public var description: String {
            switch self {
            case let .http(status, url):
                status == 401 || status == 403
                    ? "The hub answered \(status) for \(url). A gated repo needs HF_TOKEN in Gaea's environment, and its terms accepted on the hub."
                    : "The hub answered \(status) for \(url)."
            case let .noWeights(repo): "\(repo) has no .safetensors file."
            case let .severalWeights(repo, files):
                "\(repo) has several .safetensors files; name one with --file: \(files.joined(separator: ", "))"
            case let .notLFS(file): "\(file) isn't stored in LFS, so the hub gives no sha256 for it."
            }
        }
    }

    static var endpoint: URL {
        ProcessInfo.processInfo.environment["GAEA_HF_ENDPOINT"].flatMap { $0.isEmpty ? nil : URL(string: $0) }
            ?? URL(string: "https://huggingface.co")!
    }

    static var token: String? {
        let env = ProcessInfo.processInfo.environment
        return ["HF_TOKEN", "HUGGING_FACE_HUB_TOKEN"].lazy.compactMap { env[$0] }.first { !$0.isEmpty }
    }

    static func get(_ url: URL, range: ClosedRange<Int>? = nil, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Gaea/\(Gaea.version)", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let range { request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range") }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 206 else { throw ResolveError.http(status, url.absoluteString) }
        return data
    }

    /// Reads the repo at `reference`'s revision (default: the main branch's current commit).
    public static func resolve(_ reference: Reference, session: URLSession = .shared) async throws -> HuggingFaceAdapter {
        let root = endpoint
        // The repo at the revision asked: its commit and card.
        var info = root.appending(path: "api/models/\(reference.repo)")
        if let revision = reference.revision { info = info.appending(path: "revision/\(revision)") }
        struct Info: Decodable {
            struct Card: Decodable {
                var license: String?
                var license_name: String?
                var license_link: String?
                var instance_prompt: String?
                var base_model: BaseModel?
            }
            enum BaseModel: Decodable {
                case one(String), many([String])
                init(from decoder: Decoder) throws {
                    let c = try decoder.singleValueContainer()
                    if let s = try? c.decode(String.self) { self = .one(s) } else { self = .many(try c.decode([String].self)) }
                }
                var all: [String] { switch self { case let .one(s): [s]; case let .many(a): a } }
            }
            enum Gated: Decodable {
                case no, yes
                init(from decoder: Decoder) throws {
                    let c = try decoder.singleValueContainer()
                    self = ((try? c.decode(Bool.self)) == false) ? .no : .yes
                }
            }
            var sha: String
            var cardData: Card?
            var gated: Gated?
        }
        let repoInfo = try JSONDecoder().decode(Info.self, from: try await get(info, session: session))

        // The weight file, its sha256 and size, at that commit.
        struct Entry: Decodable {
            struct LFS: Decodable { var oid: String; var size: Int }
            var type: String
            var path: String
            var size: Int?
            var lfs: LFS?
        }
        let tree = root.appending(path: "api/models/\(reference.repo)/tree/\(repoInfo.sha)")
            .appending(queryItems: [.init(name: "recursive", value: "true")])
        let entries = try JSONDecoder().decode([Entry].self, from: try await get(tree, session: session))
        let weights = entries.filter { $0.type == "file" && $0.path.hasSuffix(".safetensors") }
        let chosen: Entry
        if let file = reference.file {
            guard let entry = weights.first(where: { $0.path == file }) else { throw ResolveError.noWeights("\(reference.repo)/\(file)") }
            chosen = entry
        } else {
            guard !weights.isEmpty else { throw ResolveError.noWeights(reference.repo) }
            guard weights.count == 1 else { throw ResolveError.severalWeights(reference.repo, weights.map(\.path)) }
            chosen = weights[0]
        }
        guard let lfs = chosen.lfs else { throw ResolveError.notLFS(chosen.path) }

        // The tensor names, from the safetensors header: 8 bytes of length, then JSON.
        let fileURL = root.appending(path: "\(reference.repo)/resolve/\(repoInfo.sha)/\(chosen.path)")
        var format: String?
        if let head = try? await get(fileURL, range: 0...7, session: session), head.count >= 8 {
            let length = head.prefix(8).enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
            if length > 0, length < 64 << 20,
               let header = try? await get(fileURL, range: 8...(8 + length - 1), session: session),
               let object = try? JSONSerialization.jsonObject(with: header) as? [String: Any] {
                format = Self.format(tensorNames: object.keys.filter { $0 != "__metadata__" })
            }
        }

        let card = repoInfo.cardData
        let (license, use) = Self.license(hub: card?.license, name: card?.license_name)
        let gated = repoInfo.gated == .yes
        return HuggingFaceAdapter(
            repo: reference.repo, revision: repoInfo.sha, file: chosen.path, sha256: lfs.oid.lowercased(), bytes: lfs.size,
            license: license, commercialUse: use, licenseGated: gated,
            licenseURL: card?.license_link.flatMap { $0.hasPrefix("http") ? $0 : nil }
                ?? root.appending(path: "\(reference.repo)/blob/\(repoInfo.sha)/README.md").absoluteString,
            format: format, trigger: card?.instance_prompt.flatMap { $0.isEmpty ? nil : $0 },
            baseModels: card?.base_model?.all ?? [])
    }

    /// The adapter format MLXToolKit names, from a LoRA file's tensor names.
    public static func format(tensorNames names: [String]) -> String? {
        if names.contains(where: { $0.contains("lora_down") || $0.contains("lora_up") }) { return "kohya" }
        if names.contains(where: { $0.contains(".lora.down.") || $0.contains(".lora.up.") || $0.contains("lora_linear_layer") }) {
            return "diffusers-legacy"
        }
        guard names.contains(where: { $0.contains(".lora_A.") || $0.contains(".lora_B.") }) else { return nil }
        // BFL's native FLUX layout: fused attention projections per block.
        if names.contains(where: { ($0.contains("double_blocks.") || $0.contains("single_blocks.")) && ($0.contains(".qkv.") || $0.contains(".linear1.")) }) {
            return "bfl-fused"
        }
        return "diffusers-peft"
    }

    /// The hub's licence id as an SPDX id where one exists, and what it says of commercial use.
    public static func license(hub: String?, name: String?) -> (spdx: String, commercialUse: String) {
        guard let id = hub?.lowercased(), !id.isEmpty, id != "other", id != "unknown" else {
            return ("NOASSERTION", "unknown")
        }
        let known: [String: (String, String)] = [
            "apache-2.0": ("Apache-2.0", "allowed"), "mit": ("MIT", "allowed"), "bsd-2-clause": ("BSD-2-Clause", "allowed"),
            "bsd-3-clause": ("BSD-3-Clause", "allowed"), "cc0-1.0": ("CC0-1.0", "allowed"), "cc-by-4.0": ("CC-BY-4.0", "allowed"),
            "cc-by-sa-4.0": ("CC-BY-SA-4.0", "allowed"), "unlicense": ("Unlicense", "allowed"),
            "creativeml-openrail-m": ("CreativeML-OpenRAIL-M", "conditional"), "openrail": ("OpenRAIL", "conditional"),
            "openrail++": ("OpenRAIL++", "conditional"), "bigscience-openrail-m": ("BigScience-OpenRAIL-M", "conditional"),
            "cc-by-nc-4.0": ("CC-BY-NC-4.0", "prohibited"), "cc-by-nc-sa-4.0": ("CC-BY-NC-SA-4.0", "prohibited"),
            "cc-by-nc-nd-4.0": ("CC-BY-NC-ND-4.0", "prohibited"),
            "flux-1-dev-non-commercial-license": ("LicenseRef-FLUX.1-dev-Non-Commercial", "prohibited"),
        ]
        if let (spdx, use) = known[id] { return (spdx, use) }
        if id.contains("-nc") || id.contains("non-commercial") || id.contains("research") { return (id, "prohibited") }
        return (id, "unknown")
    }
}
