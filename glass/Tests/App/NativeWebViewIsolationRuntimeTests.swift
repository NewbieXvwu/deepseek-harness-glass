import AppKit
import SwiftUI
import WebKit
import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

@MainActor
final class NativeWebViewIsolationRuntimeTests: XCTestCase {
    func testCoreNativeSurfacesContainNoWebViewsAtRuntime() {
        assertNoWebViews(
            in: NativeSidebarView(
                workspaceStore: NativeWorkspaceStore(),
                collapsed: false,
                setCollapsed: { _ in },
                workspaceActions: WorkspaceBrowserView.Actions(),
                workspaceSnapshotDialog: .none,
                onNewSession: {},
                onOpenSettings: {}
            ),
            surface: "sidebar"
        )
        assertNoWebViews(
            in: NativeConversationColumn(
                mode: .conversation,
                selectedWorkspaceTitle: "Fixture workspace",
                sessionSnapshot: .empty,
                sessionStore: NativeSessionStore(),
                agentPresetStore: NativeAgentPresetStore(),
                selectAgentPreset: { _, _ in false },
                jobsPopoverInitiallyOpen: false,
                jobsLanguageCode: nil,
                openSession: { _ in },
                canOpenProjectPath: false,
                viewRegistry: NativeConversationViewRegistry(),
                headerContributions: NativeConversationHeaderContributionRegistry()
            ),
            surface: "conversation"
        )
        assertNoWebViews(
            in: NativeDetailsView(sessionStore: NativeSessionStore(), close: {}),
            surface: "details"
        )
    }

    func testWebViewTreeInspectionRejectsInjectedWebView() {
        let host = NSHostingView(rootView: Color.clear.frame(width: 40, height: 40))
        let webView = WKWebView(frame: .zero)
        host.addSubview(webView)

        XCTAssertEqual(webViews(in: host).count, 1, "The runtime inspection must detect a real injected WKWebView.")
    }

    private func assertNoWebViews<V: View>(in view: V, surface: String) {
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
            webViews(in: host).isEmpty,
            "D0 violation: \(surface) mounted a WKWebView in its runtime NSView tree."
        )
    }

    private func webViews(in root: NSView) -> [WKWebView] {
        let own = (root as? WKWebView).map { [$0] } ?? []
        return own + root.subviews.flatMap(webViews(in:))
    }
}
