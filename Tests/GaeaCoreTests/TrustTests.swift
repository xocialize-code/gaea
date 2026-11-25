import Foundation
import GaeaProtocol
import Testing
@testable import GaeaCore

/// The trust list (AB-T-0411): teams in gaea.sqlite, releases from an unknown team held for the operator, and a team's
/// removal stopping its plugins. Tested with Gaea's own team treated as unknown (G-25).
@Suite(.serialized) struct TrustTests {
    static let dist = repoRoot.deletingLastPathComponent().appending(path: "gaea-plugin-demo/dist")
    /// The version built in `dist`, whichever it is.
    static let version = (try? Data(contentsOf: dist.appending(path: "manifest.json")))
        .flatMap { try? JSONDecoder().decode(PluginManifest.self, from: $0) }?.version ?? "none"
    static let demoZip = dist.appending(path: "demo-\(version).gaeaplugin.zip")

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

    /// G-32: Apple's notarization admits a plugin from any team; the trust list is for builds that aren't notarized.
    @Test func aNotarizedPluginRunsWhoeverSignedIt() {
        func signed(_ team: String, notarized: Bool) -> PluginVerifier.Signature {
            PluginVerifier.Signature(team: team, identifier: "com.example.plugin", commonName: nil, notarized: notarized)
        }
        let ours: Set<String> = [GPP.trustedTeam]
        #expect(PluginVerifier.admits(signed("ABCDE12345", notarized: true), trusting: ours))
        #expect(PluginVerifier.admits(signed("ABCDE12345", notarized: true), trusting: []))
        #expect(!PluginVerifier.admits(signed("ABCDE12345", notarized: false), trusting: ours))
        #expect(PluginVerifier.admits(signed(GPP.trustedTeam, notarized: false), trusting: ours), "our own local builds")
        #expect(PluginVerifier.admits(signed("ABCDE12345", notarized: false), trusting: ["ABCDE12345"]), "a team the operator approved")

        func held(_ kind: HeldRelease.Kind, installed: String?, _ team: String, notarized: Bool, trusting: Set<String> = ours) -> String? {
            PluginManager.holdReason(kind: kind, installedTeam: installed, signature: signed(team, notarized: notarized), trusting: trusting)
        }
        // A new plugin.
        #expect(held(.add, installed: nil, "ABCDE12345", notarized: true) == nil)
        #expect(held(.add, installed: nil, "ABCDE12345", notarized: false)?.contains("isn't notarized") == true)
        #expect(held(.add, installed: nil, GPP.trustedTeam, notarized: false) == nil)
        // An update keeps its signer, or waits for the operator: notarized or not.
        #expect(held(.update, installed: "ABCDE12345", "ABCDE12345", notarized: true) == nil)
        #expect(held(.update, installed: "ABCDE12345", "ZYXWV98765", notarized: true)?.contains("another team") == true)
        #expect(held(.update, installed: "ABCDE12345", "ZYXWV98765", notarized: false)?.contains("another team") == true)
        #expect(held(.update, installed: "ABCDE12345", "ZYXWV98765", notarized: true, trusting: ["ZYXWV98765"]) == nil,
                "a signer the operator already approved")
        #expect(held(.update, installed: "ABCDE12345", "ABCDE12345", notarized: false)?.contains("isn't notarized") == true)
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
        static let names = ["demo-\(TrustTests.version).gaeaplugin.zip", "demo-\(TrustTests.version).gaeaplugin.zip.sha256", "manifest.json"]
        static let base = "https://api.stub.test/dl/"
        /// Built once and never written again. Other suites call `manager()` while this one runs (CrashTests,
        /// FirstUseTests, OperatorControlsTests), and a dictionary each call rewrote was a data race that crashed about
        /// one `swift test` in five (AB-T-0473). A file missing from `dist` is left out, and `manager()` reports it.
        static let files: [String: Data] = {
            let releases: [[String: Any]] = [[
                "tag_name": "v\(TrustTests.version)", "draft": false, "prerelease": false,
                "assets": names.enumerated().map { i, name in
                    ["id": i + 1, "name": name, "size": 1, "url": base + name, "browser_download_url": base + name] as [String: Any]
                },
            ]]
            var files = ["/repos/xocialize-code/gaea-plugin-demo/releases": (try? JSONSerialization.data(withJSONObject: releases)) ?? Data()]
            for name in names { files["/dl/\(name)"] = try? Data(contentsOf: TrustTests.dist.appending(path: name)) }
            return files
        }()
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
        // As before the table was shared: a demo build missing from `dist` fails the test here, naming the file.
        for name in Releases.names where Releases.files["/dl/\(name)"] == nil { _ = try Data(contentsOf: Self.dist.appending(path: name)) }
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
