import CryptoKit
import Foundation
import Security

struct CatalogEntry: Codable, Identifiable {
    var id: String
    var version: String
    var url: URL
    var sha256: String
    var teamID: String
    var bundleName: String   // e.g. demo.gaeaplugin
    var executable: String   // Contents/MacOS/<executable>
}

struct Catalog: Codable { var plugins: [CatalogEntry] }

struct InstalledPlugin {
    var entry: CatalogEntry
    var bundleURL: URL
    var executableURL: URL { bundleURL.appendingPathComponent("Contents/MacOS/\(entry.executable)") }
}

enum QuarantinePolicy: String {
    /// Leave whatever the download produced (URLSession in a non-sandboxed app sets none).
    case asDownloaded
    /// Pretend the zip came from a browser: quarantine it before extracting (ditto propagates it).
    case simulateBrowser
    /// Like simulateBrowser, then strip quarantine from the bundle once our own signature check passes.
    case simulateBrowserThenStrip
}

struct InstallReport {
    var downloadQuarantined: Bool
    var bundleQuarantined: Bool
    var signature: String
}

enum InstallError: Error, CustomStringConvertible {
    case checksum(expected: String, actual: String)
    case signature(String)
    case extract(Int32)
    var description: String {
        switch self {
        case let .checksum(e, a): return "sha256 mismatch: expected \(e.prefix(12))…, got \(a.prefix(12))…"
        case let .signature(s): return "signature rejected: \(s)"
        case let .extract(c): return "ditto failed (\(c))"
        }
    }
}

final class PluginInstaller {
    let root: URL

    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GaeaPluginSpike/Plugins")) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func fetchCatalog(_ url: URL) async throws -> Catalog {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    func install(_ entry: CatalogEntry, quarantine: QuarantinePolicy) async throws -> (InstalledPlugin, InstallReport) {
        let (tmp, _) = try await URLSession.shared.download(from: entry.url)
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("\(entry.id)-\(entry.version).zip")
        try? FileManager.default.removeItem(at: zip)
        try FileManager.default.moveItem(at: tmp, to: zip)
        let downloadQuarantined = Self.isQuarantined(zip)

        let digest = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard digest == entry.sha256.lowercased() else { throw InstallError.checksum(expected: entry.sha256, actual: digest) }

        if quarantine != .asDownloaded { Self.setQuarantine(zip) }

        let dest = root.appendingPathComponent("\(entry.id)/\(entry.version)")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, dest.path]
        try ditto.run(); ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw InstallError.extract(ditto.terminationStatus) }

        let plugin = InstalledPlugin(entry: entry, bundleURL: dest.appendingPathComponent(entry.bundleName))
        let signature = try Self.verify(plugin.bundleURL, teamID: entry.teamID)
        if quarantine == .simulateBrowserThenStrip { Self.stripQuarantine(dest) }
        return (plugin, InstallReport(downloadQuarantined: downloadQuarantined,
                                      bundleQuarantined: Self.isQuarantined(plugin.executableURL),
                                      signature: signature))
    }

    /// Accept only a valid, sealed Developer ID signature from our team, nested code included.
    static func verify(_ bundle: URL, teamID: String) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else {
            throw InstallError.signature("not code")
        }
        let text = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists "
            + "and certificate leaf[field.1.2.840.113635.100.6.1.13] exists "
            + "and certificate leaf[subject.OU] = \"\(teamID)\""
        var requirement: SecRequirement?
        SecRequirementCreateWithString(text as CFString, [], &requirement)
        var error: Unmanaged<CFError>?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, requirement, &error)
        guard status == errSecSuccess else {
            let why = error?.takeRetainedValue().localizedDescription ?? "OSStatus \(status)"
            throw InstallError.signature(why)
        }
        var info: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let dict = info as? [String: Any] ?? [:]
        return "Developer ID, team \(dict[kSecCodeInfoTeamIdentifier as String] ?? "?"), id \(dict[kSecCodeInfoIdentifier as String] ?? "?")"
    }

    static func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    static func setQuarantine(_ url: URL) {
        let value = "0081;\(String(Int(Date().timeIntervalSince1970), radix: 16));Safari;"
        _ = value.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, XATTR_NOFOLLOW) }
    }

    static func stripQuarantine(_ dir: URL) {
        let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        removexattr(dir.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        while let url = walker?.nextObject() as? URL { removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW) }
    }
}

/// "Check for a newer version": the latest GitHub release of a repo, by tag.
enum UpdateChecker {
    static func latestRelease(_ repo: String) async throws -> (tag: String, assets: [String]) {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let assets = (json["assets"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        return (json["tag_name"] as? String ?? "?", assets)
    }
}
