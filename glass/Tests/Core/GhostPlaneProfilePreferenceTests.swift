import XCTest
@testable import GlassCore

final class GhostPlaneProfilePreferenceTests: XCTestCase {
    func testSharedIsDefaultAndRoundTrips() {
        XCTAssertEqual(GhostPlaneProfilePreference.decode(nil).selection, .sharedWeb)
        XCTAssertEqual(GhostPlaneProfilePreference.decode("shared").storedValue, "shared")
    }

    func testIsolatedNameRoundTripsButUnknownWireFailsClosed() {
        let preference = GhostPlaneProfilePreference(selection: .isolated(name: "review"))
        XCTAssertEqual(preference.storedValue, "isolated:review")
        XCTAssertEqual(GhostPlaneProfilePreference.decode(preference.storedValue).selection, .isolated(name: "review"))
        XCTAssertEqual(GhostPlaneProfilePreference.decode("file:///tmp").selection, .sharedWeb)
    }
}
