import Darwin
import Foundation

/// A blocking client for the operator API: connects to the socket, sends one request, reads one response.
public struct OperatorClient: Sendable {
    public var socket: URL

    public init(socket: URL = GaeaHome.socket) {
        self.socket = socket
    }

    public enum ClientError: Error, CustomStringConvertible {
        case notRunning(String)
        case io(String)

        public var description: String {
            switch self {
            case .notRunning(let path): "Gaea isn't running (no operator socket at \(path))."
            case .io(let message): message
            }
        }
    }

    public func send(_ request: OperatorRequest) throws -> OperatorResponse {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.io("socket: \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = socket.path
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw ClientError.io("socket path too long: \(path)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: Array(path.utf8) + [0])
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw ClientError.notRunning(path) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(request)
        line.append(0x0A)
        try line.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                guard n > 0 else { throw ClientError.io("write: \(String(cString: strerror(errno)))") }
                offset += n
            }
        }

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while !received.contains(0x0A) {
            let n = read(fd, &buffer, buffer.count)
            if n < 0 { throw ClientError.io("read: \(String(cString: strerror(errno)))") }
            if n == 0 { break }
            received.append(contentsOf: buffer[0..<n])
        }
        guard let newline = received.firstIndex(of: 0x0A) else {
            throw ClientError.io("Gaea closed the connection without answering (refused by its audit-token check?).")
        }
        return try JSONDecoder().decode(OperatorResponse.self, from: received[received.startIndex..<newline])
    }
}
