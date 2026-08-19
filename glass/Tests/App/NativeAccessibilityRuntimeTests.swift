import AppKit
import SwiftUI
import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

@MainActor
final class NativeAccessibilityRuntimeTests: XCTestCase {
    func testCollapsedSidebarExportsAccessibleNamesForVisibleIconControls() {
        let view = NativeSidebarView(
            workspaceStore: NativeWorkspaceStore(),
            collapsed: true,
            setCollapsed: { _ in },
            workspaceActions: WorkspaceBrowserView.Actions(),
            workspaceSnapshotDialog: .none,
            onNewSession: {},
            onOpenSettings: {}
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 56, height: 840)
        host.layoutSubtreeIfNeeded()

        let labels = accessibilityLabels(in: host)
        XCTAssertTrue(labels.contains(OfficialUISpec.Text.openSidebarAccessibility))
        XCTAssertTrue(labels.contains(OfficialUISpec.Text.newSessionAccessibility))
        XCTAssertTrue(labels.contains(OfficialUISpec.Text.settings))
    }

    private func accessibilityLabels(in element: any NSAccessibility) -> [String] {
        let ownLabel = element.accessibilityLabel().map { [$0] } ?? []
        let childLabels = (element.accessibilityChildren() ?? []).flatMap { child -> [String] in
            guard let child = child as? any NSAccessibility else { return [] }
            return accessibilityLabels(in: child)
        }
        return ownLabel + childLabels
    }
}
