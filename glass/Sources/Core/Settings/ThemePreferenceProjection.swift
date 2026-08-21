import Foundation

/// The exact persisted theme preference contract in locked official
/// `packages/client/ui-theme/src/theme-settings.ts`.
enum CoreThemePreference: String, CaseIterable, Sendable, Equatable {
    case light
    case dark
    case system
}

struct CoreThemePreferenceState: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case unavailable
        case malformed
        case ready
    }

    let status: Status
    let writable: Bool
    let current: CoreThemePreference?
    let revision: Int?

    func mutation(selecting preference: CoreThemePreference) -> SettingsPathOperationDTO? {
        guard status == .ready, writable else { return nil }
        return .set(path: ThemePreferenceProjection.path, value: .string(preference.rawValue))
    }
}

/// Host-authoritative view of the official `ui-theme.preference` setting. The
/// native shell never resolves a different active palette here: the persisted
/// preference itself is the product source of truth, matching AppearanceRow.
enum ThemePreferenceProjection {
    static let namespace = "ui-theme"
    static let path = ["preference"]

    static func state(namespaces: [SettingsNamespaceDTO], writable: Bool) -> CoreThemePreferenceState {
        guard let namespace = namespaces.first(where: { $0.ns == Self.namespace }) else {
            return .init(status: .unavailable, writable: false, current: nil, revision: nil)
        }
        guard let rawValue = namespace.value.objectValue?[path[0]]?.stringValue,
              let preference = CoreThemePreference(rawValue: rawValue)
        else {
            return .init(status: .malformed, writable: false, current: nil, revision: namespace.revision)
        }
        return .init(status: .ready, writable: writable, current: preference, revision: namespace.revision)
    }
}
