import Foundation

/// Gaea's local operator API (G-17, Plan §2.1): JSON lines over a Unix socket in Gaea's own folder, readable only by
/// the user who runs Gaea. The server checks each caller's audit token. Nothing here is reachable from the network;
/// MES clients never configure a server.
///
/// One request per line, one response per line:
///
///     {"id":"1","command":"plugins.add","args":{"repo":"https://github.com/xocialize/gaea-plugin-demo"}}
///     {"id":"1","ok":true,"text":"Installed …","json":"{…}"}
public enum OperatorAPI {
    /// The socket's file name inside Gaea's Application Support folder.
    public static let socketName = "operator.sock"

    /// The commands the server answers.
    public enum Command: String, Codable, Sendable, CaseIterable {
        case status
        case logs
        case pluginsList = "plugins.list"
        case pluginsAdd = "plugins.add"
        case pluginsCheck = "plugins.check"
        case pluginsUpdate = "plugins.update"
        case pluginsRollback = "plugins.rollback"
        case pluginsEnable = "plugins.enable"
        case pluginsDisable = "plugins.disable"
        case pluginsRemove = "plugins.remove"
        case pluginsLogs = "plugins.logs"
        case modelsList = "models.list"
        case modelsEnable = "models.enable"
        case modelsDisable = "models.disable"
        /// The shared weights folder: `path` sets it, `path` = `default` returns to MLXEngine's store, none reads it.
        case modelsRoot = "models.root"
        /// A model's default lane (MEM-7): `id` the model, `lane` sets it, `lane` = `default` returns to the manifest's
        /// default, none reads it.
        case modelsLane = "models.lane"
        case ledger
    }
}

public struct OperatorRequest: Codable, Sendable {
    public var id: String
    public var command: String
    public var args: [String: String]

    public init(id: String = UUID().uuidString, command: OperatorAPI.Command, args: [String: String] = [:]) {
        self.id = id
        self.command = command.rawValue
        self.args = args
    }
}

public struct OperatorResponse: Codable, Sendable {
    public var id: String
    public var ok: Bool
    /// What a person reads.
    public var text: String
    /// The same answer as JSON, for scripts (`gaea --json`).
    public var json: String?
    public var error: String?

    public init(id: String, ok: Bool, text: String, json: String? = nil, error: String? = nil) {
        self.id = id
        self.ok = ok
        self.text = text
        self.json = json
        self.error = error
    }

    public static func failure(_ id: String, _ message: String) -> OperatorResponse {
        OperatorResponse(id: id, ok: false, text: message, error: message)
    }
}

/// Where Gaea keeps its files. `GAEA_HOME` moves the Application Support folder (tests, a second instance).
public enum GaeaHome {
    public static var applicationSupport: URL {
        if let home = ProcessInfo.processInfo.environment["GAEA_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Gaea", directoryHint: .isDirectory)
    }

    public static var socket: URL { applicationSupport.appending(path: OperatorAPI.socketName) }
}
