import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
enum NativeSettingsSectionLedgerPortableCheck {
    static func main() throws {
        let registrations = [
            NativeSettingsSectionRow(id: "plugins", order: 15, label: "Plugins"),
            NativeSettingsSectionRow(id: "general", order: 0, label: "General"),
            NativeSettingsSectionRow(id: "equal-first", order: 10, label: "First"),
            NativeSettingsSectionRow(id: "models", order: 10, label: "Models"),
        ]
        let rows = NativeSettingsSectionLedger.ordered(registrations)
        guard rows.map(\.id) == ["general", "equal-first", "models", "plugins"] else {
            throw CheckFailure(description: "settings section ledger must order by official order and retain equal-order registration sequence")
        }
        guard NativeSettingsSectionLedger.activeID(requested: "models", rows: registrations) == "models",
              NativeSettingsSectionLedger.activeID(requested: nil, rows: registrations) == "general",
              NativeSettingsSectionLedger.activeID(requested: "unregistered", rows: registrations) == "general" else {
            throw CheckFailure(description: "settings selection must prefer a registered active id and otherwise use the first ordered row")
        }
        guard NativeSettingsSectionLedger.activeID(requested: "general", rows: []) == nil,
              NativeSettingsSectionLedger.closedSelection() == nil else {
            throw CheckFailure(description: "empty ledger and close must leave no invented active settings page")
        }
        print("native settings section ledger portable check passed")
    }
}
