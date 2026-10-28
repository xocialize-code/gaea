import Foundation
import GaeaOperator

// gaea — Gaea's command line, on the same Mac as the server (G-17). It talks to the running Gaea over the local
// operator socket, which checks who is calling; nothing here works from another machine.
//
//   gaea status                         the server, its plugins, workers and memory
//   gaea logs [-n 80]                   Gaea's own log
//   gaea ledger                         memory across processes (MEM-4)
//   gaea plugins [list]                 installed plugins
//   gaea plugins add <repo-url> [version]  add by Git repo URL (G-18): the newest full release, or that version
//   gaea plugins check                  read every plugin's repo for updates
//   gaea plugins update <id> [version]  install beside, switch when idle
//   gaea plugins rollback <id>          back to the version kept
//   gaea plugins enable|disable <id>
//   gaea plugins remove <id>
//   gaea plugins logs <id> [-n 80]      a plugin's events and its worker's stderr (UI-6)
//   gaea models [list]                  every plugin model, on or off
//   gaea models enable|disable <id>
//
// --json prints the JSON answer instead of the text. GAEA_HOME points at another Gaea folder.

let usage = """
    usage: gaea status | logs [-n N] | ledger
           gaea plugins [list | add <repo-url> [version] | check | update <id> [version] | rollback <id>
                         | enable <id> | disable <id> | remove <id> | logs <id> [-n N]]
           gaea models [list | enable <id> | disable <id>]
           (--json for JSON)
    """

var args = Array(CommandLine.arguments.dropFirst())
let wantsJSON = args.contains("--json")
args.removeAll { $0 == "--json" }
var lines: String?
if let i = args.firstIndex(of: "-n"), i + 1 < args.count {
    lines = args[i + 1]
    args.removeSubrange(i...(i + 1))
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// The third word: the plugin or model id, or the repo URL.
@MainActor func operand() -> String {
    guard args.count >= 3 else { fail(usage) }
    return args[2]
}

@MainActor func request() -> OperatorRequest {
    switch (args.first, args.dropFirst().first) {
    case ("status", _): return OperatorRequest(command: .status)
    case ("logs", _): return OperatorRequest(command: .logs, args: lines.map { ["lines": $0] } ?? [:])
    case ("ledger", _): return OperatorRequest(command: .ledger)
    case ("plugins", nil), ("plugins", "list"): return OperatorRequest(command: .pluginsList)
    case ("plugins", "add"):
        var a = ["repo": operand()]
        if args.count >= 4 { a["version"] = args[3] }
        return OperatorRequest(command: .pluginsAdd, args: a)
    case ("plugins", "check"): return OperatorRequest(command: .pluginsCheck)
    case ("plugins", "update"):
        var a = ["id": operand()]
        if args.count >= 4 { a["version"] = args[3] }
        return OperatorRequest(command: .pluginsUpdate, args: a)
    case ("plugins", "rollback"): return OperatorRequest(command: .pluginsRollback, args: ["id": operand()])
    case ("plugins", "enable"): return OperatorRequest(command: .pluginsEnable, args: ["id": operand()])
    case ("plugins", "disable"): return OperatorRequest(command: .pluginsDisable, args: ["id": operand()])
    case ("plugins", "remove"): return OperatorRequest(command: .pluginsRemove, args: ["id": operand()])
    case ("plugins", "logs"):
        var a = ["id": operand()]
        if let lines { a["lines"] = lines }
        return OperatorRequest(command: .pluginsLogs, args: a)
    case ("models", nil), ("models", "list"): return OperatorRequest(command: .modelsList)
    case ("models", "enable"): return OperatorRequest(command: .modelsEnable, args: ["id": operand()])
    case ("models", "disable"): return OperatorRequest(command: .modelsDisable, args: ["id": operand()])
    case ("-h", _), ("--help", _), ("help", _):
        print(usage)
        exit(0)
    default: fail(usage)
    }
}

do {
    let response = try OperatorClient().send(request())
    if wantsJSON, let json = response.json {
        print(json)
    } else {
        print(response.text)
    }
    exit(response.ok ? 0 : 1)
} catch {
    fail("gaea: \(error)")
}
