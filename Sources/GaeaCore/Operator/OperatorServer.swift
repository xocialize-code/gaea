import Darwin
import Foundation
import GaeaOperator
import GaeaProtocol
import Security
import Synchronization

/// Who is calling the operator API, from the connection's audit token.
public struct OperatorPeer: Sendable, CustomStringConvertible {
    public var pid: pid_t
    public var euid: uid_t
    /// The caller's code met the team requirement.
    public var signedByTeam: Bool
    public var description: String { "pid \(pid), uid \(euid)\(signedByTeam ? ", Developer ID \(GPP.trustedTeam)" : "")" }
}

/// The local operator API (G-17): a Unix socket in Gaea's own folder (mode 0700), itself mode 0600. No network
/// listener exists for it, so nothing off this Mac can reach it. Each connection's audit token is checked:
///
/// - the caller runs as the same user as Gaea, always;
/// - when Gaea itself is signed by the trusted team (a release build), the caller must be too (the `gaea` CLI is).
///   A development build, unsigned, accepts any same-user caller and says so in `gaea status`.
public final class OperatorServer: Sendable {
    public enum Policy: String, Sendable {
        case sameUser = "same user"
        case sameUserAndTeam = "same user, Developer ID team"
    }

    public let socket: URL
    public let policy: Policy
    let handler: @Sendable (OperatorRequest, OperatorPeer) async -> OperatorResponse
    let log: HostLog
    private let listener = Mutex<Int32>(-1)

    public init(socket: URL, log: HostLog, policy: Policy? = nil,
                handler: @escaping @Sendable (OperatorRequest, OperatorPeer) async -> OperatorResponse) {
        self.socket = socket
        self.log = log
        self.handler = handler
        self.policy = policy ?? (Self.selfIsSignedByTeam() ? .sameUserAndTeam : .sameUser)
    }

    /// Whether this process's own code is Developer ID-signed by the trusted team.
    static func selfIsSignedByTeam() -> Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        SecRequirementCreateWithString(PluginVerifier.requirementText() as CFString, [], &requirement)
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    public enum ServerError: Error, CustomStringConvertible {
        case alreadyRunning(String)
        case posix(String)
        public var description: String {
            switch self {
            case .alreadyRunning(let path): "Another Gaea is answering on \(path)."
            case .posix(let message): message
            }
        }
    }

    public func start() throws {
        let path = socket.path
        if FileManager.default.fileExists(atPath: path) {
            if (try? OperatorClient(socket: socket).send(OperatorRequest(command: .status))) != nil {
                throw ServerError.alreadyRunning(path)
            }
            unlink(path)
        }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.posix("socket: \(String(cString: strerror(errno)))") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw ServerError.posix("socket path too long: \(path)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let previous = umask(0o177)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(previous)
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw ServerError.posix("bind \(path): \(message)")
        }
        listener.withLock { $0 = fd }
        log("operator: listening on \(path) (\(policy.rawValue))")
        let thread = Thread { [self] in acceptLoop(fd) }
        thread.name = "gaea.operator"
        thread.start()
    }

    public func stop() {
        let fd = listener.withLock { fd in defer { fd = -1 }; return fd }
        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            close(fd)
            unlink(socket.path)
        }
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            Task.detached { [self] in await serve(client) }
        }
    }

    /// The caller's identity from `LOCAL_PEERTOKEN`, checked against the policy.
    func peer(_ fd: Int32) -> OperatorPeer? {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0 else { return nil }
        // audit_token_t: [auid, euid, egid, ruid, rgid, pid, asid, pidversion]
        let euid = uid_t(token.val.1)
        let pid = pid_t(bitPattern: token.val.5)
        let tokenData = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        var signed = false
        if SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: tokenData] as CFDictionary, [], &code) == errSecSuccess,
           let code {
            var requirement: SecRequirement?
            SecRequirementCreateWithString(PluginVerifier.requirementText() as CFString, [], &requirement)
            signed = SecCodeCheckValidity(code, [], requirement) == errSecSuccess
        }
        return OperatorPeer(pid: pid, euid: euid, signedByTeam: signed)
    }

    private func serve(_ fd: Int32) async {
        defer { close(fd) }
        guard let peer = peer(fd) else {
            log("operator: refused a connection without an audit token")
            return
        }
        guard peer.euid == geteuid() else {
            log("operator: refused \(peer): another user")
            return
        }
        if policy == .sameUserAndTeam, !peer.signedByTeam {
            log("operator: refused \(peer): not signed by \(GPP.trustedTeam)")
            return
        }
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while !received.contains(0x0A), received.count < 1 << 20 {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            received.append(contentsOf: buffer[0..<n])
        }
        guard let newline = received.firstIndex(of: 0x0A),
              let request = try? JSONDecoder().decode(OperatorRequest.self, from: received[received.startIndex..<newline]) else {
            return
        }
        let response = await handler(request, peer)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var line = try? encoder.encode(response) else { return }
        line.append(0x0A)
        line.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n <= 0 { return }
                offset += n
            }
        }
    }
}
