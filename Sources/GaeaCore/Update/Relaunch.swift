import Darwin
import Foundation

/// Starting the Gaea.app an update put in place, with this launch's arguments and environment, after this one has
/// stopped serving (G-24).
public enum Relaunch {
    /// Headless: the new executable replaces this process. The pid, arguments, environment, terminal and launchd job
    /// stay the same, so a supervisor sees one process that came back. Every descriptor above stderr is closed by exec.
    public static func exec(_ app: URL, arguments: [String]) -> Never {
        let executable = app.appending(path: "Contents/MacOS/Gaea").path
        let limit = getdtablesize()
        for fd in 3..<limit { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        execv(executable, argv)
        FileHandle.standardError.write(Data("Gaea: couldn't start \(executable): \(String(cString: strerror(errno)))\n".utf8))
        exit(1)
    }

    /// The app: a shell waits for this process to exit, then starts the new executable with the same arguments and
    /// environment (`open` would drop the environment, and with it `GAEA_HOME`).
    public static func afterExit(_ app: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \"$0\" 2>/dev/null; do sleep 0.2; done; exec \"$@\"",
                             String(getpid()), app.appending(path: "Contents/MacOS/Gaea").path] + arguments
        try process.run()
    }

    /// This launch's arguments, with `--port 0` (a free port) replaced by the port it served on, so clients find the
    /// relaunched server where it was.
    public static func arguments(_ original: [String], servedPort: Int?) -> [String] {
        var arguments = original
        if let servedPort, let i = arguments.firstIndex(of: "--port"), i + 1 < arguments.count, arguments[i + 1] == "0" {
            arguments[i + 1] = String(servedPort)
        }
        return arguments
    }
}
