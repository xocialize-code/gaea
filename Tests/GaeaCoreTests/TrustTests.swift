import Foundation
import GaeaProtocol
import Testing
@testable import GaeaCore

/// The trust list (AB-T-0411): teams in gaea.sqlite, releases from an unknown team held for the operator, and a team's
/// removal stopping its plugins. Tested with Gaea's own team treated as unknown (G-25).
@Suite(.serialized) struct TrustTests {
    static let dist = repoRoot.deletingLastPathComponent().appending(path: "gaea-plugin-demo/dist")
    static let demoZip = dist.appending(path: "demo-0.3.0.gaeaplugin.zip")

    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "gaea-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theRequirementNamesEveryTrustedTeam() {
        let text = PluginVerifier.requirementText(teams: ["BBBBB22222", "AAAAA11111"])
        #expect(text.hasPrefix("anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists"))
        #expect(text.hasSuffix("and (certificate leaf[subject.OU] = \"AAAAA11111\" or certificate leaf[subject.OU] = \"BBBBB22222\")"))
        #expect(PluginVerifier.requirementText() == PluginVerifier.requirementText(teams: [GPP.trustedTeam]))
    }

    @Test func trustedTeamsAndHeldReleasesLiveInGaeaSqlite() throws {
        let database = try GaeaDatabase()
        try database.trust(team: "ABCDE12345", name: "Jane Doe")
        try database.trust(team: "ABCDE12345", name: "Someone else")
        #expect(try database.trustedTeams().map(\.name) == ["Jane Doe"])
        let held = HeldRelease(id: "h-1", kind: .update, pluginID: "com.example.p", title: "P", summary: "", version: "1.0.0",
                               repo: "https://github.com/o/r", tag: "v1.0.0", team: "ABCDE12345",
                               signingIdentity: "Developer ID Application: Jane Doe (ABCDE12345)", notarized: true, models: ["a", "b"],
                               record: .init(version: "1.0.0", bundlePath: "/held/p.gaeaplugin", zipSHA256: "z", manifestSHA256: "m",
                                             signature: "s", notarized: true))
        try database.insertHeld(held)
        let read = try #require(try database.held("h-1"))
        #expect(read.kind == .update && read.models == ["a", "b"] && read.teamName == "Jane Doe" && read.record.bundlePath == "/held/p.gaeaplugin")
        try database.deleteHeld("h-1")
        try database.untrust(team: "ABCDE12345")
        #expect(try database.held().isEmpty && database.trustedTeams().isEmpty)
    }

    /// Releases served from memory, as GitHub would serve the demo's: `files` maps a URL's path to its bytes.
    final class Releases: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var files: [String: Data] = [:]
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let data = Self.files[request.url!.path]
            let response = HTTPURLResponse(url: request.url!, statusCode: data == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data ?? Data())
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    func manager(_ dir: URL, ownTeamTrusted: Bool) throws -> PluginManager {
        let base = "https://api.stub.test/dl/"
        let names = ["demo-0.3.0.gaeaplugin.zip", "demo-0.3.0.gaeaplugin.zip.sha256", "manifest.json"]
        let releases: [[String: Any]] = [[
            "tag_name": "v0.3.0", "draft": false, "prerelease": false,
            "assets": names.enumerated().map { i, name in
                ["id": i + 1, "name": name, "size": 1, "url": base + name, "browser_download_url": base + name] as [String: Any]
            },
        ]]
        Releases.files = ["/repos/xocialize-code/gaea-plugin-demo/releases": try JSONSerialization.data(withJSONObject: releases)]
        for name in names { Releases.files["/dl/\(name)"] = try Data(contentsOf: Self.dist.appending(path: name)) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Releases.self]
        let paths = GaeaPaths(root: dir.appending(path: "home"))
        try paths.create()
        return PluginManager(database: try GaeaDatabase(), paths: paths,
                             source: GitHubReleaseSource(apiRoot: URL(string: "https://api.stub.test")!,
                                                         session: URLSession(configuration: configuration)),
                             log: HostLog(file: paths.hostLog, echo: false), ownTeamTrusted: ownTeamTrusted)
    }

    /// G-25: with Gaea's own team treated as unknown, the demo is held, not installed; declined, its download goes;
    /// approved, it installs and launches; its team removed, it stays installed and stops; trusted again, it runs.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: demoZip.path)))
    func anUnknownTeamIsHeldApprovedAndRemoved() async throws {
        let dir = try scratch()
        let manager = try manager(dir, ownTeamTrusted: false)
        let repo = "https://github.com/xocialize-code/gaea-plugin-demo"
        let held = dir.appending(path: "home/Held")

        guard case .held(let first) = try await manager.add(repository: repo) else { Issue.record("not held"); return }
        #expect(first.team == GPP.trustedTeam && first.pluginID == "com.xocialize.gaea.demo")
        #expect(first.signingIdentity?.hasPrefix("Developer ID Application: ") == true && first.models.contains("demo-matmul"))
        #expect(await manager.installed().isEmpty)
        #expect(FileManager.default.fileExists(atPath: first.bundlePath))

        _ = try await manager.decline(first.id)
        #expect(await manager.held().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: held.path).isEmpty, "the declined download is gone")
        await #expect(throws: PluginManager.ManagerError.self) { try await manager.decline(first.id) }

        guard case .held(let second) = try await manager.add(repository: repo) else { Issue.record("not held"); return }
        guard case .added(let plugin) = try await manager.approve(second.id) else { Issue.record("not added"); return }
        #expect(plugin.enabled && plugin.trusted)
        #expect(await manager.trustedTeams() == [GPP.trustedTeam])
        #expect(await manager.held().isEmpty)
        _ = try await manager.launchable(plugin.id)

        let stopped = try await manager.revoke(team: GPP.trustedTeam)
        #expect(stopped == [plugin.id])
        let off = try #require(await manager.installed().first)
        #expect(!off.enabled && !off.trusted, "installed, and off while its team isn't trusted")
        await #expect { _ = try await manager.launchable(plugin.id) } throws: {
            ($0 as? PluginVerifier.Refusal)?.isUntrustedTeam == true
        }

        guard case .team(_, let back) = try await manager.approve(GPP.trustedTeam.lowercased()) else { Issue.record("not trusted"); return }
        #expect(back == [plugin.id])
        #expect(try #require(await manager.installed().first).enabled)
        _ = try await manager.launchable(plugin.id)
    }

    /// Gaea's own team, trusted as built in, can't be removed; a team with nothing installed or held can't be approved.
    @Test func theBuiltInTeamStaysAndAnUnknownTeamNeedsARelease() async throws {
        let dir = try scratch()
        let manager = try manager(dir, ownTeamTrusted: true)
        await #expect { _ = try await manager.revoke(team: GPP.trustedTeam) } throws: {
            if case .builtInTeam = $0 as? PluginManager.ManagerError { true } else { false }
        }
        await #expect { _ = try await manager.approve("ABCDE12345") } throws: {
            if case .unknownTeam = $0 as? PluginManager.ManagerError { true } else { false }
        }
    }
}
