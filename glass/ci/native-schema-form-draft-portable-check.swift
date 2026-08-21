import Foundation

enum OfficialUISpec {
    enum Build {
        static let id = "dsh-0.1.1-rc.1-official-528c682e"
        static let sourceCommit = "528c682e061696f5a160f363f236ecbf53cbd006"
        static func isCompatible(with hostBuildID: String) -> Bool { hostBuildID == id }
    }
}

enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case object([String: JSONValue])

    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }
    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }
    var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }
    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }
}

struct SettingsSecretDTO: Equatable { let path: [String] }
struct SettingsNamespaceDTO: Equatable {
    let ns: String
    let revision: Int?
    let value: JSONValue
    let base: JSONValue?
    let user: JSONValue?
    let secrets: [SettingsSecretDTO]
}

enum SettingsPathOperationDTO: Equatable {
    case set(path: [String], value: JSONValue)
    case unset(path: [String])
}

@main
struct NativeSchemaFormDraftPortableCheck {
    static func main() throws {
        let manifest = NativeUIManifest(
            pluginID: "example.plugin",
            hostBuildRange: .init(minimumBuildID: OfficialUISpec.Build.id, maximumBuildID: OfficialUISpec.Build.id),
            manifestVersion: 1,
            kind: .settingsForm,
            localeResources: [.init(language: "en", namespace: "example", requiredKeys: ["title"])],
            sections: [.init(id: "root", titleKey: "title", fieldIDs: ["enabled", "timeout", "mode", "path"], groupIDs: [], order: 0)],
            fields: [
                .init(id: "enabled", path: ["enabled"], kind: .toggle, labelKey: "enabled", helpKey: nil, options: [], validationIDs: [], requiredCapabilities: [], order: 0),
                .init(id: "timeout", path: ["timeoutMs"], kind: .number, labelKey: "timeout", helpKey: nil, options: [], validationIDs: [], requiredCapabilities: [], order: 1),
                .init(id: "mode", path: ["mode"], kind: .select, labelKey: "mode", helpKey: nil, options: ["fast", "safe"], validationIDs: [], requiredCapabilities: [], order: 2),
                .init(id: "path", path: ["cachePath"], kind: .path, labelKey: "path", helpKey: nil, options: [], validationIDs: [], requiredCapabilities: [], order: 3),
            ],
            groups: [], order: 0, secretRoles: [], validations: [], actions: [.save, .discard, .reset], requiredCapabilities: [],
            integrity: .init(algorithm: "sha256", digest: "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", sourceCommit: OfficialUISpec.Build.sourceCommit)
        )
        let namespace = SettingsNamespaceDTO(
            ns: "example", revision: 4,
            value: .object(["enabled": .bool(false), "timeoutMs": .number(10), "mode": .string("fast"), "cachePath": .string("/tmp/cache")]),
            base: .object(["enabled": .bool(false), "timeoutMs": .number(5), "mode": .string("safe"), "cachePath": .string("/tmp/cache")]),
            user: .object(["timeoutMs": .number(10), "mode": .string("fast")]),
            secrets: []
        )
        var draft = NativeSchemaFormDraft(namespace: namespace, manifest: manifest)
        let fields = Dictionary(uniqueKeysWithValues: manifest.fields.map { ($0.id, $0) })
        guard let enabled = fields["enabled"], let timeout = fields["timeout"], let mode = fields["mode"], let path = fields["path"] else {
            throw CheckFailure("fixture fields are missing")
        }
        draft.stageBoolean(true, for: enabled)
        draft.stageText("25", for: timeout)
        draft.stageText("safe", for: mode)
        draft.reset(path)
        guard draft.mutationPlan == [
            .set(path: ["enabled"], value: .bool(true)),
            .set(path: ["timeoutMs"], value: .number(25)),
            .set(path: ["mode"], value: .string("safe")),
        ] else {
            throw CheckFailure("ordered typed mutation plan mismatch")
        }
        draft.stageText("not-an-option", for: mode)
        guard draft.hasInvalidDraft, draft.mutationPlan == nil else {
            throw CheckFailure("unknown select value must block save")
        }
        draft.discard()
        guard !draft.isDirty, draft.state(for: timeout, writable: true)?.overridden == true else {
            throw CheckFailure("discard must restore Host-derived override state")
        }
        print("native schema form draft portable check passed")
    }

    struct CheckFailure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
