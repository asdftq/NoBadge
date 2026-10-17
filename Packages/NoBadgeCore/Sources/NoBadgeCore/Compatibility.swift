import Foundation

/// OS families select an adapter; settings schemas and transaction readback
/// still have to pass at runtime. A patch build number is not an API contract.
public struct CompatibilityManifest: Decodable, Sendable {
    public let adapterID: String
    public let qualifiedTargets: [QualifiedTarget]
    public let profiles: [CompatibilityProfile]

    public func profile(for version: OperatingSystemVersion, osBuild: String,
                        architecture: String) -> CompatibilityProfile? {
        guard adapterID == "usernoted-badge-v1" else { return nil }
        let matches = profiles.filter {
            $0.architecture == architecture && $0.supports(version) && $0.supportsBuild(osBuild)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    public func recoveryBuildPrefixes(architecture: String) -> Set<String> {
        guard adapterID == "usernoted-badge-v1" else { return [] }
        return Set(profiles.filter { $0.architecture == architecture }.map(\.osBuildPrefix))
    }
}

public struct QualifiedTarget: Decodable, Sendable {
    public let osBuild: String
    public let architecture: String
}

public struct CompatibilityProfile: Decodable, Sendable {
    public let id: String
    public let majorVersion: Int
    public let minimumMinorVersion: Int
    public let minimumPatchVersion: Int
    public let osBuildPrefix: String
    public let architecture: String

    func supports(_ version: OperatingSystemVersion) -> Bool {
        version.majorVersion == majorVersion &&
        (version.minorVersion > minimumMinorVersion ||
         (version.minorVersion == minimumMinorVersion && version.patchVersion >= minimumPatchVersion))
    }

    func supportsBuild(_ build: String) -> Bool {
        Self.build(build, hasPrefix: osBuildPrefix)
    }

    static func build(_ build: String, hasPrefix prefix: String) -> Bool {
        // Match the complete Darwin generation, never e.g. 25 against 250.
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isASCII && $0.isNumber }),
              build.hasPrefix(prefix) else { return false }
        let suffix = build.dropFirst(prefix.count)
        guard let letter = suffix.first, letter.isASCII && letter.isUppercase else { return false }
        let number = suffix.dropFirst()
        return !number.isEmpty && number.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
