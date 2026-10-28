import Foundation

/// A semantic version (`1.2.3`, `0.2.0-beta.1`), as plugin tags and `min_gaea` use them. A leading `v` is dropped.
public struct SemVer: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int
    public var prerelease: [String]

    public init?(_ text: String) {
        var s = Substring(text.trimmingCharacters(in: .whitespaces))
        if s.first == "v" || s.first == "V" { s = s.dropFirst() }
        let core = s.split(separator: "+", maxSplits: 1).first ?? ""
        let parts = core.split(separator: "-", maxSplits: 1)
        let numbers = parts.first?.split(separator: ".").map { Int($0) } ?? []
        guard numbers.count == 3, let major = numbers[0], let minor = numbers[1], let patch = numbers[2] else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        prerelease = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
    }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    public static func < (a: SemVer, b: SemVer) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) {
            return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
        // A pre-release sorts before its release.
        if a.prerelease.isEmpty != b.prerelease.isEmpty { return !a.prerelease.isEmpty }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            switch (Int(x), Int(y)) {
            case let (i?, j?): return i < j
            case (.some, nil): return true
            case (nil, .some): return false
            default: return x < y
            }
        }
        return a.prerelease.count < b.prerelease.count
    }
}
