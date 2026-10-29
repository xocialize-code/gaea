import AppKit
import Foundation
import GaeaCore

// Gaea — the MES media server whose models are plugins.
//
//   Gaea                       the menu bar item and console, serving MES (UI-1, UI-2)
//   Gaea --headless            the server alone, for a studio Mac at login (SRV-10)
//   Gaea --snapshot <dir>      render the console's Plugins, Models and System pages and Settings' Adapters tab to PNGs, then quit
//
//   --port N (17630)  --paired [--host 0.0.0.0] [--approve-pairings]  --no-advertise  --budget-bytes N
//   --outputs-ttl S  --idle-seconds S  --models-root <folder> (this launch only; `gaea models root` keeps one)
//
// Configuration happens here, in Gaea's own UI, or with the `gaea` CLI on this Mac (G-17). MES clients can't
// configure it. GAEA_HOME moves Gaea's folder; GAEA_GITHUB_TOKEN reads private plugin repos (never stored).

setvbuf(stdout, nil, _IOLBF, 0)

struct Launch {
    var options = GaeaHost.Options()
    var headless = false
    var snapshot: URL?
    var approvePairings = false

    init(_ arguments: [String]) {
        var args = arguments.makeIterator()
        while let arg = args.next() {
            switch arg {
            case "--headless": headless = true
            case "--snapshot": snapshot = args.next().map { URL(fileURLWithPath: $0) }
            case "--port": options.port = Int(args.next() ?? "") ?? options.port
            case "--paired": options.paired = true
            case "--host": options.bindHost = args.next()
            case "--no-advertise": options.advertise = false
            case "--budget-bytes": options.budgetBytes = args.next().flatMap(UInt64.init)
            case "--models-root": options.modelsRoot = args.next().map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            case "--idle-seconds": options.idleTimeout = .seconds(Int(args.next() ?? "") ?? 900)
            case "--outputs-ttl": options.outputsTTLSeconds = args.next().flatMap(Int.init)
            // Headless only: pre-approve every pairing (development, unattended hosts). The app asks its operator.
            case "--approve-pairings":
                approvePairings = true
                options.pairingApproval = { _ in true }
            case _ where arg.hasPrefix("-NS") || arg.hasPrefix("-Apple"): _ = args.next() // AppKit's own defaults
            default:
                FileHandle.standardError.write(Data("Gaea: unknown argument \(arg)\n".utf8))
                exit(2)
            }
        }
    }
}

let launch = Launch(Array(CommandLine.arguments.dropFirst()))

if launch.headless {
    let host: GaeaHost
    do { host = try GaeaHost(options: launch.options) } catch {
        FileHandle.standardError.write(Data("Gaea: \(error)\n".utf8))
        exit(1)
    }
    let serving = Task {
        do {
            try await host.run { _ in print("gaea \(Gaea.version) serving MES at \(host.endpoint ?? "?"); operator API at \(host.paths.socket.path)") }
        } catch is CancellationError {
        } catch {
            FileHandle.standardError.write(Data("Gaea: \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }
    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    var sources: [DispatchSourceSignal] = []
    for sig in [SIGTERM, SIGINT] {
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { serving.cancel() }
        source.resume()
        sources.append(source)
    }
    dispatchMain()
}

let app = NSApplication.shared
let delegate = AppDelegate(launch: launch)
app.delegate = delegate
app.setActivationPolicy(launch.snapshot == nil ? .accessory : .prohibited)
app.run()
