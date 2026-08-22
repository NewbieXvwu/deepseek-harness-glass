import XCTest

@testable import GlassCore

final class NativeSettingsSectionLedgerTests: XCTestCase {
    func testOrdersByOfficialOrderStablyAndPrefersRequestedActive() {
        let registrations = [
            NativeSettingsSectionRow(id: "plugins", order: 15, label: "Plugins"),
            NativeSettingsSectionRow(id: "general", order: 0, label: "General"),
            NativeSettingsSectionRow(id: "same-first", order: 10, label: "First"),
            NativeSettingsSectionRow(id: "models", order: 10, label: "Models"),
        ]
        let ordered = NativeSettingsSectionLedger.ordered(registrations)
        XCTAssertEqual(ordered.map(\.id), ["general", "same-first", "models", "plugins"])
        XCTAssertEqual(NativeSettingsSectionLedger.activeID(requested: "models", rows: registrations), "models")
    }

    func testFallsBackToFirstWhenNoRequestedOrEntryUnregistersAndKeepsEmptyNil() {
        let rows = [
            NativeSettingsSectionRow(id: "models", order: 10, label: "Models"),
            NativeSettingsSectionRow(id: "general", order: 0, label: "General"),
        ]
        XCTAssertEqual(NativeSettingsSectionLedger.activeID(requested: nil, rows: rows), "general")
        XCTAssertEqual(NativeSettingsSectionLedger.activeID(requested: "plugins", rows: rows), "general")
        XCTAssertNil(NativeSettingsSectionLedger.activeID(requested: "general", rows: []))
        XCTAssertNil(NativeSettingsSectionLedger.closedSelection())
    }
}
