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
//   gaea crashes [<plugin>] [-n 50]     worker crashes, newest first, and quarantines (SRV-8, G-26)
//   gaea crashes show <id>              one crash: what ran, how it ended, stderr's last lines, macOS's crash report
//   gaea trust [list]                   the trusted teams, and releases held because their team isn't (AB-T-0411)
//   gaea trust approve <held-id | team> trust a held release's team and finish its install, or trust a team again
//   gaea trust decline <held-id>        drop a held release
//   gaea trust remove <team>            stop trusting a team: its plugins stop and stay installed
//   gaea models [list]                  every plugin model, on or off
//   gaea models enable|disable <id>
//   gaea models root [<folder> | default]  the shared weights folder: read it, set it, or go back to MLXEngine's store
//   gaea models lane <id> [<lane> | default]  the lane a model loads when it fits (MEM-7): read it, set it, or go back
//                                       to the manifest's default
//   gaea adapters [list]                every adapter (LoRA), shipped by a plugin or added, on or off
//   gaea adapters add <hf-url> --model <id> [--file f] [--id id] [--title t] [--trigger t] [--format f] [--strength s]
//                                       add a LoRA by its Hugging Face repo URL for one model (GPP-1 §4.8)
//   gaea adapters enable|disable <id>   an opt-in adapter starts off; enabling it accepts its terms
//   gaea adapters remove <id>           an added one (its weights stay in the models root)
//   gaea update --check                 read Gaea's releases: what's available, what's kept for rollback
//   gaea update [<version>]             download and verify the newest release (or that version, a pre-release too),
//                                       install it once no job is running or waiting, and relaunch (G-24)
//   gaea update --rollback              back to the version the last update replaced
//   gaea update --cancel                drop an update that is still waiting
//   gaea update --prereleases [on|off]  include pre-releases in checks and updates
//
// --json prints the JSON answer instead of the text. GAEA_HOME points at another Gaea folder.

let usage = """
    usage: gaea status | logs [-n N] | ledger
           gaea plugins [list | add <repo-url> [version] | check | update <id> [version] | rollback <id>
                         | enable <id> | disable <id> | remove <id> | logs <id> [-n N] | warm <id> [model] [lane]]
           gaea workers idle [<seconds> | default]
           gaea crashes [<plugin> | show <id>]
           gaea trust [list | approve <held-id | team> | decline <held-id> | remove <team>]
           gaea models [list | enable <id> | disable <id> | root [<folder> | default] | lane <id> [<lane> | default]]
           gaea adapters [list | add <hf-url> --model <id> [--file f] [--id id] [--title t] [--trigger t] [--format f]
                          [--strength s] | enable <id> | disable <id> | remove <id>]
           gaea update [<version> | --check | --rollback | --cancel | --prereleases [on|off]]
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
    case ("workers", "idle"): return OperatorRequest(command: .workersIdle, args: args.count >= 3 ? ["seconds": args[2]] : [:])
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
    case ("plugins", "warm"):
        var a = ["id": operand()]
        if args.count >= 4 { a["model"] = args[3] }
        if args.count >= 5 { a["lane"] = args[4] }
        return OperatorRequest(command: .pluginsWarm, args: a)
    case ("crashes", "show"): return OperatorRequest(command: .crashesShow, args: ["id": operand()])
    case ("crashes", let plugin):
        var a: [String: String] = [:]
        if let plugin, plugin != "list" { a["plugin"] = plugin }
        if let lines { a["lines"] = lines }
        return OperatorRequest(command: .crashesList, args: a)
    case ("trust", nil), ("trust", "list"): return OperatorRequest(command: .trustList)
    case ("trust", "approve"): return OperatorRequest(command: .trustApprove, args: ["id": operand()])
    case ("trust", "decline"): return OperatorRequest(command: .trustDecline, args: ["id": operand()])
    case ("trust", "remove"): return OperatorRequest(command: .trustRemove, args: ["team": operand()])
    case ("plugins", "logs"):
        var a = ["id": operand()]
        if let lines { a["lines"] = lines }
        return OperatorRequest(command: .pluginsLogs, args: a)
    case ("models", nil), ("models", "list"): return OperatorRequest(command: .modelsList)
    case ("models", "enable"): return OperatorRequest(command: .modelsEnable, args: ["id": operand()])
    case ("models", "disable"): return OperatorRequest(command: .modelsDisable, args: ["id": operand()])
    case ("models", "root"):
        guard args.count >= 3 else { return OperatorRequest(command: .modelsRoot) }
        let path = args[2] == "default" ? "default" : URL(fileURLWithPath: args[2]).standardizedFileURL.path
        return OperatorRequest(command: .modelsRoot, args: ["path": path])
    case ("models", "lane"):
        var a = ["id": operand()]
        if args.count >= 4 { a["lane"] = args[3] }
        return OperatorRequest(command: .modelsLane, args: a)
    case ("adapters", nil), ("adapters", "list"): return OperatorRequest(command: .adaptersList)
    case ("adapters", "add"):
        var a = ["url": operand()]
        var rest = Array(args.dropFirst(3))
        while let flag = rest.first, flag.hasPrefix("--"), rest.count >= 2 {
            let key = String(flag.dropFirst(2))
            guard ["model", "file", "id", "title", "trigger", "format", "strength", "notes"].contains(key) else { fail(usage) }
            a[key] = rest[1]
            rest.removeFirst(2)
        }
        guard rest.isEmpty, a["model"] != nil else { fail(usage) }
        return OperatorRequest(command: .adaptersAdd, args: a)
    case ("adapters", "enable"): return OperatorRequest(command: .adaptersEnable, args: ["id": operand()])
    case ("adapters", "disable"): return OperatorRequest(command: .adaptersDisable, args: ["id": operand()])
    case ("adapters", "remove"): return OperatorRequest(command: .adaptersRemove, args: ["id": operand()])
    case ("update", "--check"): return OperatorRequest(command: .updateCheck)
    case ("update", "--rollback"): return OperatorRequest(command: .updateRollback)
    case ("update", "--cancel"): return OperatorRequest(command: .updateCancel)
    case ("update", "--prereleases"):
        return OperatorRequest(command: .updatePrereleases, args: args.count >= 3 ? ["value": args[2]] : [:])
    case ("update", nil): return OperatorRequest(command: .updateInstall)
    case ("update", let version?) where !version.hasPrefix("-"):
        return OperatorRequest(command: .updateInstall, args: ["version": version])
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
