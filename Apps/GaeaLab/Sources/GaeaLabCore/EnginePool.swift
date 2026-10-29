import Foundation
import MESClientKit
import MESCore
import Synchronization

/// Every server Gaea Lab knows, as one engine (G-19, CLI-2). Its operations are the servers' together, each with every
/// model any of them offers, so a run can name a model only one server has. Each job goes where MESClientKit's
/// `EnginePicker` sends it: a server that offers the operation, the model and the adapters, preferring one with the
/// model resident and a short queue. Everything after the submit (events, the job, downloads, confirm) goes to that
/// server.
///
/// Uploads wait: until the picker chooses, there is no server to send a file to. `upload` keeps the file and hands back
/// a pending id, and `submit` sends each pending file to the chosen server before the request.
public final class EnginePool: EngineConnection, Sendable {
    /// One server in the pool.
    public struct Member: Sendable {
        public var id: String
        public var name: String
        public var connection: any EngineConnection

        public init(id: String, name: String, connection: any EngineConnection) {
            self.id = id; self.name = name; self.connection = connection
        }
    }

    /// Where one job ran.
    public struct Route: Sendable, Equatable {
        public var engineID: String
        public var engineName: String
        /// The model the picker expected the server to run (the job's provenance says what did).
        public var model: String?
        public var resident: Bool
        public var queueDepth: Int
    }

    struct State {
        var members: [Member] = []
        var jobs: [String: String] = [:]                        // job id → member id
        var routes: [String: Route] = [:]
        var pending: [String: (file: URL, mediaType: String)] = [:]
    }

    public let id: String
    public let name: String
    public let picker = EnginePicker()
    private let state = Mutex(State())
    /// The adapters a request gets when it names none: Gaea Lab's LoRA panel, or `lab-run --adapter`.
    private let adapterChoice: @Sendable (JobRequest) -> [AdapterRequest]?

    static let pendingPrefix = "lab-pending-"

    public init(id: String = "eng_gaea_lab_pool", name: String = "Every server",
                adapters: @escaping @Sendable (JobRequest) -> [AdapterRequest]? = { _ in nil }) {
        self.id = id
        self.name = name
        self.adapterChoice = adapters
    }

    public var members: [Member] { state.withLock { $0.members } }

    public func setMembers(_ members: [Member]) async {
        state.withLock { $0.members = members }
        await picker.setCandidates(members.map { EngineCandidate(id: $0.id, name: $0.name, connection: $0.connection) })
    }

    /// Where `job` ran, once submitted through the pool.
    public func route(of job: String) -> Route? { state.withLock { $0.routes[job] } }

    func member(for job: String) throws -> any EngineConnection {
        try state.withLock { s in
            guard let id = s.jobs[job], let member = s.members.first(where: { $0.id == id }) else {
                throw MESClientError.unexpected("Gaea Lab didn't submit job \(job).")
            }
            return member.connection
        }
    }

    // MARK: - The pool as one engine

    /// The first reachable server's handshake, named for the pool; the smallest inline limit, so an inline input fits
    /// wherever the job goes.
    public func engineInfo() async throws -> EngineInfo {
        var infos: [EngineInfo] = []
        for member in members {
            if let info = try? await member.connection.engineInfo() { infos.append(info) }
        }
        guard var info = infos.first else { throw MESClientError.unexpected("Gaea Lab knows no reachable server yet.") }
        info.id = id
        info.name = "\(name) (\(infos.count))"
        info.limits.maxInlineBytes = infos.map(\.limits.maxInlineBytes).min() ?? info.limits.maxInlineBytes
        info.limits.maxUploadBytes = infos.map(\.limits.maxUploadBytes).min() ?? info.limits.maxUploadBytes
        return info
    }

    /// Each operation once, with every model a server offers for it (the first server's offer of a model wins).
    public func operations() async throws -> OperationsList {
        var lists: [OperationsList] = []
        for member in members {
            if let list = try? await member.connection.operations() { lists.append(list) }
        }
        return Self.merged(lists)
    }

