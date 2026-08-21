import AppKit
import GlassCore
import GlassPluginPlane
import WebKit
import XCTest

@MainActor
final class GhostPlaneWebViewHostTests: XCTestCase {
    func testRegisteredPluginPlaneOwnsExactlyOneEphemeralWebView() throws {
        let policy = try XCTUnwrap(GhostPlaneLoopbackPolicy(
            origin: URL(string: "http://127.0.0.1:7342/")!,
            pluginIDs: ["dsh-review-loop"]
        ))
        let host = GhostPlaneWebViewHost(policy: policy)

        XCTAssertTrue(host.webView.configuration.websiteDataStore.isPersistent == false)
        XCTAssertNil(host.webView.uiDelegate)
        XCTAssertNotNil(host.loadSkeleton("<html><body><div data-ghost-plane=\"skeleton\"></div></body></html>"))
        XCTAssertEqual(webViews(in: host.webView).count, 1)
    }

    func testPluginPlanePolicyKeepsHostAndPluginResourceBoundariesDistinct() throws {
        let policy = try XCTUnwrap(GhostPlaneLoopbackPolicy(
            origin: URL(string: "http://127.0.0.1:7342/")!,
            pluginIDs: ["dsh-review-loop"]
        ))

        XCTAssertEqual(policy.decision(for: policy.origin), .allowSkeletonDocument)
        XCTAssertEqual(
            policy.decision(for: URL(string: "http://127.0.0.1:7342/plugins/dsh-review-loop/client.js?rev=r1")!),
            .allowPluginResource(pluginID: "dsh-review-loop")
        )
        XCTAssertEqual(
            policy.decision(for: URL(string: "http://127.0.0.1:7342/api/host.describe")!),
            .deny(.nonPluginPath)
        )
    }

    private func webViews(in root: NSView) -> [WKWebView] {
        let own = (root as? WKWebView).map { [$0] } ?? []
        return own + root.subviews.flatMap(webViews(in:))
    }
}
