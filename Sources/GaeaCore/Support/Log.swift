import Foundation
import Synchronization

/// Gaea's own log: one line per event, appended to `~/Library/Logs/Gaea/gaea.log` and echoed to stderr.
public final class HostLog: Sendable {
    private let file: URL
    private let lock = Mutex(())
    private let echo: Bool

    public init(file: URL, echo: Bool = true) {
        self.file = file
        self.echo = echo
    }

    public func callAsFunction(_ message: String) {
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        lock.withLock { _ in
            if echo { FileHandle.standardError.write(Data(line.utf8)) }
            Self.append(line, to: file)
        }
    }

    static func append(_ text: String, to file: URL) {
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: file)
        }
    }

    /// The last `lines` lines of a log file.
    public static func tail(_ file: URL, lines: Int) -> String {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return "" }
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines + 1).joined(separator: "\n")
    }
}