    static func merged(_ lists: [OperationsList]) -> OperationsList {
        var order: [String] = []
        var byOperation: [String: Descriptor] = [:]
        for list in lists {
            for descriptor in list.operations {
                guard var known = byOperation[descriptor.operation] else {
                    order.append(descriptor.operation)
                    byOperation[descriptor.operation] = descriptor
                    continue
                }
                for model in descriptor.models where !known.models.contains(where: { $0.id == model.id }) {
                    known.models.append(model)
                }
                byOperation[descriptor.operation] = known
            }
        }
        return OperationsList(operations: order.compactMap { byOperation[$0] }, etag: lists.map(\.etag).joined(separator: "+"))
    }

    public func health() async throws -> Health {
        var last: (any Error)?
        for member in members {
            do { return try await member.connection.health() } catch { last = error }
        }
        throw last ?? MESClientError.unexpected("Gaea Lab knows no server yet.")
    }

    /// Keeps the file until `submit` knows the server.
    public func upload(contentsOf file: URL, mediaType: String) async throws -> Upload {
        let id = Self.pendingPrefix + UUID().uuidString.lowercased()
        state.withLock { $0.pending[id] = (file, mediaType) }
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Upload(uploadID: id, mediaType: mediaType, bytes: bytes, sha256: "", expiresAt: Date().addingTimeInterval(3600))
    }

    /// Chooses the server, sends it the pending files, and submits there.
    public func submit(_ request: JobRequest, idempotencyKey: String?) async throws -> Job {
        var request = request
        if request.adapters == nil, let adapters = adapterChoice(request), !adapters.isEmpty { request.adapters = adapters }
        let choice = try await picker.choose(for: request)
        let connection = choice.candidate.connection
        if let inputs = request.inputs {
            var sent: [String: RequestInput] = [:]
            for (name, input) in inputs { sent[name] = try await resolve(input, on: connection) }
            request.inputs = sent
        }
        let job = try await connection.submit(request, idempotencyKey: idempotencyKey)
        state.withLock {
            $0.jobs[job.id] = choice.candidate.id
            $0.routes[job.id] = Route(engineID: choice.candidate.id, engineName: choice.candidate.name, model: choice.model,
                                      resident: choice.resident, queueDepth: choice.queueDepth)
        }
        return job
    }

    func resolve(_ input: RequestInput, on connection: any EngineConnection) async throws -> RequestInput {
        switch input {
        case .text: return input
        case .one(let value): return .one(try await resolve(value, on: connection))
        case .many(let values):
            var resolved: [InputValue] = []
            for value in values { resolved.append(try await resolve(value, on: connection)) }
            return .many(resolved)
        }
    }

    func resolve(_ value: InputValue, on connection: any EngineConnection) async throws -> InputValue {
        guard case .upload(let id) = value, id.hasPrefix(Self.pendingPrefix) else { return value }
        guard let pending = state.withLock({ $0.pending.removeValue(forKey: id) }) else {
            throw MESClientError.unexpected("Gaea Lab lost the file for upload \(id).")
        }
        return .upload(try await connection.upload(contentsOf: pending.file, mediaType: pending.mediaType).uploadID)
    }

    public func job(_ id: String, wait: Int) async throws -> Job { try await member(for: id).job(id, wait: wait) }

    public func jobs(state jobState: JobState?) async throws -> [Job] {
        var all: [Job] = []
        for member in members { all += (try? await member.connection.jobs(state: jobState)) ?? [] }
        return all
    }

    public func release(_ id: String) async throws -> Job { try await member(for: id).release(id) }
    public func confirm(_ id: String) async throws -> Job { try await member(for: id).confirm(id) }

    public func download(job: String, output: Output, to destination: URL) async throws -> URL {
        try await member(for: job).download(job: job, output: output, to: destination)
    }

    public func events(job: String, after seq: Int) -> AsyncThrowingStream<Event, any Error> {
        do {
            return try member(for: job).events(job: job, after: seq)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }
}
