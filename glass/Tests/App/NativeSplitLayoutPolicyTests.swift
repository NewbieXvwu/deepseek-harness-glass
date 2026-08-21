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

    func testOfficialConcessionChainMatchesStepOneAndStepTwoSeams() {
        let sidebar = 300
        let details = OfficialUISpec.Layout.detailsDefault
        let center = OfficialUISpec.Layout.centerMinimum

        XCTAssertEqual(
            OfficialColumnLayout.resolve(
                viewport: sidebar + details + center,
                sidebarPreference: sidebar,
                detailsPreference: details
            ),
            OfficialColumnLayout(sidebar: sidebar, center: center, details: details)
        )
        XCTAssertEqual(
            OfficialColumnLayout.resolve(
                viewport: sidebar + details + center - 1,
                sidebarPreference: sidebar,
                detailsPreference: details
            ),
            OfficialColumnLayout(sidebar: sidebar, center: center, details: details - 1)
        )
    }

    func testClosedSidebarUsesRailBeforeDetailsConcession() {
        let rail = OfficialUISpec.Layout.sidebarCollapsed
        let detailsMinimum = OfficialUISpec.Layout.detailsMinimum
        let centerMinimum = OfficialUISpec.Layout.centerMinimum

        XCTAssertEqual(
            OfficialColumnLayout.resolve(
                viewport: rail + detailsMinimum + centerMinimum,
                sidebarPreference: 0,
                detailsPreference: OfficialUISpec.Layout.detailsDefault
            ),
            OfficialColumnLayout(sidebar: rail, center: centerMinimum, details: detailsMinimum)
        )
        XCTAssertEqual(
            OfficialColumnLayout.resolve(
                viewport: rail + detailsMinimum + centerMinimum - 1,
                sidebarPreference: 0,
                detailsPreference: OfficialUISpec.Layout.detailsDefault
            ).details,
            0
        )
    }

    func testConcessionTemporarilyCollapsesDetailsWithoutForgettingPreference() {
        let sidebar = OfficialUISpec.Layout.sidebarDefault
        let preference = OfficialUISpec.Layout.detailsMaximum
        let constrained = OfficialColumnLayout.resolve(
            viewport: 1000,
            sidebarPreference: sidebar,
            detailsPreference: preference
        )
        XCTAssertEqual(constrained.details, 0)
        XCTAssertEqual(constrained.center, 720)

        let rewidened = OfficialColumnLayout.resolve(
            viewport: 1440,
            sidebarPreference: sidebar,
            detailsPreference: preference
        )
        XCTAssertEqual(rewidened.details, preference)
        XCTAssertEqual(rewidened.center, OfficialUISpec.Layout.centerMinimum)
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

    @MainActor
    func testDeliverablesSnapshotRetainsRecordedNarrowSidebarExpansionOnly() {
        let fixture = NativeShellPresentation(
            mode: .conversation,
            snapshotSidebarNarrowExpanded: true
        )
        fixture.setSidebarViewportNarrow(true)
        XCTAssertFalse(fixture.sidebarLayout.isCollapsed)
        XCTAssertTrue(fixture.sidebarLayout.narrowExpanded)

        let production = NativeShellPresentation(mode: .conversation)
        production.setSidebarViewportNarrow(true)
        XCTAssertTrue(production.sidebarLayout.isCollapsed)
        XCTAssertFalse(production.sidebarLayout.narrowExpanded)
    }

    func testRepeatedNarrowViewportRefreshPreservesManualExpansion() {
        var state = NativeSidebarLayoutState()
        state.setNarrow(true)
        state.setCollapsed(false)
        XCTAssertFalse(state.isCollapsed)
        XCTAssertTrue(state.narrowExpanded)

        state.setNarrow(true)
        XCTAssertFalse(state.isCollapsed, "a viewport refresh within the same narrow regime must preserve the user's open rail")
        XCTAssertTrue(state.narrowExpanded)
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
