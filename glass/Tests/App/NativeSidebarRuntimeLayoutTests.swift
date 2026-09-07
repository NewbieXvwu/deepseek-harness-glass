import AppKit
import XCTest

@testable import GlassSpec
@testable import GlassUI

@MainActor
final class NativeSidebarRuntimeLayoutTests: XCTestCase {
    func testNarrowSystemSidebarHonorsOfficialCollapsedRailThickness() {
        let presentation = NativeShellPresentation(mode: .welcome)
        let root = NativeShellRootController(presentation: presentation)
        root.loadView()
        root.view.frame = NSRect(x: 0, y: 0, width: 780, height: 900)
        root.view.layoutSubtreeIfNeeded()
        root.refreshForCurrentViewport()
        root.view.layoutSubtreeIfNeeded()

        guard let split = root.children.compactMap({ $0 as? NativeShellController }).first else {
            return XCTFail("Native shell root must contain its AppKit split controller")
        }
        split.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(presentation.sidebarLayout.isCollapsed)
        XCTAssertEqual(split.splitView.bounds.width, 780, accuracy: 0.5)
        XCTAssertEqual(
            split.splitViewItems[0].minimumThickness,
            OfficialUISpec.Layout.sidebarCollapsed,
            accuracy: 0.5
        )
        XCTAssertEqual(
            split.splitView.subviews[0].frame.width,
            OfficialUISpec.Layout.sidebarCollapsed,
            accuracy: 0.5
        )
    }
}
