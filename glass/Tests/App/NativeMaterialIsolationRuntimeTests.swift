import AppKit
import SwiftUI
import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

@MainActor
final class NativeMaterialIsolationRuntimeTests: XCTestCase {
    func testConversationContentOwnsNoStructuralVisualEffectViewAtRuntime() {
        assertNoVisualEffects(
            in: NativeConversationColumn(
                mode: .conversation,
                selectedWorkspaceTitle: "Fixture workspace",
                sessionSnapshot: .empty,
                sessionStore: NativeSessionStore(),
                jobsPopoverInitiallyOpen: false,
                jobsLanguageCode: nil,
                openSession: { _ in },
                viewRegistry: NativeConversationViewRegistry(),
                headerContributions: NativeConversationHeaderContributionRegistry()
            ),
            surface: "conversation-content"
        )
    }

    func testNativeShellUsesSystemSidebarAndInspectorItemsWhileContentStaysMaterialFree() {
        let presentation = NativeShellPresentation(mode: .welcome)
        let root = NativeShellRootController(presentation: presentation)
        root.loadView()

        guard let split = root.children.compactMap({ $0 as? NativeShellController }).first else {
            return XCTFail("Native shell root must contain its AppKit split controller")
        }
        XCTAssertEqual(split.splitViewItems.count, 3)
        XCTAssertEqual(split.splitViewItems[0].behavior, .sidebar)
        XCTAssertEqual(split.splitViewItems[2].behavior, .inspector)
        XCTAssertTrue(
            visualEffects(in: split.splitViewItems[1].viewController.view).isEmpty,
            "D3 violation: the conversation content host must not materialize an ad-hoc visual effect view."
        )
    }

    func testDetailsCloseForgetsDraggedWidthAndReopenUsesOfficialDefault() {
        let presentation = NativeShellPresentation(mode: .conversation)
        presentation.openDetails()
        XCTAssertTrue(presentation.detailsVisible)
        XCTAssertEqual(presentation.detailsPreference, OfficialUISpec.Layout.detailsDefault)

        presentation.detailsPreference = OfficialUISpec.Layout.detailsMaximum
        presentation.closeDetails()
        XCTAssertFalse(presentation.detailsVisible)
        XCTAssertEqual(presentation.detailsPreference, 0)

        presentation.openDetails()
        XCTAssertTrue(presentation.detailsVisible)
        XCTAssertEqual(
            presentation.detailsPreference,
            OfficialUISpec.Layout.detailsDefault,
            "RC8 close/reopen must restore the official default rather than a stale dragged width"
        )
    }

    func testVisualEffectTreeInspectionRejectsInjectedStructuralMaterial() {
        let host = NSHostingView(rootView: Color.clear.frame(width: 40, height: 40))
        host.addSubview(NSVisualEffectView(frame: .zero))

        XCTAssertEqual(visualEffects(in: host).count, 1, "The runtime inspection must detect a real injected NSVisualEffectView.")
    }

    private func assertNoVisualEffects<V: View>(in view: V, surface: String) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        defer { window.orderOut(nil) }

        XCTAssertTrue(
            visualEffects(in: host).isEmpty,
            "D3 violation: \(surface) mounted an ad-hoc NSVisualEffectView in its runtime content tree."
        )
    }

    private func visualEffects(in root: NSView) -> [NSVisualEffectView] {
        let own = (root as? NSVisualEffectView).map { [$0] } ?? []
        return own + root.subviews.flatMap(visualEffects(in:))
    }
}
