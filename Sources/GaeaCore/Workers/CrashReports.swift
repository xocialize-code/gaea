import Foundation

/// The crash reports macOS writes for a worker (`~/Library/Logs/DiagnosticReports/<process>-<date>.ips`), matched by
/// process and pid, and summarised for the crash record (SRV-8). ReportCrash writes a report for a process ended by a
/// signal that dumps core (a trap, a bad access, an abort), a moment after it's gone; a SIGKILL gets none.
public struct CrashReports: Sendable {
    public var folder: URL

    public init(folder: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)) {
        self.folder = folder
    }

    /// The report for `process` with `pid`, written since `after`.
    public func find(process: String, pid: Int32, after: Date) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.first { file in
            guard file.pathExtension == "ips", file.lastPathComponent.hasPrefix(process + "-"),
                  let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified >= after.addingTimeInterval(-5), let report = Report(file) else { return false }
            return report.pid == pid
        }
    }

    /// Looks every quarter second until `timeout` for the report.
    public func wait(process: String, pid: Int32, after: Date, timeout: Duration = .seconds(20)) async -> URL? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let url = find(process: process, pid: pid, after: after) { return url }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return find(process: process, pid: pid, after: after)
    }

    /// One `.ips`: a JSON header line, then the JSON body.
    public struct Report: Sendable {
        public var pid: Int32
        public var process: String
        /// `EXC_BREAKPOINT (SIGTRAP)`.
        public var exception: String
        /// What the process said as it died, e.g. Swift's `Fatal error: …`.
        public var messages: [String]
        /// The faulting thread's first frames, `image  symbol`.
        public var frames: [String]

        public init?(_ url: URL) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            self.init(text: text)
        }

        public init?(text: String) {
            guard let newline = text.firstIndex(of: "\n"),
                  let body = try? JSONSerialization.jsonObject(with: Data(text[text.index(after: newline)...].utf8)) as? [String: Any],
                  let pid = body["pid"] as? Int else { return nil }
            self.pid = Int32(pid)
            process = body["procName"] as? String ?? ""
            let exception = body["exception"] as? [String: Any]
            let type = exception?["type"] as? String ?? "unknown exception"
            self.exception = (exception?["signal"] as? String).map { "\(type) (\($0))" } ?? type
            // `asi`: the messages each library left for the crash reporter, by library.
            let asi = body["asi"] as? [String: [String]] ?? [:]
            messages = asi.keys.sorted().flatMap { asi[$0] ?? [] }
            let threads = body["threads"] as? [[String: Any]] ?? []
            let images = body["usedImages"] as? [[String: Any]] ?? []
            let faulting = body["faultingThread"] as? Int ?? threads.firstIndex { $0["triggered"] as? Bool == true } ?? 0
            let rawFrames = faulting < threads.count ? threads[faulting]["frames"] as? [[String: Any]] ?? [] : []
            frames = rawFrames.prefix(6).map { frame in
                let image = (frame["imageIndex"] as? Int).flatMap { $0 < images.count ? images[$0]["name"] as? String : nil } ?? "?"
                return "\(image)  \(frame["symbol"] as? String ?? "+\(frame["imageOffset"] as? Int ?? 0)")"
            }
        }

        /// The exception, its messages and the first frames, a line each.
        public var summary: String {
            ([exception] + messages.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                + frames.enumerated().map { "\($0.offset)  \($0.element)" }).joined(separator: "\n")
        }
    }
}
