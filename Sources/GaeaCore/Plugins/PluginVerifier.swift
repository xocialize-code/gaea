import Foundation
import GaeaProtocol
import LightweightCodeRequirements
import Security

/// Trust comes from the signature, never the URL (G-7, G-18). v1 trusts one team, ours (G-22): `GPP.trustedTeam`.
/// The check runs at install and again before every launch (PLG-3), and the launch itself carries a
/// `launchRequirement` the kernel enforces at exec.
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
        /// A valid Developer ID signature from a team v1 doesn't run (G-22).
        case untrustedTeam(String)
        case noHardenedRuntime

        public var description: String {
            switch self {
            case .notDeveloperID(let why): "Refused: the bundle isn't signed with a Developer ID (\(why))."
            case .invalid(let why): "Refused: the bundle's signature is invalid (\(why))."
            case .untrustedTeam(let team):
                "Refused: the bundle is signed by team \(team). Gaea v1 runs only plugins signed by \(GPP.trustedTeam); "
                    + "third-party plugins come with the trust list in a later release (G-22)."
            case .noHardenedRuntime: "Refused: the bundle's signature has no hardened runtime."
            }
        }
    }

    /// The requirement every plugin must meet: Apple-anchored Developer ID, leaf issued to the trusted team.
    public static func requirementText(team: String = GPP.trustedTeam) -> String {
        "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists "
            + "and certificate leaf[field.1.2.840.113635.100.6.1.13] exists "
            + "and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// Checks the bundle statically: every architecture, strict, nested code, then the team requirement.
    public static func verify(_ bundle: URL) throws -> Signature {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else {
            throw Refusal.notDeveloperID("not code")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)

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

        var requirement: SecRequirement?
        SecRequirementCreateWithString(requirementText() as CFString, [], &requirement)
        let developerID = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists "
            + "and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        var developerIDRequirement: SecRequirement?
        SecRequirementCreateWithString(developerID as CFString, [], &developerIDRequirement)
        guard SecStaticCodeCheckValidity(code, flags, developerIDRequirement) == errSecSuccess else {
            throw Refusal.notDeveloperID("signed by \(commonName ?? team), not a Developer ID Application certificate")
        }
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw Refusal.untrustedTeam(team)
        }
        let codeFlags = (dict[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        guard codeFlags & 0x10000 != 0 else { throw Refusal.noHardenedRuntime } // CS_RUNTIME

        var notarizedRequirement: SecRequirement?
        SecRequirementCreateWithString("notarized" as CFString, [], &notarizedRequirement)
        let notarized = SecStaticCodeCheckValidity(code, flags, notarizedRequirement) == errSecSuccess
        return Signature(team: team, identifier: identifier, commonName: commonName, notarized: notarized)
    }

    /// The requirement a worker launch carries: the kernel kills an executable that doesn't meet it (spike check 11).
    public static func launchRequirement() throws -> LaunchCodeRequirement {
        try LaunchCodeRequirement.allOf {
            TeamIdentifier(GPP.trustedTeam)
            ValidationCategory(.developerID)
        }
    }
}
