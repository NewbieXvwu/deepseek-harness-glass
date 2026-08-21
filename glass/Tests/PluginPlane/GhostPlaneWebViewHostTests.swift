import AppKit
import GlassCore
import GlassPluginPlane
import WebKit
import XCTest

@MainActor
final class GhostPlaneWebViewHostTests: XCTestCase {
    func testRegisteredPluginPlaneOwnsExactlyOneEphemeralWebView() throws {
        let policy = try policy()
        let host = GhostPlaneWebViewHost(policy: policy)

        XCTAssertTrue(host.webView.configuration.websiteDataStore.isPersistent == false)
        XCTAssertNil(host.webView.uiDelegate)
        XCTAssertNotNil(host.loadSkeleton("<html><body><div data-ghost-plane=\"skeleton\"></div></body></html>"))
        XCTAssertEqual(webViews(in: host.webView).count, 1)
    }

    func testPluginPlanePolicyKeepsHostAndPluginResourceBoundariesDistinct() throws {
        let policy = try policy()

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

    func testTapIndexRejectsAnyWriteBeforeNativeSkeletonFinishes() async throws {
        let host = GhostPlaneWebViewHost(policy: try policy())
        let replay = try admittedReplay()

        do {
            try await host.applyTapIndex(replay)
            XCTFail("tapIndex must not write before the native skeleton finishes")
        } catch let error as GhostPlaneWebViewHost.TapIndexApplicationError {
            XCTAssertEqual(error, .skeletonNotReady)
        }
    }

    func testTapIndexAppliesOnlyAdmittedPrimitivePayloadToFixedSkeletonTargets() async throws {
        let host = GhostPlaneWebViewHost(policy: try policy())
        let loaded = expectation(description: "native skeleton completed")
        var observation: NSKeyValueObservation?
        observation = host.webView.observe(\.isLoading, options: [.new]) { webView, change in
            if change.newValue == false, webView.url != nil {
                loaded.fulfill()
                observation?.invalidate()
                observation = nil
            }
        }
        defer { observation?.invalidate() }

        XCTAssertNotNil(host.loadSkeleton("""
        <!doctype html><html><head><meta charset="utf-8"></head><body>
        <div id="ghost-plane-root"></div><div id="ghost-toolview"></div><div id="ghost-scroll-content"></div>
        </body></html>
        """))
        await fulfillment(of: [loaded], timeout: 5)
        try await host.applyTapIndex(try admittedReplay())

        let result = try await host.webView.callAsyncJavaScript(
            """
            const root = document.getElementById('ghost-plane-root');
            const tool = document.getElementById('ghost-toolview');
            return {
              color: root.style.getPropertyValue('--dsh-accent'),
              mode: tool.getAttribute('data-ghost-mode'),
              classPresent: tool.classList.contains('ghost-compat-review-tool'),
              executable: root.getAttribute('onclick'),
              moduleLoadType: typeof window.__ModuleLoader__?.load,
              moduleQueue: Array.isArray(window.__ModuleLoader__?.pendingQueue),
            };
            """,
            arguments: [:],
            in: nil,
            in: .page
        ) as? [String: Any]

        XCTAssertEqual(result?["color"] as? String, "#3b82f6")
        XCTAssertEqual(result?["mode"] as? String, "review")
        XCTAssertEqual(result?["classPresent"] as? Bool, true)
        XCTAssertNil(result?["executable"])
        XCTAssertEqual(result?["moduleLoadType"] as? String, "function")
        XCTAssertEqual(result?["moduleQueue"] as? Bool, true)

        try await host.applyScrollOffset(.init(documentEpoch: 1, sequence: 1, scrollOffset: 42.5))
        let scrollResult = try await host.webView.callAsyncJavaScript(
            """
            const content = document.getElementById('ghost-scroll-content');
            return {
              transform: content.style.transform,
              offset: content.style.getPropertyValue('--ghost-scroll-offset'),
            };
            """,
            arguments: [:],
            in: nil,
            in: .page
        ) as? [String: Any]
        XCTAssertEqual(scrollResult?["transform"] as? String, "translate3d(0px, -42.5px, 0px)")
        XCTAssertEqual(scrollResult?["offset"] as? String, "42.5")
    }

    private func policy() throws -> GhostPlaneLoopbackPolicy {
        try XCTUnwrap(GhostPlaneLoopbackPolicy(
            origin: URL(string: "http://127.0.0.1:7342/")!,
            pluginIDs: ["dsh-review-loop"]
        ))
    }

    private func admittedReplay() throws -> GhostPlaneTapIndexReplay {
        let policy = try policy()
        let data = Data("""
        {"rev":"graph-r1","entries":[{"id":"dsh-review-loop","url":"http://127.0.0.1:7342/plugins/dsh-review-loop/client.js?rev=r1","rev":"r1","inject":[],"immediately":true,"external":[]}]}
        """.utf8)
        let manifest: GhostPlaneModuleManifest
        switch GhostPlaneModuleManifest.admit(data: data, policy: policy, staticModuleSpecifiers: []) {
        case .admitted(let value): manifest = value
        case .rejected(let reason): throw NSError(
            domain: "GhostPlaneWebViewHostTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "manifest unexpectedly rejected: \(reason)"]
        )
        }
        let source = GhostPlaneTapIndexReplay.Source(pluginID: "dsh-review-loop", revision: "r1")
        let records: [GhostPlaneTapIndexReplay.Record] = [
            .init(
                source: source,
                target: .planeRoot,
                mutation: .setCustomProperty(name: "--dsh-accent", value: "#3b82f6")
            ),
            .init(
                source: source,
                target: .toolview,
                mutation: .setDataAttribute(name: "data-ghost-mode", value: "review")
            ),
            .init(
                source: source,
                target: .toolview,
                mutation: .addCompatibilityClass("ghost-compat-review-tool")
            ),
        ]
        switch GhostPlaneTapIndexReplay.admit(records: records, for: manifest) {
        case .admitted(let replay): return replay
        case .rejected(let reason): throw NSError(
            domain: "GhostPlaneWebViewHostTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "replay unexpectedly rejected: \(reason)"]
        )
        }
    }

    private func webViews(in root: NSView) -> [WKWebView] {
        let own = (root as? WKWebView).map { [$0] } ?? []
        return own + root.subviews.flatMap(webViews(in:))
    }
}
