import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Declarative, non-executable description of a reviewed plugin surface.
///
/// Version 1 deliberately accepts only the currently locked Host build. Future
/// Host ranges require an explicit schema-version migration rather than a local
/// lexical version comparison that could accidentally admit an unreviewed Host.
struct NativeUIManifest: Codable, Equatable, Sendable {
    static let currentManifestVersion = 1

    enum Kind: String, Codable, CaseIterable, Sendable {
        case settingsForm
        case settingsPanel
    }

    enum FieldKind: String, Codable, CaseIterable, Sendable {
        case text
        case number
        case toggle
        case select
        case secret
        case path
        case readOnly
    }

    enum Action: String, Codable, CaseIterable, Sendable {
        case save
        case discard
        case reset
        case help
    }

    struct HostBuildRange: Codable, Equatable, Sendable {
        /// Both bounds are required in v1. They must be equal because the app
        /// currently supports one audited Host build only.
        let minimumBuildID: String
        let maximumBuildID: String

        func containsExactly(_ hostBuildID: String) -> Bool {
            minimumBuildID == maximumBuildID && minimumBuildID == hostBuildID
        }
    }

    struct LocaleResource: Codable, Equatable, Sendable {
        let language: String
        let namespace: String
        let requiredKeys: [String]
    }

    struct Section: Codable, Equatable, Sendable {
        let id: String
        let titleKey: String
        let fieldIDs: [String]
        let groupIDs: [String]
        let order: Int
    }

    struct Field: Codable, Equatable, Sendable {
        let id: String
        let path: [String]
        let kind: FieldKind
        let labelKey: String
        let helpKey: String?
        let options: [String]
        let validationIDs: [String]
        let requiredCapabilities: [String]
        let order: Int
    }

    struct Group: Codable, Equatable, Sendable {
        let id: String
        let titleKey: String?
        let fieldIDs: [String]
        let order: Int
    }

    struct Validation: Codable, Equatable, Sendable {
        enum Rule: String, Codable, CaseIterable, Sendable {
            case required
            case finiteNumber
            case nonNegativeNumber
            case nonEmptySelection
        }

        let id: String
        let rule: Rule
    }

    struct SecretRole: Codable, Equatable, Sendable {
        let id: String
        let credentialReference: String
        let labelKey: String
    }

    struct Integrity: Codable, Equatable, Sendable {
        let algorithm: String
        let digest: String
        let sourceCommit: String
    }

    let pluginID: String
    let hostBuildRange: HostBuildRange
    let manifestVersion: Int
    let kind: Kind
    let localeResources: [LocaleResource]
    let sections: [Section]
    let fields: [Field]
    let groups: [Group]
    let order: Int
    let secretRoles: [SecretRole]
    let validations: [Validation]
    let actions: [Action]
    let requiredCapabilities: [String]
    let integrity: Integrity
}

enum NativeUIManifestSchema {
    static let resourceName = "native-ui-manifest-v1"

    static func load() throws -> Data {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = .module
        #else
        bundle = .main
        #endif
        guard let url = bundle.url(forResource: resourceName, withExtension: "schema.json") else {
            throw NativeUIManifestValidationError.missingSchemaResource
        }
        return try Data(contentsOf: url)
    }
}

enum NativeUIManifestValidationError: Error, Equatable, Sendable {
    case missingSchemaResource
    case unsupportedManifestVersion(Int)
    case invalidPluginID
    case incompatibleHostBuildRange
    case unsupportedHostBuild(String)
    case integrityNotVerified
    case unsupportedIntegrityAlgorithm
    case malformedIntegrityDigest
    case sourceCommitMismatch
    case missingLocaleResources
    case invalidLocaleResource
    case duplicateSectionID(String)
    case duplicateFieldID(String)
    case duplicateGroupID(String)
    case duplicateValidationID(String)
    case duplicateSecretRoleID(String)
    case invalidOrder
    case invalidFieldPath(String)
    case unknownSectionField(String)
    case unknownSectionGroup(String)
    case unknownGroupField(String)
    case unknownValidation(String)
    case duplicateFieldReference(String)
    case unsafeSecretField(String)
    case invalidSecretRole(String)
    case noActions
}

