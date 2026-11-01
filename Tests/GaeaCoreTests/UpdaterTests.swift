import Foundation
import GaeaProtocol
import MESCore
import MESEngineCore
import Testing
@testable import GaeaCore

/// Gaea's own updates (G-24): which release it takes, when it's quiet enough to install, what it refuses, and the swap.
@Suite(.serialized) struct UpdaterTests {
    static let app = repoRoot.appending(path: "dist/Gaea.app")

    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "gaea-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func release(_ version: String, prerelease: Bool = false, assets: Bool = true) -> PluginRelease {
        let base = URL(string: "https://stub.test/\(version)/")!
        let names = assets ? ["Gaea-\(version).zip", "Gaea-\(version).zip.sha256", "release.json"] : ["Gaea-\(version).zip"]
        return PluginRelease(tag: "v\(version)", version: SemVer(version)!, prerelease: prerelease, notes: nil, publishedAt: nil,
                             htmlURL: nil, assets: names.enumerated().map { i, name in
                                 .init(id: i, name: name, size: 1, apiURL: base.appending(path: name), downloadURL: base.appending(path: name))
                             })
    }

    @Test func itTakesTheNewestFullReleaseUnlessPreReleasesAreOn() {
        let releases = [release("0.11.3"), release("0.12.0"), release("0.12.1-rc.1", prerelease: true), release("0.13.0", assets: false)]
        let current = SemVer("0.12.0")!
        #expect(GaeaUpdater.choose(releases, current: current, prereleases: false) == nil)
        #expect(GaeaUpdater.choose(releases, current: current, prereleases: true)?.version.description == "0.12.1-rc.1")
        #expect(GaeaUpdater.choose(releases, current: SemVer("0.11.3")!, prereleases: false)?.version.description == "0.12.0")
        // A pre-release of the next version is newer than its predecessor and older than the release itself.
        #expect(GaeaUpdater.choose(releases + [release("0.12.1")], current: current, prereleases: true)?.version.description == "0.12.1")
    }

    func job(_ state: JobState, outcome: Outcome? = nil, finished: Date? = nil) -> JobActivity {
        JobActivity(id: UUID().uuidString, operation: "image.generate", client: "local", model: ModelRef(id: "m", license: License(spdx: "MIT", commercialUse: .yes)),
                    quality: .standard, state: state, outcome: outcome, createdAt: Date(), finishedAt: finished)
    }

    @Test func itWaitsForRunningWaitingAndJustFinishedJobs() {
        let now = Date()
        #expect(GaeaUpdater.quiet(nil, now: now, grace: 60) == nil)
        #expect(GaeaUpdater.quiet(EngineActivity(jobs: []), now: now, grace: 60) == nil)
        #expect(GaeaUpdater.quiet(EngineActivity(jobs: [job(.running), job(.waiting)]), now: now, grace: 60) == "1 running, 1 waiting")
        #expect(GaeaUpdater.quiet(EngineActivity(jobs: [job(.fetching)]), now: now, grace: 60) == "1 waiting")
        let held = job(.holding, outcome: .succeeded, finished: now.addingTimeInterval(-10))
        #expect(GaeaUpdater.quiet(EngineActivity(jobs: [held]), now: now, grace: 60) == "1 just finished, held for its client")
        let old = job(.holding, outcome: .succeeded, finished: now.addingTimeInterval(-120))
        let purged = job(.purged, outcome: .succeeded, finished: now)
        #expect(GaeaUpdater.quiet(EngineActivity(jobs: [old, purged]), now: now, grace: 60) == nil)
    }

    @Test func itNamesThePluginsAnUpdateWouldStrand() {
        let plugins = [(id: "z-image", version: "0.2.0", gpp: 1, manifest: 1), (id: "future", version: "1.0.0", gpp: 2, manifest: 2)]
        #expect(GaeaUpdater.incompatibilities(plugins, info: .init(version: "0.12.0", gpp: [1, 2], manifest: [1, 2])).isEmpty)
        let problems = GaeaUpdater.incompatibilities(plugins, info: .init(version: "0.12.0", gpp: [1], manifest: [1]))
        #expect(problems == ["future 1.0.0 speaks GPP 2, and Gaea 0.12.0 speaks 1",
                             "future 1.0.0 has manifest version 2, and Gaea 0.12.0 reads 1"])
    }

    @Test func aRelaunchKeepsThePortItServedOn() {
        #expect(Relaunch.arguments(["--headless", "--port", "0", "--no-advertise"], servedPort: 51234)
                == ["--headless", "--port", "51234", "--no-advertise"])
        #expect(Relaunch.arguments(["--headless", "--port", "17630"], servedPort: 17630) == ["--headless", "--port", "17630"])
        #expect(Relaunch.arguments(["--headless"], servedPort: 17630) == ["--headless"])
    }

    @Test func itUpdatesOnlyFromAWritableGaeaApp() async throws {
        let dir = try scratch()
        let paths = GaeaPaths(root: dir.appending(path: "home"))
        try paths.create()
        let database = try GaeaDatabase()
        let log = HostLog(file: paths.hostLog, echo: false)
        let built = GaeaUpdater(database: database, paths: paths, log: log, appBundle: repoRoot.appending(path: ".build/debug"))
        #expect(throws: GaeaUpdater.UpdateError.self) { try built.bundleToReplace() }
        let fake = try fakeApp(in: dir.appending(path: "Applications"), version: "0.12.0")
        let updater = GaeaUpdater(database: database, paths: paths, log: log, appBundle: fake)
        #expect(try updater.bundleToReplace() == fake)
        let status = await updater.status()
        #expect(status.cannotUpdate == nil && status.current == Gaea.version && status.kept == nil)
    }

    /// An app folder with only an Info.plist: enough for the checks that read it.
    func fakeApp(in folder: URL, version: String) throws -> URL {
        let app = folder.appending(path: "Gaea.app")
        try FileManager.default.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": Gaea.bundleIdentifier, "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appending(path: "Contents/Info.plist"))
        return app
    }

    /// A staged app that crashes saying what it is (as v0.12.0 from CI did, missing its resources) is refused; one that
    /// doesn't know `--version` (before 0.12.0) is taken at its Info.plist's word.
    @Test func anAppThatCrashesAtStartIsRefused() throws {
        let dir = try scratch()
        let updater = GaeaUpdater(database: try GaeaDatabase(), paths: GaeaPaths(root: dir.appending(path: "home")),
                                  log: HostLog(file: dir.appending(path: "log"), echo: false), appBundle: nil)
        for (name, script, crashes) in [("crashes", "kill -TRAP $$", true), ("old", "echo unknown argument >&2; exit 2", false)] {
            let app = try fakeApp(in: dir.appending(path: name), version: "0.11.3")
            let executable = app.appending(path: "Contents/MacOS/Gaea")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\n\(script)\n".write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            if crashes {
                #expect(throws: GaeaUpdater.UpdateError.self) { try updater.buildInfo(of: app) }
            } else {
                #expect(try updater.buildInfo(of: app) == .init(version: "0.11.3", gpp: [1], manifest: [1]))
            }
        }
    }

    /// Releases served from memory: `StubProtocol.files` maps a URL's path to its bytes.
    final class StubProtocol: URLProtocol, @unchecked Sendable {
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

    func stubbedUpdater(_ dir: URL, facts: GaeaReleaseFacts, zip: Data, checksum: String) throws -> GaeaUpdater {
        let base = "https://api.stub.test/dl/"
        let releases: [[String: Any]] = [[
            "tag_name": "v\(facts.version)", "draft": false, "prerelease": false,
            "assets": [("Gaea-\(facts.version).zip", 1), ("Gaea-\(facts.version).zip.sha256", 2), ("release.json", 3)].map { name, id in
                ["id": id, "name": name, "size": 1, "url": base + name, "browser_download_url": base + name] as [String: Any]
            },
        ]]
        StubProtocol.files = [
            "/repos/xocialize-code/gaea/releases": try JSONSerialization.data(withJSONObject: releases),
            "/dl/release.json": try JSONEncoder().encode(facts),
            "/dl/Gaea-\(facts.version).zip": zip,
            "/dl/Gaea-\(facts.version).zip.sha256": Data("\(checksum)  Gaea-\(facts.version).zip\n".utf8),
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let paths = GaeaPaths(root: dir.appending(path: "home"))
        try paths.create()
        return GaeaUpdater(database: try GaeaDatabase(), paths: paths,
                           source: GitHubReleaseSource(apiRoot: URL(string: "https://api.stub.test")!, session: URLSession(configuration: configuration)),
                           log: HostLog(file: paths.hostLog, echo: false),
                           appBundle: try fakeApp(in: dir.appending(path: "Applications"), version: Gaea.version))
    }

    func facts(_ version: String, gpp: [Int] = [1], sha256: String) -> GaeaReleaseFacts {
        GaeaReleaseFacts(name: "Gaea", version: version, tag: "v\(version)", zip: "Gaea-\(version).zip", sha256: sha256,
                         minimumMacOS: "26.0", gpp: gpp, manifest: [1], team: GPP.trustedTeam, notarized: true)
    }

    @Test func itRefusesAReleaseThatWouldStrandAPluginBeforeDownloading() async throws {
        let dir = try scratch()
        let updater = try stubbedUpdater(dir, facts: facts("99.0.0", gpp: [2], sha256: "x"), zip: Data("zip".utf8), checksum: "x")
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: repoRoot.appending(path: "examples/v1/manifest/demo.json")))
        let plugin = InstalledPlugin(id: manifest.id, version: manifest.version, title: manifest.title, repo: manifest.repo, enabled: true, trusted: true,
                                     bundle: dir, manifest: manifest, manifestData: Data())
        await updater.attach(plugins: { [plugin] }, activity: { nil }, relaunch: { _ in })
        await #expect { _ = try await updater.install() } throws: { error in
            guard case .incompatible(let problems) = error as? GaeaUpdater.UpdateError else { return false }
            return problems.count == 1 && problems[0].hasPrefix("\(manifest.id) \(manifest.version) speaks GPP 1")
        }
        #expect(await updater.status().staged == nil)
    }

    @Test func itRefusesADownloadWhoseDigestDoesntMatch() async throws {
        let dir = try scratch()
        let zip = Data("not the zip that was published".utf8)
        let updater = try stubbedUpdater(dir, facts: facts("99.0.0", sha256: String(repeating: "a", count: 64)), zip: zip,
                                         checksum: String(repeating: "a", count: 64))
        await #expect { _ = try await updater.install() } throws: { error in
            if case .checksum = error as? GaeaUpdater.UpdateError { true } else { false }
        }
        let staging = try FileManager.default.contentsOfDirectory(atPath: dir.appending(path: "home/Caches/staging").path)
        #expect(staging.isEmpty, "the refused download is removed")
    }

    /// The real swap, on copies of the signed app `scripts/build-app.sh` makes: exchanged in place, the replaced one
    /// kept, and back again.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: app.path)))
    func itSwapsTheAppAndKeepsTheOneItReplaced() async throws {
        let dir = try scratch()
        let applications = dir.appending(path: "Applications")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let target = applications.appending(path: "Gaea.app")
        try FileManager.default.copyItem(at: Self.app, to: target)
        let paths = GaeaPaths(root: dir.appending(path: "home"))
        try paths.create()
        let staged = paths.staging.appending(path: "gaea-test/unpacked/Gaea.app")
        try FileManager.default.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.app, to: staged)
        let version = try #require(GaeaUpdater.version(of: Self.app))
        let updater = GaeaUpdater(database: try GaeaDatabase(), paths: paths, log: HostLog(file: paths.hostLog, echo: false), appBundle: target)

        #expect(try await updater.swap(staged, replacing: target, rollback: false) == version)
        #expect(try PluginVerifier.verify(target, trusting: [GPP.trustedTeam]).identifier == Gaea.bundleIdentifier)
        #expect(!FileManager.default.fileExists(atPath: paths.staging.appending(path: "gaea-test").path))
        let kept = try #require(await updater.keptBundle())
        #expect(kept.version == version && kept.app.lastPathComponent == "Gaea-\(version).app")
        #expect(try FileManager.default.contentsOfDirectory(atPath: applications.path) == ["Gaea.app"], "nothing left beside it")

        // Back: the kept app goes in, and the one it leaves is kept in turn.
        #expect(try await updater.swap(kept.app, replacing: target, rollback: true) == version)
        #expect(try PluginVerifier.verify(target, trusting: [GPP.trustedTeam]).identifier == Gaea.bundleIdentifier)
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.updates.path) == ["Gaea-\(version).app"])

        // The built app answers --version (0.12.0 and later).
        let info = try updater.buildInfo(of: target)
        #expect(info.version == version && info.gpp == [1] && info.manifest == [1])
    }
}

