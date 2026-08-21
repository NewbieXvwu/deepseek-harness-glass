import XCTest
@testable import GlassCore

final class GhostPlaneProfilePreferenceStoreTests: XCTestCase {
    func testStorePersistsOnlyCodecValueAndResetsToShared() {
        let suite = "GhostPlaneProfilePreferenceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GhostPlaneProfilePreferenceStore(defaults: defaults, key: "profile")
        XCTAssertEqual(store.preference.selection, .sharedWeb)
        store.set(.init(selection: .isolated(name: "review")))
        XCTAssertEqual(store.preference.selection, .isolated(name: "review"))
        XCTAssertEqual(defaults.string(forKey: "profile"), "isolated:review")
        store.reset()
        XCTAssertEqual(store.preference.selection, .sharedWeb)
    }
}
