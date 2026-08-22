import Foundation

/// Native equivalent of the ordered `settings.section` nav-row projection. It
/// deliberately has no SwiftUI/slot runtime dependency: the shell supplies only
/// reviewed builtin registrations, while this model owns the authoritative
/// order and active-selection fallback behavior.
public struct NativeSettingsSectionRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let order: Int
    public let label: String

    public init(id: String, order: Int, label: String) {
        self.id = id
        self.order = order
        self.label = label
    }
}

public enum NativeSettingsSectionLedger {
    /// JS stable `Array.prototype.sort(order)` equivalent: equal-order entries
    /// retain their registration order rather than being reordered by identifier.
    public static func ordered(_ registrations: [NativeSettingsSectionRow]) -> [NativeSettingsSectionRow] {
        registrations.enumerated()
            .sorted { lhs, rhs in
                lhs.element.order == rhs.element.order ? lhs.offset < rhs.offset : lhs.element.order < rhs.element.order
            }
            .map(\.element)
    }

    /// Mirrors SettingsPanel's `activeId ?? rows[0]?.id` and its response when
    /// a selected ledger entry unregisters. An empty ledger deliberately yields
    /// nil so callers render an empty content column instead of inventing a page.
    public static func activeID(requested: String?, rows: [NativeSettingsSectionRow]) -> String? {
        let rows = ordered(rows)
        guard let requested, rows.contains(where: { $0.id == requested }) else {
            return rows.first?.id
        }
        return requested
    }

    /// Root close clears active state; a later manual open derives first active.
    public static func closedSelection() -> String? { nil }
}
