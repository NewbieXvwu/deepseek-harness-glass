import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// The UI-only staged state of one already verified NativeUIManifest.
///
/// It owns no durable settings and cannot interpret executable plugin content.
/// A caller must send `mutationPlan` through the revision-fenced Settings API and
/// must obtain every secret value through the separate credentials boundary.
struct NativeSchemaFormDraft: Equatable {
    struct FieldState: Equatable {
        let text: String
        let boolean: Bool
        let overridden: Bool
        let invalid: Bool
        let writable: Bool
    }

    private enum Edit: Equatable {
        case text(String)
        case boolean(Bool)
        case reset
    }

    let namespace: SettingsNamespaceDTO
    let manifest: NativeUIManifest
    private let fields: [String: NativeUIManifest.Field]
    private var staged: [String: Edit] = [:]

    init(namespace: SettingsNamespaceDTO, manifest: NativeUIManifest) {
        self.namespace = namespace
        self.manifest = manifest
        fields = Dictionary(uniqueKeysWithValues: manifest.fields.map { ($0.id, $0) })
    }

    var isDirty: Bool { !staged.isEmpty }

    var hasInvalidDraft: Bool {
        staged.contains { id, edit in
            guard let field = fields[id] else { return true }
            return parse(edit, as: field) == nil
        }
    }

    /// Operations preserve manifest order so the visible form and Host mutation
    /// order remain auditable. An invalid draft returns nil and is never dropped.
    var mutationPlan: [SettingsPathOperationDTO]? {
        guard !hasInvalidDraft else { return nil }
        var plan: [SettingsPathOperationDTO] = []
        for field in manifest.fields.sorted(by: { $0.order < $1.order }) {
            guard let edit = staged[field.id], let parsed = parse(edit, as: field) else { continue }
            switch parsed {
            case .unchanged:
                continue
            case .clear:
                if isOverridden(field) { plan.append(.unset(path: field.path)) }
            case let .set(value):
                if value != effectiveValue(field) { plan.append(.set(path: field.path, value: value)) }
            }
        }
        return plan
    }

    func state(for field: NativeUIManifest.Field, writable: Bool) -> FieldState? {
        guard let declared = fields[field.id] else { return nil }
        let editable = writable && declared.kind != .readOnly && declared.kind != .secret
        let stored = effectiveValue(declared)
        guard let edit = staged[declared.id] else {
            return FieldState(
                text: format(stored, as: declared),
                boolean: stored?.boolValue ?? false,
                overridden: isOverridden(declared),
                invalid: false,
                writable: editable
            )
        }
        guard let parsed = parse(edit, as: declared) else {
            return FieldState(text: text(of: edit), boolean: false, overridden: false, invalid: true, writable: editable)
        }
        switch parsed {
        case .unchanged:
            return FieldState(
                text: format(stored, as: declared),
                boolean: stored?.boolValue ?? false,
                overridden: isOverridden(declared),
                invalid: false,
                writable: editable
            )
        case .clear:
            return FieldState(
                text: format(baseValue(declared), as: declared),
                boolean: baseValue(declared)?.boolValue ?? false,
                overridden: false,
                invalid: false,
                writable: editable
            )
        case let .set(value):
            return FieldState(
                text: format(value, as: declared),
                boolean: value.boolValue ?? false,
                overridden: true,
                invalid: false,
                writable: editable
            )
        }
    }

    mutating func stageText(_ value: String, for field: NativeUIManifest.Field) {
        guard fields[field.id]?.kind != .readOnly, fields[field.id]?.kind != .secret else { return }
        staged[field.id] = .text(value)
    }

    mutating func stageBoolean(_ value: Bool, for field: NativeUIManifest.Field) {
        guard fields[field.id]?.kind == .toggle else { return }
        staged[field.id] = .boolean(value)
    }

    mutating func reset(_ field: NativeUIManifest.Field) {
        guard fields[field.id]?.kind != .readOnly, fields[field.id]?.kind != .secret else { return }
        staged[field.id] = .reset
    }

    mutating func discard() { staged = [:] }

    private enum Parsed: Equatable {
        case unchanged
        case clear
        case set(JSONValue)
    }

    private func parse(_ edit: Edit, as field: NativeUIManifest.Field) -> Parsed? {
        switch edit {
        case .reset:
            return .clear
        case let .boolean(value):
            return field.kind == .toggle ? .set(.bool(value)) : nil
        case let .text(raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            switch field.kind {
            case .text, .path:
                return trimmed.isEmpty ? .clear : .set(.string(trimmed))
            case .number:
                guard !trimmed.isEmpty else { return .clear }
                guard let number = Double(trimmed), number.isFinite else { return nil }
                return .set(.number(number))
            case .select:
                guard !trimmed.isEmpty else { return .clear }
                guard field.options.contains(trimmed) else { return nil }
                return .set(.string(trimmed))
            case .readOnly:
                return .unchanged
            case .toggle, .secret:
                return nil
            }
        }
    }

    private func text(of edit: Edit) -> String {
        switch edit {
        case let .text(value): value
        case .boolean: ""
        case .reset: ""
        }
    }

    private func format(_ value: JSONValue?, as field: NativeUIManifest.Field) -> String {
        switch field.kind {
        case .text, .path, .select, .readOnly:
            return value?.stringValue ?? ""
        case .number:
            guard let number = value?.numberValue else { return "" }
            return number.rounded(.towardZero) == number ? String(Int(number)) : String(number)
        case .toggle:
            return value?.boolValue == true ? "true" : "false"
        case .secret:
            return ""
        }
    }

    private func effectiveValue(_ field: NativeUIManifest.Field) -> JSONValue? {
        namespace.value.value(at: field.path)
    }

    private func baseValue(_ field: NativeUIManifest.Field) -> JSONValue? {
        namespace.base?.value(at: field.path)
    }

    private func isOverridden(_ field: NativeUIManifest.Field) -> Bool {
        namespace.user?.containsValue(at: field.path) == true
    }
}
