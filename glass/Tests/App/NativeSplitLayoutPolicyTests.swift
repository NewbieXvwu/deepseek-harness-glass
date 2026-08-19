import CoreGraphics
import XCTest

@testable import GlassSpec
@testable import GlassUI

final class NativeSplitLayoutPolicyTests: XCTestCase {
    func testOfficialThreePaneBaselineUsesLockedColumnLayout() {
        let columns = OfficialColumnLayout.resolve(
            viewport: 1280,
            sidebarPreference: OfficialUISpec.Layout.sidebarDefault,
            detailsPreference: OfficialUISpec.Layout.detailsDefault
        )
        XCTAssertEqual(columns.sidebar, 280)
        XCTAssertEqual(columns.center, 640)
        XCTAssertEqual(columns.details, 360)
    }

    func testSidebarDividerClampsAndCollapsedRailIsFixed() {
        XCTAssertEqual(
            NativeSplitLayoutPolicy.sidebarDividerPosition(proposed: 100, collapsed: false),
            OfficialUISpec.Layout.sidebarMinimum
        )
        XCTAssertEqual(
            NativeSplitLayoutPolicy.sidebarDividerPosition(proposed: 512, collapsed: false),
            OfficialUISpec.Layout.sidebarMaximum
        )
        XCTAssertEqual(
            NativeSplitLayoutPolicy.sidebarDividerPosition(proposed: 280, collapsed: true),
            OfficialUISpec.Layout.sidebarCollapsed
        )
    }

    func testDetailsDividerClampsToOfficialBoundsAndCollapsesWhenCenterCannotFit() {
        let sidebar = OfficialUISpec.Layout.sidebarDefault
        XCTAssertEqual(
            NativeSplitLayoutPolicy.detailsDividerPosition(
                proposed: 800,
                viewport: 1440,
                sidebarWidth: sidebar
            ),
            920,
            "at a viewport that leaves 520px after sidebar plus official center minimum, a wider drag clamps to the 520px maximum"
        )
        XCTAssertEqual(
            NativeSplitLayoutPolicy.detailsDividerPosition(
                proposed: 1050,
                viewport: 1280,
                sidebarWidth: sidebar
            ),
            980,
            "a drag requesting 230px details clamps to the official 300px minimum"
        )
        XCTAssertEqual(
            NativeSplitLayoutPolicy.detailsDividerPosition(
                proposed: 600,
                viewport: 1000,
                sidebarWidth: sidebar
            ),
            1000,
            "details must collapse rather than violate the official 640px center minimum"
        )
    }

    func testNarrowViewportUsesTheOfficialFiftySixPointRail() {
        XCTAssertLessThan(1023, OfficialUISpec.Layout.sidebarAutoCollapse)
        let layout = OfficialColumnLayout.resolve(
            viewport: 900,
            sidebarPreference: 0,
            detailsPreference: OfficialUISpec.Layout.detailsDefault
        )
        XCTAssertEqual(layout.sidebar, OfficialUISpec.Layout.sidebarCollapsed)
        XCTAssertEqual(layout.details, 0)
        XCTAssertEqual(layout.center, 844)
    }
}
