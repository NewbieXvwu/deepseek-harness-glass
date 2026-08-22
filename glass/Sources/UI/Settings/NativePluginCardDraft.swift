#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// The field grammar a reviewed native plugin card is allowed to stage. Secret
/// roles deliberately have no case here: credentials use their write-only API.
enum NativePluginCardFieldKind: Equatable {
    case text
    case number
}

struct NativePluginCardField: Equatable {
    let path: [String]
    let kind: NativePluginCardFieldKind

    init(_ name: String, kind: NativePluginCardFieldKind) {
        path = [name]
        self.kind = kind
    }
}

struct NativePluginCardFieldState: Equatable {
    let text: String
    let overridden: Bool
    let invalid: Bool
}

/// A per-card, locally staged projection over one complete Host namespace.
/// It never owns durable settings: `operations()` returns a typed plan that the
/// existing revision-fenced Settings facade must accept before authority moves.
struct NativePluginCardDraft: Equatable {
    private enum Edit: Equatable {
        case text(String)
        case reset
    }

    private enum Parsed {
        case set(JSONValue)
        case clear
        case invalid
    }

    let namespace: SettingsNamespaceDTO
    private let fields: [String: NativePluginCardField]
    private var staged: [String: Edit] = [:]

    init(namespace: SettingsNamespaceDTO, fields: [NativePluginCardField]) {
        self.namespace = namespace
        let secretPaths = Set(namespace.secrets.map(\.path))
        self.fields = Dictionary(
            uniqueKeysWithValues: fields
                .filter { !secretPaths.contains($0.path) }
                .map { ($0.path.joined(separator: "."), $0) }
        )
    }

    var isDirty: Bool { !staged.isEmpty }
    var hasInvalidDraft: Bool {
        staged.contains { key, edit in
            guard case let .text(text) = edit else { return false }
            guard let field = fields[key] else { return true }
            if case .invalid = parse(text, as: field.kind) { return true }
            return false
        }
    }

    /// The complete ordered typed mutation plan. A nil result means a draft is
    /// invalid and therefore must not be saved; an empty result is a clean card.
    var mutationPlan: [SettingsPathOperationDTO]? {
        guard !hasInvalidDraft else { return nil }
        var operations: [SettingsPathOperationDTO] = []
        for (key, edit) in staged.sorted(by: { $0.key < $1.key }) {
            guard let field = fields[key] else { continue }
            switch edit {
            case .reset:
                if isOverridden(field) { operations.append(.unset(path: field.path)) }
            case let .text(text):
                switch parse(text, as: field.kind) {
                case let .set(value):
                    if value != effectiveValue(field) { operations.append(.set(path: field.path, value: value)) }
                case .clear:
                    if isOverridden(field) { operations.append(.unset(path: field.path)) }
                case .invalid:
                    return nil
                }
            }
        }
        return operations
    }

    func state(for field: NativePluginCardField) -> NativePluginCardFieldState? {
        guard let declared = fields[key(for: field)] else { return nil }
        if let staged = staged[key(for: declared)] {
            switch staged {
            case .reset:
                return .init(text: format(baseValue(declared), as: declared.kind), overridden: false, invalid: false)
            case let .text(text):
                let parsed = parse(text, as: declared.kind)
                let invalid: Bool
                let overridden: Bool
                switch parsed {
                case .set:
                    invalid = false
                    overridden = true
                case .clear:
                    invalid = false
                    overridden = false
                case .invalid:
                    invalid = true
                    overridden = false
                }
                return .init(text: text, overridden: overridden, invalid: invalid)
            }
        }
        return .init(
            text: format(effectiveValue(declared), as: declared.kind),
            overridden: isOverridden(declared),
            invalid: false
        )
    }

    mutating func stage(_ text: String, for field: NativePluginCardField) {
        guard fields[key(for: field)] != nil else { return }
        staged[key(for: field)] = .text(text)
    }

    mutating func reset(_ field: NativePluginCardField) {
        guard fields[key(for: field)] != nil else { return }
        staged[key(for: field)] = .reset
    }

    mutating func discard() { staged = [:] }

    private func key(for field: NativePluginCardField) -> String { field.path.joined(separator: ".") }
    private func effectiveValue(_ field: NativePluginCardField) -> JSONValue? { namespace.value.value(at: field.path) }
    private func baseValue(_ field: NativePluginCardField) -> JSONValue? { namespace.base?.value(at: field.path) }
    private func isOverridden(_ field: NativePluginCardField) -> Bool { namespace.user?.containsValue(at: field.path) == true }

    private func format(_ value: JSONValue?, as kind: NativePluginCardFieldKind) -> String {
        switch kind {
        case .text: return value?.stringValue ?? ""
        case .number:
            guard let number = value?.numberValue else { return "" }
            return number.rounded(.towardZero) == number ? String(Int(number)) : String(number)
        }
    }

    private func parse(_ text: String, as kind: NativePluginCardFieldKind) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .clear }
        switch kind {
        case .text: return .set(.string(trimmed))
        case .number:
            guard let number = Double(trimmed), number.isFinite else { return .invalid }
            return .set(.number(number))
        }
    }
}

extension JSONValue {
    func value(at path: [String]) -> JSONValue? {
        var current = self
        for segment in path {
            guard let next = current.objectValue?[segment] else { return nil }
            current = next
        }
        return current
    }

    func containsValue(at path: [String]) -> Bool { value(at: path) != nil }
}
