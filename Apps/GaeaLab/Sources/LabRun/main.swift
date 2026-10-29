import ArgumentParser
import Foundation
import GaeaLabCore
import MESClientKit
import MESCore
import PixelAgencyRun

/// `lab-run`: Gaea Lab's run workflow without a window (CLI-3). It does what a person does in Lab (pick an operation,
/// give inputs, controls and adapters, run, save the result) through the same `RunSession` over the same `EnginePool`,
/// so each job goes to the server that offers its model and adapters (G-19). The MES client conformance suite drives it
/// with one server:
///
///     mes-conformance client --command 'lab-run --engine {url} --operation image.generate --text prompt={prompt} --out {out}'
///
/// and recorded runs give several (`--engine` repeated) and print where each job went.
@main
struct LabRun: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lab-run",
        abstract: "Run one operation the way Gaea Lab does, over one or more servers, and save its results.")

    @Option(help: "A server's base URL (an open-mode engine). Repeatable: each job goes to the one that can run it.")
    var engine: [String]
    @Option(help: "The operation, e.g. image.generate.") var operation: String
    @Option(help: "A text input as name=value. Repeatable.") var text: [String] = []
    @Option(help: "A media input as name=path. Repeatable.") var file: [String] = []
    @Option(help: "A data input as name=JSON (e.g. points for image.segment). Repeatable.") var data: [String] = []
    @Option(help: "A parameter as name=JSON (or a plain string). Repeatable.") var param: [String] = []
    @Option(help: "A model id from the descriptor.") var model: String?
    @Option(help: "An adapter (LoRA) as id or id=strength. Repeatable.") var adapter: [String] = []
    @Option(help: "Where to save the results.") var out: String
    @Option(help: "Also write where the job ran, and its provenance, as JSON here.") var report: String?

    @MainActor
    func run() async throws {
        let choices = AdapterChoices()
        let pool = EnginePool(adapters: choices.provider)
        var members: [EnginePool.Member] = []
        for text in engine {
            guard let url = URL(string: text) else { throw ValidationError("\(text) isn't a URL.") }
            let connection = HTTPEngineConnection(baseURL: url)
            let info = try await connection.engineInfo()
            // Jobs are routed by id: two servers that answer with the same one (Gaea before 0.7.0, on one Mac) are told
            // apart by address.
            let address = "\(url.host() ?? ""):\(url.port ?? 0)"
            let id = members.contains { $0.id == info.id } ? "\(info.id)@\(address)" : info.id
            members.append(.init(id: id, name: "\(info.name) (\(address))", connection: connection))
        }
        await pool.setMembers(members)
        let info = try await pool.engineInfo()
        guard let descriptor = try await pool.operations().operations.first(where: { $0.operation == operation }) else {
            throw ValidationError("No server offers \(operation).")
        }
        choices.set(try adapter.map { pair in
            guard let eq = pair.firstIndex(of: "=") else { return AdapterRequest(id: pair) }
            guard let strength = Double(pair[pair.index(after: eq)...]) else { throw ValidationError("--adapter \(pair): strength isn't a number.") }
            return AdapterRequest(id: String(pair[..<eq]), strength: strength)
        }, for: operation)

        let session = SessionLog()
        defer { session.clear() }
        let run = RunSession(engine: pool, engineInfo: info, descriptor: descriptor, folder: session.folder)
        for pair in text {
            let (name, value) = try Self.split(pair)
            run.form.text[name] = value
        }
        for pair in file {
            let (name, path) = try Self.split(pair)
            run.media[name, default: []].append(MediaItem(file: URL(fileURLWithPath: (path as NSString).expandingTildeInPath)))
        }
        for pair in data {
            let (name, value) = try Self.split(pair)
            guard let json = try? MESJSON.decoder.decode(JSONValue.self, from: Data(value.utf8)) else {
                throw ValidationError("--data \(name) isn't JSON.")
            }
            run.data[name] = json
        }
        for pair in param {
            let (name, value) = try Self.split(pair)
            run.form.setValue((try? MESJSON.decoder.decode(JSONValue.self, from: Data(value.utf8))) ?? .string(value), at: [name])
        }
        run.form.model = model
        if let missing = run.missingInputs.first { throw ValidationError("\(operation) needs input '\(missing.name)'.") }

        await run.run()
        let route = run.job.flatMap { pool.route(of: $0.id) }
        if let route { print("ran on \(route.engineName)\(route.model.map { " · picked for \($0)" } ?? "")") }
        switch run.phase {
        case .finished:
            let folder = URL(fileURLWithPath: (out as NSString).expandingTildeInPath, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for result in run.results { print("saved \(try ResultExporter.save(result, to: folder).path)") }
            let provenance = run.results.first?.provenance
            if let p = provenance {
                print("model \(p.model.id) · \(p.model.license.spdx)"
                      + (p.adapters ?? []).map { " · adapter \($0.id) \($0.strength) @\($0.revision?.prefix(12) ?? "")" }.joined())
            }
            if let report {
                let record: [String: JSONValue] = [
                    "operation": .string(operation),
                    "engine": route.map { .string($0.engineName) } ?? .null,
                    "engine_id": route.map { .string($0.engineID) } ?? .null,
                    "resident": route.map { .bool($0.resident) } ?? .null,
                    "queue_depth": route.map { .number(Double($0.queueDepth)) } ?? .null,
                    "job": run.job.map { .string($0.id) } ?? .null,
                    "provenance": provenance.flatMap { p in try? MESJSON.decoder.decode(JSONValue.self, from: MESJSON.encoder.encode(p)) } ?? .null,
                ]
                try MESJSON.encoder.encode(JSONValue.object(record)).write(to: URL(fileURLWithPath: report))
            }
        case .failed(let message):
            FileHandle.standardError.write(Data("failed: \(message)\n".utf8))
            throw ExitCode.failure
        case .cancelled:
            FileHandle.standardError.write(Data("cancelled\n".utf8))
            throw ExitCode.failure
        default:
            throw ExitCode.failure
        }
    }

    static func split(_ pair: String) throws -> (String, String) {
        guard let eq = pair.firstIndex(of: "=") else { throw ValidationError("Expected name=value, got '\(pair)'.") }
        return (String(pair[..<eq]), String(pair[pair.index(after: eq)...]))
    }
}
