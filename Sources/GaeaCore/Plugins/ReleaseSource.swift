import Foundation

/// A plugin repo on GitHub, from the URL the operator added (G-18): `https://github.com/owner/repo`, with or without
/// `.git`, or `owner/repo`.
public struct PluginRepository: Sendable, Hashable, CustomStringConvertible {
    public var owner: String
    public var name: String

    public init?(_ text: String) {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        let parts: [Substring]
        if s.contains("://") {
            guard let url = URL(string: s), let host = url.host()?.lowercased(), host == "github.com" || host == "www.github.com"
            else { return nil }
            parts = url.path.split(separator: "/")
        } else {
            parts = s.split(separator: "/")
        }
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && !$0.contains(" ") }) else { return nil }
        owner = String(parts[0])
        name = String(parts[1])
    }

    public var url: URL { URL(string: "https://github.com/\(owner)/\(name)")! }
    public var description: String { "\(owner)/\(name)" }

    /// Two spellings of the same repo compare equal (GitHub names are case-insensitive).
    public func matches(_ other: PluginRepository) -> Bool {
        owner.lowercased() == other.owner.lowercased() && name.lowercased() == other.name.lowercased()
    }
}

/// One GitHub Release of a plugin repo.
public struct PluginRelease: Sendable, Equatable {
    public struct Asset: Sendable, Equatable {
        public var id: Int
        public var name: String
        public var size: Int
        /// `GET /repos/…/releases/assets/{id}` with `Accept: application/octet-stream` (works for private repos with a token).
        public var apiURL: URL
        /// The public download link (needs no token for a public repo).
        public var downloadURL: URL
    }

    public var tag: String
    public var version: SemVer
    public var prerelease: Bool
    public var notes: String?
    public var publishedAt: Date?
    public var htmlURL: URL?
    public var assets: [Asset]

    /// The bundle zip, its `.sha256`, and the sealed manifest a plugin release carries (Plan §2.2).
    public var zip: Asset? { assets.first { $0.name.hasSuffix(".gaeaplugin.zip") } }
    public var checksum: Asset? { assets.first { $0.name.hasSuffix(".gaeaplugin.zip.sha256") } }
    public var manifest: Asset? { assets.first { $0.name == "manifest.json" } }
}

/// Reads a repo's releases from the GitHub REST API and downloads their assets.
///
/// - Public repos need nothing.
/// - A private repo, during development, needs a token in the environment: `GAEA_GITHUB_TOKEN` (or `GH_TOKEN`,
///   `GITHUB_TOKEN`), for example `GAEA_GITHUB_TOKEN=$(gh auth token)`. Gaea reads it per request and never stores it.
/// - `GAEA_GITHUB_API` points the reader at another API root (a local stand-in for tests).
public struct GitHubReleaseSource: Sendable {
    public var apiRoot: URL
    var session: URLSession

    public init(apiRoot: URL? = nil, session: URLSession = .shared) {
        let env = ProcessInfo.processInfo.environment["GAEA_GITHUB_API"].flatMap { $0.isEmpty ? nil : URL(string: $0) }
        self.apiRoot = apiRoot ?? env ?? URL(string: "https://api.github.com")!
        self.session = session
    }

    static var token: String? {
        let env = ProcessInfo.processInfo.environment
        return ["GAEA_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"].lazy.compactMap { env[$0] }.first { !$0.isEmpty }
    }

    public enum SourceError: Error, CustomStringConvertible {
        case http(Int, String)
        case notFound(PluginRepository)

        public var description: String {
            switch self {
            case let .http(status, url): "GitHub answered \(status) for \(url)"
            case let .notFound(repo):
                "GitHub has no repo \(repo) we can read. A private repo needs GAEA_GITHUB_TOKEN in Gaea's environment."
            }
        }
    }

    func request(_ url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Gaea/\(Gaea.version)", forHTTPHeaderField: "User-Agent")
        if let token = Self.token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// Every published release, newest first as GitHub lists them. Drafts are skipped.
    public func releases(_ repo: PluginRepository) async throws -> [PluginRelease] {
        let url = apiRoot.appending(path: "repos/\(repo.owner)/\(repo.name)/releases").appending(queryItems: [.init(name: "per_page", value: "50")])
        let (data, response) = try await session.data(for: request(url, accept: "application/vnd.github+json"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw SourceError.notFound(repo) }
        guard status == 200 else { throw SourceError.http(status, url.absoluteString) }

        struct Wire: Decodable {
            struct Asset: Decodable { var id: Int; var name: String; var size: Int; var url: URL; var browser_download_url: URL }
            var tag_name: String
            var draft: Bool
            var prerelease: Bool
            var body: String?
            var published_at: String?
            var html_url: URL?
            var assets: [Asset]
        }
        let iso = ISO8601DateFormatter()
        return try JSONDecoder().decode([Wire].self, from: data).compactMap { w in
            guard !w.draft, let version = SemVer(w.tag_name) else { return nil }
            return PluginRelease(
                tag: w.tag_name, version: version, prerelease: w.prerelease, notes: w.body,
                publishedAt: w.published_at.flatMap(iso.date(from:)), htmlURL: w.html_url,
                assets: w.assets.map { .init(id: $0.id, name: $0.name, size: $0.size, apiURL: $0.url, downloadURL: $0.browser_download_url) })
        }
    }

    /// Downloads an asset to a file. With a token it goes through the API (private repos); without, the public link.
    public func download(_ asset: PluginRelease.Asset, to file: URL) async throws {
        let url = Self.token != nil ? asset.apiURL : asset.downloadURL
        let (temporary, response) = try await session.download(for: request(url, accept: "application/octet-stream"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            throw SourceError.http(status, url.absoluteString)
        }
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temporary, to: file)
    }

    /// A small asset's bytes (the manifest, the checksum).
    public func data(_ asset: PluginRelease.Asset) async throws -> Data {
        let url = Self.token != nil ? asset.apiURL : asset.downloadURL
        let (data, response) = try await session.data(for: request(url, accept: "application/octet-stream"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SourceError.http(status, url.absoluteString) }
        return data
    }
}