enum NativeUIManifestRoute: Equatable, Sendable {
    /// A native renderer may consume this declarative, integrity-verified schema.
    case native(NativeUIManifest)
    /// Invalid or untrusted schema must never produce a partial native form. The
    /// later T11.4 router can hand the known plugin to the isolated Ghost Plane.
    case ghostPlaneFallback(pluginID: String, reason: NativeUIManifestValidationError)
}

/// Performs only structural validation. Cryptographic hashing belongs at the
/// Host/isolated-plane boundary; `verifiedIntegrity` is the verified output of
/// that boundary, not an untrusted value read from the manifest itself.
enum NativeUIManifestVerifier {
    static func route(
        _ manifest: NativeUIManifest,
        hostBuildID: String,
        verifiedIntegrity: NativeUIManifest.Integrity?
    ) -> NativeUIManifestRoute {
        do {
            try validate(manifest, hostBuildID: hostBuildID, verifiedIntegrity: verifiedIntegrity)
            return .native(manifest)
        } catch let error as NativeUIManifestValidationError {
            return .ghostPlaneFallback(pluginID: manifest.pluginID, reason: error)
        } catch {
            return .ghostPlaneFallback(pluginID: manifest.pluginID, reason: .integrityNotVerified)
        }
    }

    static func validate(
        _ manifest: NativeUIManifest,
        hostBuildID: String,
        verifiedIntegrity: NativeUIManifest.Integrity?
    ) throws {
        guard manifest.manifestVersion == NativeUIManifest.currentManifestVersion else {
            throw NativeUIManifestValidationError.unsupportedManifestVersion(manifest.manifestVersion)
        }
        guard validIdentifier(manifest.pluginID) else {
            throw NativeUIManifestValidationError.invalidPluginID
        }
        guard manifest.hostBuildRange.minimumBuildID == manifest.hostBuildRange.maximumBuildID else {
            throw NativeUIManifestValidationError.incompatibleHostBuildRange
        }
        guard manifest.hostBuildRange.containsExactly(hostBuildID), OfficialUISpec.Build.isCompatible(with: hostBuildID) else {
            throw NativeUIManifestValidationError.unsupportedHostBuild(hostBuildID)
        }
        guard manifest.integrity.algorithm == "sha256" else {
            throw NativeUIManifestValidationError.unsupportedIntegrityAlgorithm
        }
        guard validSHA256(manifest.integrity.digest) else {
            throw NativeUIManifestValidationError.malformedIntegrityDigest
        }
        guard manifest.integrity.sourceCommit == OfficialUISpec.Build.sourceCommit else {
            throw NativeUIManifestValidationError.sourceCommitMismatch
        }
        guard verifiedIntegrity == manifest.integrity else {
            throw NativeUIManifestValidationError.integrityNotVerified
        }
        guard !manifest.localeResources.isEmpty else {
            throw NativeUIManifestValidationError.missingLocaleResources
        }
        guard manifest.localeResources.allSatisfy(valid) else {
            throw NativeUIManifestValidationError.invalidLocaleResource
        }
        guard !manifest.actions.isEmpty else {
            throw NativeUIManifestValidationError.noActions
        }
        guard unique(manifest.sections.map(\.id)) else {
            throw NativeUIManifestValidationError.duplicateSectionID(firstDuplicate(in: manifest.sections.map(\.id)) ?? "")
        }
        guard unique(manifest.fields.map(\.id)) else {
            throw NativeUIManifestValidationError.duplicateFieldID(firstDuplicate(in: manifest.fields.map(\.id)) ?? "")
        }
        guard unique(manifest.groups.map(\.id)) else {
            throw NativeUIManifestValidationError.duplicateGroupID(firstDuplicate(in: manifest.groups.map(\.id)) ?? "")
        }
        guard unique(manifest.validations.map(\.id)) else {
            throw NativeUIManifestValidationError.duplicateValidationID(firstDuplicate(in: manifest.validations.map(\.id)) ?? "")
        }
        guard unique(manifest.secretRoles.map(\.id)) else {
            throw NativeUIManifestValidationError.duplicateSecretRoleID(firstDuplicate(in: manifest.secretRoles.map(\.id)) ?? "")
        }
        guard manifest.order >= 0,
              manifest.sections.allSatisfy({ $0.order >= 0 }),
              manifest.fields.allSatisfy({ $0.order >= 0 }),
              manifest.groups.allSatisfy({ $0.order >= 0 })
        else {
            throw NativeUIManifestValidationError.invalidOrder
        }

        let fieldIDs = Set(manifest.fields.map(\.id))
        let groupIDs = Set(manifest.groups.map(\.id))
        let validationIDs = Set(manifest.validations.map(\.id))
        for field in manifest.fields {
            guard validPath(field.path) else {
                throw NativeUIManifestValidationError.invalidFieldPath(field.id)
            }
            guard Set(field.validationIDs).isSubset(of: validationIDs) else {
                throw NativeUIManifestValidationError.unknownValidation(field.id)
            }
            if field.kind == .secret {
                throw NativeUIManifestValidationError.unsafeSecretField(field.id)
            }
        }
        for section in manifest.sections {
            guard Set(section.fieldIDs).isSubset(of: fieldIDs) else {
                throw NativeUIManifestValidationError.unknownSectionField(section.id)
            }
            guard Set(section.groupIDs).isSubset(of: groupIDs) else {
                throw NativeUIManifestValidationError.unknownSectionGroup(section.id)
            }
            guard unique(section.fieldIDs) else {
                throw NativeUIManifestValidationError.duplicateFieldReference(section.id)
            }
        }
        for group in manifest.groups {
            guard Set(group.fieldIDs).isSubset(of: fieldIDs) else {
                throw NativeUIManifestValidationError.unknownGroupField(group.id)
            }
            guard unique(group.fieldIDs) else {
                throw NativeUIManifestValidationError.duplicateFieldReference(group.id)
            }
        }
        for role in manifest.secretRoles {
            guard validIdentifier(role.id), validIdentifier(role.credentialReference), !role.labelKey.isEmpty else {
                throw NativeUIManifestValidationError.invalidSecretRole(role.id)
            }
        }
    }

    private static func valid(_ resource: NativeUIManifest.LocaleResource) -> Bool {
        (resource.language == "en" || resource.language == "zh")
            && !resource.namespace.isEmpty
            && !resource.requiredKeys.isEmpty
            && resource.requiredKeys.allSatisfy { !$0.isEmpty }
    }

    private static func validIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 160 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 46, 47, 58, 95, 48...57, 65...90, 97...122: true // - . / : _ ASCII alphanumerics
            default: false
            }
        }
    }

    private static func validPath(_ path: [String]) -> Bool {
        !path.isEmpty && path.allSatisfy { segment in
            !segment.isEmpty && !segment.contains(".") && validIdentifier(segment)
        }
    }

    private static func validSHA256(_ digest: String) -> Bool {
        let normalized = digest.hasPrefix("sha256:") ? String(digest.dropFirst(7)) : digest
        guard normalized.count == 64 else { return false }
        return normalized.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...70, 97...102: true
            default: false
            }
        }
    }

    private static func unique(_ values: [String]) -> Bool {
        Set(values).count == values.count
    }

    private static func firstDuplicate(in values: [String]) -> String? {
        var seen = Set<String>()
        for value in values where !seen.insert(value).inserted { return value }
        return nil
    }
}
