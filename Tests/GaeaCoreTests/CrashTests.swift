import Darwin
import Foundation
import GaeaProtocol
import Testing
@testable import GaeaCore

/// Crash and requeue reporting (SRV-8, AB-T-0417): every worker death Gaea didn't ask for is recorded with what it ran,
/// how it ended, its stderr and macOS's crash report, and a plugin's third crash in ten minutes quarantines it (G-26).
@Suite(.serialized) struct CrashTests {
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "gaea-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func crashesAndQuarantinesLiveInGaeaSqlite() throws {
        let database = try GaeaDatabase()
        var crash = CrashRecord(at: Date(), pluginID: "com.example.p", version: "1.0.0", pid: 42, how: "SIGTRAP", signal: SIGTRAP,
                                status: nil, model: "m", lane: "bf16", job: "job_1", outcome: .requeued,
                                stderrTail: ["one", "Fatal error: two"], reportNote: "looking")
        crash.id = try database.insertCrash(crash)
        try database.updateCrash(crash.id!) { $0.reportPath = "/r.ips"; $0.reportSummary = "EXC_BREAKPOINT (SIGTRAP)"; $0.reportNote = nil }
        let read = try #require(try database.crash(crash.id!))
        #expect(read.stderrTail == ["one", "Fatal error: two"] && read.reportPath == "/r.ips" && read.reportNote == nil && read.lane == "bf16")
        #expect(try database.crashes(plugin: "com.example.p").count == 1)
        #expect(try database.crashes(plugin: "com.example.p", since: Date().addingTimeInterval(60)).isEmpty)
        #expect(try database.crashes(plugin: "com.example.other").isEmpty)
    }

    /// An `.ips` as macOS 27 writes it: a header line, then the body.
    static func ips(pid: Int, process: String = "gaea-demo-worker") -> String {
        let header = #"{"app_name":"\#(process)","bug_type":"309","name":"\#(process)"}"#
        let body: [String: Any] = [
            "pid": pid, "procName": process,
            "exception": ["type": "EXC_BREAKPOINT", "signal": "SIGTRAP"],
            "asi": ["libswiftCore.dylib": ["gaea-demo-worker/main.swift:107: Fatal error: demo-gradient: a trap on seed 666"]],
            "faultingThread": 1,
            "threads": [["frames": []], ["triggered": true, "frames": [
                ["imageIndex": 0, "symbol": "_assertionFailure(_:_:file:line:flags:)"],
                ["imageIndex": 1, "symbol": "GradientModel.run(_:context:)"],
                ["imageIndex": 1, "imageOffset": 1234],
            ]]],
            "usedImages": [["name": "libswiftCore.dylib"], ["name": process]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted])
        return header + "\n" + String(decoding: data, as: UTF8.self)
    }

    @Test func aCrashReportIsSummarised() throws {
        let report = try #require(CrashReports.Report(text: Self.ips(pid: 4242)))
        #expect(report.pid == 4242 && report.process == "gaea-demo-worker")
        #expect(report.summary.components(separatedBy: "\n") == [
            "EXC_BREAKPOINT (SIGTRAP)",
            "gaea-demo-worker/main.swift:107: Fatal error: demo-gradient: a trap on seed 666",
            "0  libswiftCore.dylib  _assertionFailure(_:_:file:line:flags:)",
            "1  gaea-demo-worker  GradientModel.run(_:context:)",
            "2  gaea-demo-worker  +1234",
        ])
        #expect(CrashReports.Report(text: "not a report") == nil)
    }

    @Test func theReportIsFoundByProcessAndPid() async throws {
        let folder = try scratch()
        let reports = CrashReports(folder: folder)
        let began = Date()
        try Self.ips(pid: 11).write(to: folder.appending(path: "gaea-demo-worker-2026-11-01-120000.ips"), atomically: true, encoding: .utf8)
        try Self.ips(pid: 12, process: "other").write(to: folder.appending(path: "other-2026-11-01-120000.ips"), atomically: true, encoding: .utf8)
        #expect(reports.find(process: "gaea-demo-worker", pid: 12, after: began) == nil)
        #expect(reports.find(process: "other", pid: 12, after: began) != nil)
        // ReportCrash writes a moment after the exit: the wait sees it arrive.
        Task {
            try await Task.sleep(for: .milliseconds(400))
            try Self.ips(pid: 13).write(to: folder.appending(path: "gaea-demo-worker-2026-11-01-120001.ips"), atomically: true, encoding: .utf8)
        }
        let found = await reports.wait(process: "gaea-demo-worker", pid: 13, after: began, timeout: .seconds(5))
        #expect(found?.lastPathComponent == "gaea-demo-worker-2026-11-01-120001.ips")
        #expect(await reports.wait(process: "gaea-demo-worker", pid: 14, after: began, timeout: .milliseconds(300)) == nil)
    }

    @Test func anExitNamesItsSignal() {
        let exit = WorkerExit(worker: UUID(), process: "w", pid: 1, status: SIGTRAP, signalled: true, at: Date(), expected: false,
                              fault: nil, stderrTail: [])
        #expect(exit.how == "SIGTRAP" && exit.writesCrashReport)
        var killed = exit
        killed.status = SIGKILL
        #expect(killed.how == "SIGKILL" && !killed.writesCrashReport)
        var exited = exit
        exited.signalled = false
        exited.status = 3
        #expect(exited.how == "exit 3" && !exited.writesCrashReport)
    }

    /// With the demo plugin's release built next door: a worker SIGKILLed mid-job is recorded and the job requeued; killed
    /// again, the job fails with both crashes named; a third crash, while idle, quarantines the plugin, which offers
    /// nothing and refuses jobs until the operator switches it on, after which a job runs and the count starts again.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: TrustTests.demoZip.path)))
    func killedWorkersAreRecordedAndTheThirdQuarantines() async throws {
        let dir = try scratch()
        let manager = try TrustTests().manager(dir, ownTeamTrusted: true)
        guard case .installed(let demo) = try await manager.add(repository: "https://github.com/xocialize-code/gaea-plugin-demo") else {
            Issue.record("the demo was held")
            return
        }
        let reports = dir.appending(path: "DiagnosticReports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let database = await manager.database
        let scheduler = Scheduler(manager: manager, database: database, paths: await manager.paths, log: await manager.log,
                                  budgetBytes: 40_000_000_000, crashReports: CrashReports(folder: reports))
        await manager.attach(workers: scheduler, onChange: {})

        func long(_ name: String) -> WorkerJob {
            WorkerJob(job: name, pluginID: demo.id, model: "demo-matmul", operation: "x-gaea.demo.matmul",
                      params: ["n": 4096, "iterations": 1000], outputDir: dir.appending(path: "spool/\(name)"))
        }
        /// Kills each new worker of the demo as soon as it shows, `times` times.
        func killWorkers(_ times: Int) async throws -> [Int32] {
            var killed: [Int32] = []
            for _ in 0..<600 where killed.count < times {
                if let pid = await scheduler.processes().first(where: { $0.pluginID == demo.id })?.pid, !killed.contains(pid) {
                    kill(pid, SIGKILL)
                    killed.append(pid)
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            return killed
        }

        // Killed twice: requeued once, then failed with both crashes named.
        let job = Task { try await scheduler.run(long("job_twice"), progress: { _ in }) }
        let killed = try await killWorkers(2)
        #expect(killed.count == 2)
        let failure = await #expect(throws: WorkerFailure.self) { try await job.value }
        #expect(failure?.message.contains("crashed twice running this job, SIGKILL (crash #1) then SIGKILL (crash #2)") == true,
                "\(failure?.message ?? "")")
        let crashes = try database.crashes(plugin: demo.id)
        #expect(crashes.map(\.outcome) == [.failed, .requeued])
        #expect(crashes.allSatisfy { $0.how == "SIGKILL" && $0.job == "job_twice" && $0.model == "demo-matmul" && $0.lane == "fp32" })
        #expect(crashes.allSatisfy { $0.reportNote == "none: SIGKILL writes no crash report" && $0.reportPath == nil })
        #expect(Set(crashes.map(\.pid)) == Set(killed))
        #expect(try database.plugin(demo.id)?.quarantinedAt == nil)

        // A third, while idle: quarantined.
        let warm = WorkerJob(job: "job_warm", pluginID: demo.id, model: "demo-matmul", operation: "x-gaea.demo.matmul",
                             params: ["n": 256, "iterations": 1], outputDir: dir.appending(path: "spool/warm"))
        _ = try await scheduler.run(warm, progress: { _ in })
        let idle = try #require(await scheduler.processes().first { $0.pluginID == demo.id }?.pid)
        kill(idle, SIGKILL)
        var row = try database.plugin(demo.id)
        for _ in 0..<100 where row?.quarantinedAt == nil {
            try await Task.sleep(for: .milliseconds(50))
            row = try database.plugin(demo.id)
        }
        #expect(row?.enabled == false && row?.quarantineReason?.hasPrefix("3 crashes in 10 minutes, the last SIGKILL while idle (crash #3)") == true,
                "\(row?.quarantineReason ?? "not quarantined")")
        let third = try #require(try database.crash(3))
        #expect(third.outcome == .idle && third.job == nil && third.quarantined && third.pid == idle)
        #expect(await manager.installed().first { $0.id == demo.id }?.enabled == false)
        let refused = await #expect(throws: WorkerFailure.self) { try await scheduler.run(warm, progress: { _ in }) }
        #expect(refused?.message.contains("is quarantined after 3 crashes in 10 minutes") == true, "\(refused?.message ?? "")")

        // The operator switches it on: cleared, a job runs, and the old crashes no longer count.
        try await manager.setEnabled(true, plugin: demo.id)
        row = try database.plugin(demo.id)
        #expect(row?.enabled == true && row?.quarantinedAt == nil && row?.quarantineReason == nil && row?.crashesClearedAt != nil)
        _ = try await scheduler.run(warm, progress: { _ in })
        let again = try #require(await scheduler.processes().first { $0.pluginID == demo.id }?.pid)
        kill(again, SIGKILL)
        try await Task.sleep(for: .seconds(1))
        #expect(try database.crashes(plugin: demo.id).count == 4)
        #expect(try database.plugin(demo.id)?.quarantinedAt == nil)
        // Stopping isn't a crash.
        _ = try await scheduler.run(warm, progress: { _ in })
        await scheduler.stopAll()
        try await Task.sleep(for: .milliseconds(500))
        #expect(try database.crashes(plugin: demo.id).count == 4)
        let events = try database.events(plugin: demo.id).map(\.kind)
        #expect(events.filter { $0 == "crashed" }.count == 4 && events.contains("quarantined") && events.contains("quarantine_cleared"))
    }

    /// A trap in the plugin (the demo's `GAEA_DEMO_TRAP_SEED`, from 0.3.2): both tries crash with SIGTRAP, the job fails
    /// naming them, and each record has the worker's `Fatal error:` line and macOS's crash report, copied and summarised.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: TrustTests.demoZip.path) && TrustTests.version >= "0.3.2"))
    func aTrapIsRecordedWithItsReport() async throws {
        let dir = try scratch()
        let manager = try TrustTests().manager(dir, ownTeamTrusted: true)
        guard case .installed(let demo) = try await manager.add(repository: "https://github.com/xocialize-code/gaea-plugin-demo") else {
            Issue.record("the demo was held")
            return
        }
        let database = await manager.database
        let paths = await manager.paths
        let scheduler = Scheduler(manager: manager, database: database, paths: paths, log: await manager.log, budgetBytes: 40_000_000_000)
        await manager.attach(workers: scheduler, onChange: {})
        setenv("GAEA_DEMO_TRAP_SEED", "666", 1)
        defer { unsetenv("GAEA_DEMO_TRAP_SEED") }

        func gradient(_ name: String, seed: Int) -> WorkerJob {
            WorkerJob(job: name, pluginID: demo.id, model: "demo-gradient", operation: "image.generate",
                      params: ["size": ["width": 64, "height": 64]], seed: seed, outputDir: dir.appending(path: "spool/\(name)"))
        }
        let failure = await #expect(throws: WorkerFailure.self) { try await scheduler.run(gradient("job_trap", seed: 666), progress: { _ in }) }
        #expect(failure?.message.contains("crashed twice running this job, SIGTRAP (crash #1) then SIGTRAP (crash #2)") == true,
                "\(failure?.message ?? "")")
        // Another seed runs.
        _ = try await scheduler.run(gradient("job_fine", seed: 1), progress: { _ in })

        var crashes = try database.crashes(plugin: demo.id)
        for _ in 0..<120 where crashes.contains(where: { $0.reportNote != nil }) {
            try await Task.sleep(for: .milliseconds(250))
            crashes = try database.crashes(plugin: demo.id)
        }
        #expect(crashes.map(\.outcome) == [.failed, .requeued] && crashes.allSatisfy { $0.how == "SIGTRAP" && $0.model == "demo-gradient" })
        for crash in crashes {
            #expect(crash.stderrTail.contains { $0.contains("Fatal error: demo-gradient: a trap on seed 666") }, "\(crash.stderrTail)")
            let report = try #require(crash.reportPath.map(URL.init(fileURLWithPath:)), "\(crash.reportNote ?? "")")
            #expect(report.path.hasPrefix(paths.crashes.path) && FileManager.default.fileExists(atPath: report.path))
            #expect(CrashReports.Report(report)?.pid == crash.pid)
            #expect(crash.reportSummary?.hasPrefix("EXC_BREAKPOINT (SIGTRAP)") == true, "\(crash.reportSummary ?? "")")
        }
        await scheduler.stopAll()
    }
}
