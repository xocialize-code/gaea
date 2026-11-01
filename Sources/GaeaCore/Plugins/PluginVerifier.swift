import Foundation
import GaeaProtocol
import LightweightCodeRequirements
import Security

/// Trust comes from the signature, never the URL (G-7, G-18). A plugin runs only when it's signed by a team on the trust
/// list (`TrustList`): Gaea's own, `GPP.trustedTeam`, and the teams the operator approved. The check runs at install and
/// again before every launch (PLG-3), and the launch itself carries a `launchRequirement` the kernel enforces at exec.
public enum PluginVerifier {
    public struct Signature: Sendable, Equatable, CustomStringConvertible {
        public var team: String
        public var identifier: String
        public var commonName: String?
        public var notarized: Bool
        public var description: String {
            "\(commonName ?? "Developer ID, team \(team)"), id \(identifier)\(notarized ? ", notarized" : ", not notarized"), hardened runtime"
        }

        /// The person or company on the certificate: "Dustin Nielson" from "Developer ID Application: Dustin Nielson (CFZS6RXUCP)".
        public static func holder(_ commonName: String) -> String? {
            guard let colon = commonName.range(of: ": "), let paren = commonName.range(of: " (", options: .backwards),
                  colon.upperBound <= paren.lowerBound else { return nil }
            return String(commonName[colon.upperBound..<paren.lowerBound])
        }
    }

    public enum Refusal: Error, Equatable, CustomStringConvertible {
        /// Not signed, or signed ad hoc: no Developer ID at all.
        case notDeveloperID(String)
        /// The seal is broken: something in the bundle changed after signing.
        case invalid(String)
        /// A valid Developer ID signature, with hardened runtime, from a team that isn't on the trust list. An install
        /// holds the release for the operator's answer instead of refusing it.
        case untrustedTeam(Signature)
        case noHardenedRuntime

        public var isUntrustedTeam: Bool { if case .untrustedTeam = self { true } else { false } }

        public var description: String {
            switch self {
            case .notDeveloperID(let why): "Refused: the bundle isn't signed with a Developer ID (\(why))."
            case .invalid(let why): "Refused: the bundle's signature is invalid (\(why))."
            case .untrustedTeam(let signature):
                "Refused: the bundle is signed by \(signature.commonName.flatMap(Signature.holder) ?? "team \(signature.team)") "
                    + "(\(signature.team)), a team this Gaea doesn't trust. Approve the team to run it: gaea trust."
            case .noHardenedRuntime: "Refused: the bundle's signature has no hardened runtime."
            }
        }
    }

    static let developerID = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists "
        + "and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"

    /// The requirement a team's code must meet: Apple-anchored Developer ID, leaf issued to that team. Gaea itself and
    /// the operator CLI are held to Gaea's own team, whatever the trust list says.
    public static func requirementText(team: String = GPP.trustedTeam) -> String {
        requirementText(teams: [team])
    }

    /// Developer ID, leaf issued to any one of `teams`.
    public static func requirementText(teams: some Collection<String>) -> String {
        let leaf = teams.sorted().map { "certificate leaf[subject.OU] = \"\($0)\"" }.joined(separator: " or ")
        return developerID + " and (\(leaf))"
    }

    /// Checks the bundle statically (every architecture, strict, nested code), then that a team in `teams` signed it.
    public static func verify(_ bundle: URL, trusting teams: Set<String>) throws -> Signature {
        let (code, signature) = try check(bundle)
        guard !teams.isEmpty else { throw Refusal.untrustedTeam(signature) }
        var requirement: SecRequirement?
        SecRequirementCreateWithString(requirementText(teams: teams) as CFString, [], &requirement)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw Refusal.untrustedTeam(signature)
        }
        return signature
    }

    static let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)

    /// The checks that don't depend on the trust list: the seal, a Developer ID Application certificate, hardened
    /// runtime, and whether Apple notarized it.
    static func check(_ bundle: URL) throws -> (SecStaticCode, Signature) {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else {
            throw Refusal.notDeveloperID("not code")
        }
        // First the seal alone, so a broken seal reads as tampering rather than a team problem.
        var error: Unmanaged<CFError>?
        let sealed = SecStaticCodeCheckValidityWithErrors(code, flags, nil, &error)
        guard sealed == errSecSuccess else {
            _ = error?.takeRetainedValue()
            if sealed == errSecCSUnsigned { throw Refusal.notDeveloperID("unsigned") }
            let why = (SecCopyErrorMessageString(sealed, nil) as String?) ?? "OSStatus \(sealed)"
            throw Refusal.invalid("\(why), OSStatus \(sealed)")
        }

        var info: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let dict = info as? [String: Any] ?? [:]
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let identifier = dict[kSecCodeInfoIdentifier as String] as? String ?? "?"
        let certificates = dict[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let commonName = certificates.first.flatMap { cert -> String? in
            var name: CFString?
            SecCertificateCopyCommonName(cert, &name)
            return name as String?
        }
        guard let team, !certificates.isEmpty else { throw Refusal.notDeveloperID("ad hoc signature, no team") }

        var developerIDRequirement: SecRequirement?
        SecRequirementCreateWithString(developerID as CFString, [], &developerIDRequirement)
        guard SecStaticCodeCheckValidity(code, flags, developerIDRequirement) == errSecSuccess else {
            throw Refusal.notDeveloperID("signed by \(commonName ?? team), not a Developer ID Application certificate")
        }
        let codeFlags = (dict[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        guard codeFlags & 0x10000 != 0 else { throw Refusal.noHardenedRuntime } // CS_RUNTIME

        var notarizedRequirement: SecRequirement?
        SecRequirementCreateWithString("notarized" as CFString, [], &notarizedRequirement)
        let notarized = SecStaticCodeCheckValidity(code, flags, notarizedRequirement) == errSecSuccess
        return (code, Signature(team: team, identifier: identifier, commonName: commonName, notarized: notarized))
    }

    /// The requirement a worker launch carries, pinned to the plugin's team, which the launch check just found trusted:
    /// the kernel kills an executable that doesn't meet it (spike check 11).
    public static func launchRequirement(team: String) throws -> LaunchCodeRequirement {
        try LaunchCodeRequirement.allOf {
            TeamIdentifier(team)
            ValidationCategory(.developerID)
        }
    }
}
