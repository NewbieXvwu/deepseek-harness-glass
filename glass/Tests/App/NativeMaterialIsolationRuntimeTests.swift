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
                openSession: { _ in }
            ),
            surface: "conversation-content"
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
