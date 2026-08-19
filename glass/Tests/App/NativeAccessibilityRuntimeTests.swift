import AppKit
import ApplicationServices
import SwiftUI
import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

@MainActor
final class NativeAccessibilityRuntimeTests: XCTestCase {
    func testCollapsedSidebarExportsAccessibleNamesForVisibleIconControls() throws {
        guard AXIsProcessTrusted() else {
            throw XCTSkip("The macOS-26 CI runner is not a trusted accessibility client; static core-path gate remains mandatory and this runtime tree test executes in trusted UI-test environments.")
        }
        let view = NativeSidebarView(
            workspaceStore: NativeWorkspaceStore(),
            collapsed: true,
            setCollapsed: { _ in },
            workspaceActions: WorkspaceBrowserView.Actions(),
            workspaceSnapshotDialog: .none,
            onNewSession: {},
            onOpenSettings: {}
        )
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 56, height: 840),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let labels = accessibilityLabels(in: host)
        window.orderOut(nil)
        XCTAssertTrue(labels.contains(OfficialUISpec.Text.openSidebarAccessibility), "exported labels: \(labels)")
        XCTAssertTrue(labels.contains(OfficialUISpec.Text.newSessionAccessibility), "exported labels: \(labels)")
        XCTAssertTrue(labels.contains(OfficialUISpec.Text.settings), "exported labels: \(labels)")
    }

    private func accessibilityLabels(in element: any NSAccessibilityProtocol) -> [String] {
        let ownLabel = element.accessibilityLabel().map { [$0] } ?? []
        let childLabels = (element.accessibilityChildren() ?? []).flatMap { child -> [String] in
            guard let child = child as? any NSAccessibilityProtocol else { return [] }
            return accessibilityLabels(in: child)
        }
        return ownLabel + childLabels
    }
}
