import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Host-authoritative projection of the official `permission.defaultPreset`
/// settings descriptor. Source: `ui-permission-presets/settings-store.ts`.
struct CorePermissionPresetState: Equatable {
    enum Status: Equatable {
        case unavailable
        case ready
        case malformed
    }

    struct Option: Equatable, Identifiable {
        let id: String
        let label: String
        let requiresConfirmation: Bool
    }

    let status: Status
    let writable: Bool
    let currentValue: String
    let options: [Option]
    let revision: Int?

    /// Returns a CAS-protected mutation only for an option explicitly advertised
    /// by the current Host schema. Unknown values never reach transport.
    func mutation(selecting preset: String) -> SettingsPathOperationDTO? {
        guard status == .ready, writable, options.contains(where: { $0.id == preset }) else { return nil }
        return .set(path: ["defaultPreset"], value: .string(preset))
    }
}

/// Strict schema projection for the official permission namespace. The parser
/// intentionally understands only the locked rehydrated schema vocabulary used
/// by `permissionDefaultOf`: root uid, refs, object/dict, union/list and const.
enum PermissionPresetProjection {
    static let namespace = "permission"
    static let fullAccessPreset = "danger-full-access"

    static func state(
        namespaces: [SettingsNamespaceDTO],
        writable: Bool
    ) -> CorePermissionPresetState {
        guard let namespace = namespaces.first(where: { $0.ns == self.namespace }) else {
            return .init(status: .unavailable, writable: false, currentValue: "", options: [], revision: nil)
        }
        guard let current = namespace.value.permissionString(at: ["defaultPreset"]),
              let options = options(from: namespace.schema),
              !options.isEmpty,
              options.contains(where: { $0.id == current })
        else {
            return .init(status: .malformed, writable: false, currentValue: "", options: [], revision: nil)
        }
        return .init(
            status: .ready,
            writable: writable,
            currentValue: current,
            options: options,
            revision: namespace.revision
        )
    }

    private static func options(from schema: JSONValue) -> [CorePermissionPresetState.Option]? {
        guard let root = schema.permissionReferencedSchema(),
              root.permissionType == "object",
              let defaultPresetRef = root.permissionObject(named: "dict")?["defaultPreset"]?.permissionReference,
              let defaultPresetNode = schema.permissionReferenceNode(defaultPresetRef)
        else { return nil }

        let choices: [JSONValue]
        if defaultPresetNode.permissionType == "union" {
            choices = (defaultPresetNode.permissionArray(named: "list") ?? []).compactMap { value in
                guard let reference = value.permissionReference else { return nil }
                return schema.permissionReferenceNode(reference)
            }
        } else {
            choices = [defaultPresetNode]
        }

        let options = choices.compactMap { choice -> CorePermissionPresetState.Option? in
            guard choice.permissionType == "const",
                  let value = choice.permissionValue(named: "value")?.stringValue
            else { return nil }
            let description = choice.permissionObject(named: "meta")?["description"]?.stringValue
            let suppliedLabel = (description?.isEmpty == false) ? description! : value
            return .init(
                id: value,
                label: display(value: value, suppliedLabel: suppliedLabel),
                requiresConfirmation: value == fullAccessPreset
            )
        }
        return options
    }

    static func display(value: String, suppliedLabel: String) -> String {
        if value == fullAccessPreset { return "Full access" }
guard isASCIILowerKebabCase(suppliedLabel) else { return suppliedLabel }
        return suppliedLabel.split(separator: "-").map {
            $0.prefix(1).uppercased() + $0.dropFirst()
        }.joined(separator: " ")
    }

/// Avoids compiling a regular expression on every settings projection. The
    /// Host schema permits only ASCII lowercase/digit segments separated by one
    /// hyphen; any other label is preserved verbatim rather than normalized.
    private static func isASCIILowerKebabCase(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        var needsSegmentCharacter = true
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 48 ... 57, 97 ... 122: // 0...9, a...z
                needsSegmentCharacter = false
            case 45 where !needsSegmentCharacter: // '-'
                needsSegmentCharacter = true
            default:
                return false
            }
        }
        return !needsSegmentCharacter
    }
}

private extension JSONValue {
    func permissionValue(named key: String) -> JSONValue? { objectValue?[key] }
    func permissionObject(named key: String) -> [String: JSONValue]? { permissionValue(named: key)?.objectValue }
    func permissionArray(named key: String) -> [JSONValue]? { permissionValue(named: key)?.arrayValue }
    var permissionType: String? { permissionValue(named: "type")?.stringValue }
    var permissionReference: Int? {
        guard let number = numberValue, number.rounded(.towardZero) == number,
              number >= 0, number <= Double(Int.max)
        else { return nil }
        return Int(number)
    }

    func permissionString(at path: [String]) -> String? {
        var node: JSONValue = self
        for key in path {
            guard let child = node.objectValue?[key] else { return nil }
            node = child
        }
        return node.stringValue
    }

    func permissionReferencedSchema() -> JSONValue? {
        guard let rootRef = permissionValue(named: "uid")?.permissionReference else { return nil }
        return permissionReferenceNode(rootRef)
    }

    func permissionReferenceNode(_ reference: Int) -> JSONValue? {
        permissionObject(named: "refs")?[String(reference)]
    }
}
