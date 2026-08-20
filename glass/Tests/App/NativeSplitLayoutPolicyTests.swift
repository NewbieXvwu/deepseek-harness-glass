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

    func testNarrowSidebarManualExpandDoesNotRewriteWidePreference() {
        var state = NativeSidebarLayoutState()
        XCTAssertFalse(state.isCollapsed)

        state.setNarrow(true)
        XCTAssertTrue(state.isCollapsed, "RC8 narrows to a 56px rail by default")
        XCTAssertFalse(state.narrowExpanded)

        state.setCollapsed(false)
        XCTAssertFalse(state.isCollapsed, "open in a narrow viewport must use the transient override")
        XCTAssertTrue(state.narrowExpanded)

        state.setNarrow(false)
        XCTAssertFalse(state.isCollapsed, "re-widening restores the untouched wide preference")
        XCTAssertFalse(state.narrowExpanded, "the narrow-only override must reset at the breakpoint")
    }

    func testWideCollapsedPreferenceSurvivesNarrowManualExpansion() {
        var state = NativeSidebarLayoutState()
        state.setCollapsed(true)
        XCTAssertTrue(state.isCollapsed)

        state.setNarrow(true)
        state.setCollapsed(false)
        XCTAssertFalse(state.isCollapsed, "narrow expansion must not mutate the wide collapsed preference")

        state.setNarrow(false)
        XCTAssertTrue(state.isCollapsed, "the prior wide collapsed preference returns after re-widening")
    }
}
