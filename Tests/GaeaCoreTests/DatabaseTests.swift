import Foundation
import GaeaProtocol
import MESEngineCore
import Testing
@testable import GaeaCore

@Suite struct DatabaseTests {
    @Test func theEnabledSetLivesInGaeaSqlite() throws {
        let database = try GaeaDatabase()
        let enablement = try ModelEnablement(store: DatabaseEnablementStore(database))
        try enablement.set("demo-matmul", enabled: false, optIn: false)
        try enablement.set("research-model", enabled: true, optIn: true)
        let reloaded = try ModelEnablement(store: DatabaseEnablementStore(database))
        #expect(!reloaded.isEnabled("demo-matmul", optIn: false))
        #expect(reloaded.isEnabled("research-model", optIn: true))
        #expect(reloaded.acceptedAt("research-model") != nil)
        #expect(reloaded.isEnabled("something-else", optIn: false))
    }

    /// GPP-1 §3.6 through the host's handler: namespaced per plugin, key order, prefix, after, more, the 1 MiB cap.
    @Test func pluginStoresAreNamespacedAndOrdered() throws {
        let database = try GaeaDatabase()
        func call(_ type: String, _ fields: [String: JSONValue], plugin: String = "p1") throws -> [String: JSONValue] {
            var message = fields
            message["namespace"] = "presets"
            return try Scheduler.storage(type, message, plugin: plugin, database: database)
        }
        for key in ["b", "a", "c", "ab"] { _ = try call("storage.put", ["key": .string(key), "value": ["k": .string(key)]]) }
        _ = try call("storage.put", ["key": "a", "value": "other plugin"], plugin: "p2")
        #expect(try call("storage.get", ["key": "a"]) == ["found": true, "value": ["k": "a"]])
        #expect(try call("storage.get", ["key": "zz"]) == ["found": false])
        let page = try call("storage.query", ["limit": 2])
        #expect(page["items"]?.arrayValue?.compactMap { $0["key"]?.stringValue } == ["a", "ab"])
        #expect(page["more"] == true)
        let prefixed = try call("storage.query", ["prefix": "a"])
        #expect(prefixed["items"]?.arrayValue?.count == 2)
        let after = try call("storage.query", ["after": "ab"])
        #expect(after["items"]?.arrayValue?.compactMap { $0["key"]?.stringValue } == ["b", "c"])
        _ = try call("storage.delete", ["key": "a"])
        #expect(try call("storage.get", ["key": "a"]) == ["found": false])
        #expect(try call("storage.get", ["key": "a"], plugin: "p2") == ["found": true, "value": "other plugin"])
        let huge = JSONValue.string(String(repeating: "x", count: GPP.maxStorageValueBytes))
        #expect(throws: WorkerFailure.self) { try call("storage.put", ["key": "big", "value": huge]) }
    }

    @Test func pluginRowsAndVersions() throws {
        let database = try GaeaDatabase()
        let v1 = GaeaDatabase.VersionRecord(version: "0.2.0", bundlePath: "/x/0.2.0/demo.gaeaplugin", zipSHA256: "a", manifestSHA256: "b",
                                            signature: "Developer ID", notarized: false)
        try database.insertPlugin(id: "com.example.p", repo: "https://github.com/o/r", title: "P", summary: "", team: GPP.trustedTeam, version: v1)
        try database.updatePlugin("com.example.p") { $0.previousVersion = "0.1.0"; $0.enabled = false }
        let row = try #require(try database.plugin("com.example.p"))
        #expect(row.activeVersion == "0.2.0" && row.previousVersion == "0.1.0" && !row.enabled)
        #expect(try database.versions(of: "com.example.p").map(\.version) == ["0.2.0"])
        try database.deletePlugin("com.example.p")
        #expect(try database.versions(of: "com.example.p").isEmpty)
    }

    /// G-19: two servers on one Mac don't share an engine id; an install that existed keeps the one its clients paired with.
    @Test func eachInstallKeepsAnEngineIDOfItsOwn() throws {
        let a = try GaeaDatabase(), b = try GaeaDatabase(), old = try GaeaDatabase()
        let idA = GaeaHost.engineID(a, installed: false), idB = GaeaHost.engineID(b, installed: false)
        #expect(idA != idB && idA.hasPrefix("eng_gaea_") && idA.count > idB.split(separator: "_").dropLast().joined(separator: "_").count)
        #expect(GaeaHost.engineID(a, installed: false) == idA)              // kept
        let legacy = GaeaHost.engineID(old, installed: true)
        #expect(!legacy.isEmpty && GaeaHost.engineID(old, installed: false) == legacy)
        #expect(try old.setting(GaeaHost.engineIDSetting) == legacy)
    }
}
