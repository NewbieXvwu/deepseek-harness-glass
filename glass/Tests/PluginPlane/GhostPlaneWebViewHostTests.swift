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
        XCTAssertNotNil(host.loadSkeleton("<html><head></head><body><div data-ghost-plane=\"skeleton\"></div></body></html>"))
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
        <div id="ghost-plane-root"></div><div id="ghost-details-tool"></div><div id="ghost-scroll-content"></div>
        </body></html>
        """))
        await fulfillment(of: [loaded], timeout: 5)
        try await host.applyTapIndex(try admittedReplay())

        let result = try await host.webView.callAsyncJavaScript(
            """
            const root = document.getElementById('ghost-plane-root');
            const tool = document.getElementById('ghost-details-tool');
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
                        contentWorld: .page
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
                        contentWorld: .page
        ) as? [String: Any]
        XCTAssertEqual(scrollResult?["transform"] as? String, "translate3d(0px, -42.5px, 0px)")
        XCTAssertEqual(scrollResult?["offset"] as? String, "42.5")

        try await host.applyScrollOffset(.init(documentEpoch: 1, sequence: 2, scrollOffset: 80))
        try await host.applyScrollOffset(.init(documentEpoch: 1, sequence: 1, scrollOffset: 12))
        host.beginDocument(epoch: 2)
        try await host.applyScrollOffset(.init(documentEpoch: 2, sequence: 1, scrollOffset: 21))
        try await host.applyScrollOffset(.init(documentEpoch: 1, sequence: 99, scrollOffset: 999))
        let fenced = try await host.webView.callAsyncJavaScript(
            """
            const content = document.getElementById('ghost-scroll-content');
            return {
              transform: content.style.transform,
              epoch: content.dataset.ghostScrollEpoch,
              sequence: content.dataset.ghostScrollSequence,
            };
            """,
            arguments: [:], contentWorld: .page
        ) as? [String: Any]
        XCTAssertEqual(fenced?["transform"] as? String, "translate3d(0px, -21px, 0px)")
        XCTAssertEqual(fenced?["epoch"] as? String, "2")
        XCTAssertEqual(fenced?["sequence"] as? String, "1")
    }

    func testNativePermitPromotesExactQueuedFactoriesWithoutInvokingThem() async throws {
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
        XCTAssertNotNil(host.loadSkeleton("<!doctype html><html><head></head><body><div id=\"ghost-scroll-content\"></div></body></html>"))
        await fulfillment(of: [loaded], timeout: 5)
        _ = try await host.webView.callAsyncJavaScript(
            """
            window.__ModuleLoader__.load({
              id: 'dsh-review-loop',
              factory: () => { throw new Error('factory must not run during promotion'); },
            });
            return window.__ModuleLoader__.mode;
            """,
            arguments: [:], contentWorld: .page
        )
        try await host.promoteModuleFactories([try activationPermit()])
        let result = try await host.webView.callAsyncJavaScript(
            """
            return {
              mode: window.__ModuleLoader__.mode,
              queued: window.__ModuleLoader__.pendingQueue.length,
              live: window.__ModuleLoader__.factories.has('dsh-review-loop'),
            };
            """,
            arguments: [:], contentWorld: .page
        ) as? [String: Any]
        XCTAssertEqual(result?["mode"] as? String, "live")
        XCTAssertEqual(result?["queued"] as? Int, 0)
        XCTAssertEqual(result?["live"] as? Bool, true)
    }

    func testNativeBridgeEventUsesFixedDTOAndDocumentReceiver() async throws {
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
        XCTAssertNotNil(host.loadSkeleton("<!doctype html><html><head></head><body><div id=\"ghost-scroll-content\"></div></body></html>"))
        await fulfillment(of: [loaded], timeout: 5)
        _ = try await host.webView.callAsyncJavaScript(
            """
            document.addEventListener('dsh-ghost-plane-native-event', event => {
              window.__ghostNativeBridgeCapture = event.detail;
            }, { once: true });
            document.addEventListener('keydown', event => {
              window.__ghostStandardKeyboardCapture = {
                key: event.key, code: event.code, metaKey: event.metaKey, repeat: event.repeat,
              };
            }, { once: true });
            return true;
            """,
            arguments: [:], contentWorld: .page
        )
        try await host.emitNativeBridgeEvent(.keyboard(.init(
            phase: .down, key: "Enter", code: "Enter", location: 0,
            modifiers: [.command], isRepeat: false, isComposing: false
        )))
        let result = try await host.webView.callAsyncJavaScript(
            """
            const value = window.__ghostNativeBridgeCapture;
            const keyboard = window.__ghostStandardKeyboardCapture;
            return {
              direction: value?.direction, epoch: value?.documentEpoch, sequence: value?.sequence,
              key: value?.event?.key, standardKey: keyboard?.key, standardCode: keyboard?.code,
              standardMeta: keyboard?.metaKey,
            };
            """,
            arguments: [:], contentWorld: .page
        ) as? [String: Any]
        XCTAssertEqual(result?["direction"] as? String, "nativeToPlane")
        XCTAssertEqual(result?["epoch"] as? Int, 1)
        XCTAssertEqual(result?["sequence"] as? Int, 1)
        XCTAssertEqual(result?["key"] as? String, "Enter")
        XCTAssertEqual(result?["standardKey"] as? String, "Enter")
        XCTAssertEqual(result?["standardCode"] as? String, "Enter")
        XCTAssertEqual(result?["standardMeta"] as? Bool, true)
    }

    func testNativeImagePasteSelectionAndDragBecomeStandardBrowserEvents() async throws {
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
        <!doctype html><html><head></head><body>
        <div id="ghost-scroll-content"></div>
        <div id="ghost-selection-a"><span></span></div>
        <div id="ghost-selection-b"><span></span></div>
        </body></html>
        """))
        await fulfillment(of: [loaded], timeout: 5)
        _ = try await host.webView.callAsyncJavaScript(
            """
            document.addEventListener('paste', event => {
              const file = event.clipboardData?.files?.[0];
              window.__ghostPasteCapture = file === undefined ? null : { name: file.name, type: file.type, size: file.size };
            }, { once: true });
            document.addEventListener('selectionchange', () => {
              const selection = window.getSelection();
              window.__ghostSelectionCapture = {
                anchor: selection?.anchorNode?.id, focus: selection?.focusNode?.id, collapsed: selection?.isCollapsed,
              };
            }, { once: true });
            document.addEventListener('dragenter', event => {
              const file = event.dataTransfer?.files?.[0];
              window.__ghostDragCapture = file === undefined ? null : { name: file.name, type: file.type, count: event.dataTransfer.files.length };
            }, { once: true });
            return true;
            """, arguments: [:], contentWorld: .page
        )

        let pasteID = UUID()
        try host.leaseTemporaryData(Data([1, 2, 3, 4]), id: pasteID, suggestedName: "pasted.png", mediaType: "image/png")
        try await host.emitNativeBridgeEvent(.imagePaste(.init(
            attachmentID: pasteID, suggestedName: "pasted.png", mediaType: "image/png"
        )))
        try await host.emitNativeBridgeEvent(.selection(.init(
            anchorID: "ghost-selection-a", anchorOffset: 0,
            focusID: "ghost-selection-b", focusOffset: 1, isCollapsed: false
        )))
        let dragID = UUID()
        try host.leaseTemporaryData(Data([5, 6]), id: dragID, suggestedName: "dragged.png", mediaType: "image/png")
        try await host.emitNativeBridgeEvent(.drag(.init(
            phase: .enter, operation: .copy, attachmentIDs: [dragID], x: 1, y: 1
        )))
        try await host.emitNativeBridgeEvent(.drag(.init(
            phase: .leave, operation: .none, attachmentIDs: [dragID], x: 1, y: 1
        )))

        let result = try await host.webView.callAsyncJavaScript(
            """
            return {
              paste: window.__ghostPasteCapture,
              selection: window.__ghostSelectionCapture,
              drag: window.__ghostDragCapture,
            };
            """, arguments: [:], contentWorld: .page
        ) as? [String: Any]
        let paste = result?["paste"] as? [String: Any]
        XCTAssertEqual(paste?["name"] as? String, "pasted.png")
        XCTAssertEqual(paste?["type"] as? String, "image/png")
        XCTAssertEqual(paste?["size"] as? Int, 4)
        let selection = result?["selection"] as? [String: Any]
        XCTAssertEqual(selection?["anchor"] as? String, "ghost-selection-a")
        XCTAssertEqual(selection?["focus"] as? String, "ghost-selection-b")
        XCTAssertEqual(selection?["collapsed"] as? Bool, false)
        let drag = result?["drag"] as? [String: Any]
        XCTAssertEqual(drag?["name"] as? String, "dragged.png")
        XCTAssertEqual(drag?["type"] as? String, "image/png")
        XCTAssertEqual(drag?["count"] as? Int, 1)
    }

    func testWebKitMessageHandlerDeliversOnlyWireDecodedFencedEvent() async throws {
        let host = GhostPlaneWebViewHost(policy: try policy())
        let loaded = expectation(description: "native skeleton completed")
        let received = expectation(description: "typed plane event delivered")
        var observation: NSKeyValueObservation?
        observation = host.webView.observe(\.isLoading, options: [.new]) { webView, change in
            if change.newValue == false, webView.url != nil {
                loaded.fulfill()
                observation?.invalidate()
                observation = nil
            }
        }
        defer { observation?.invalidate() }
        host.onPlaneEvent = { event in
            guard case let .keyboard(keyboard) = event else { return XCTFail("expected keyboard") }
            XCTAssertEqual(keyboard.key, "Enter")
            received.fulfill()
        }
        XCTAssertNotNil(host.loadSkeleton("<!doctype html><html><head></head><body><div id=\"ghost-scroll-content\"></div></body></html>"))
        await fulfillment(of: [loaded], timeout: 5)
        _ = try await host.webView.callAsyncJavaScript(
            """
            window.webkit.messageHandlers.ghostPlaneEvents.postMessage({
              documentEpoch: 1, sequence: 1, direction: 'planeToNative',
              event: { kind: 'keyboard', phase: 'down', key: 'Enter', code: 'Enter', location: 0, modifiers: 0, isRepeat: false, isComposing: false },
            });
            window.webkit.messageHandlers.ghostPlaneEvents.postMessage({
              documentEpoch: 1, sequence: 2, direction: 'wrong', event: { kind: 'keyboard' },
            });
            return true;
            """,
            arguments: [:], contentWorld: .page
        )
        await fulfillment(of: [received], timeout: 5)
    }

    private func policy() throws -> GhostPlaneLoopbackPolicy {
        try XCTUnwrap(GhostPlaneLoopbackPolicy(
            origin: URL(string: "http://127.0.0.1:7342/")!,
            pluginIDs: ["dsh-review-loop"]
        ))
    }

    private func admittedManifest() throws -> GhostPlaneModuleManifest {
        let policy = try policy()
        let data = Data("""
        {"rev":"graph-r1","entries":[{"id":"dsh-review-loop","url":"http://127.0.0.1:7342/plugins/??dsh-review-loop/client.js&rev=r1","rev":"r1","inject":[],"immediately":true,"external":[]}],"batches":[{"phase":"application","url":"http://127.0.0.1:7342/plugins/??dsh-review-loop/client.js&rev=batch-r1","rev":"batch-r1","entries":["dsh-review-loop"]}]}
        """.utf8)
        switch GhostPlaneModuleManifest.admit(data: data, policy: policy, staticModuleSpecifiers: []) {
        case .admitted(let value): return value
        case .rejected(let reason): throw NSError(
            domain: "GhostPlaneWebViewHostTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "manifest unexpectedly rejected: \(reason)"]
        )
        }
    }

    private func activationPermit() throws -> GhostPlaneModuleActivationGate.ActivationPermit {
        var gate = GhostPlaneModuleActivationGate(manifest: try admittedManifest(), staticModuleSpecifiers: [])
        guard case .admitted = gate.admitArrival(pluginID: "dsh-review-loop", revision: "r1") else {
            throw NSError(domain: "GhostPlaneWebViewHostTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "arrival unexpectedly rejected"])
        }
        switch gate.permitActivation(pluginID: "dsh-review-loop") {
        case .permitted(let permit): return permit
        case .rejected(let reason): throw NSError(
            domain: "GhostPlaneWebViewHostTests",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "activation unexpectedly rejected: \(reason)"]
        )
        }
    }

    private func admittedReplay() throws -> GhostPlaneTapIndexReplay {
        let manifest = try admittedManifest()
        let source = GhostPlaneTapIndexReplay.Source(pluginID: "dsh-review-loop", revision: "r1")
        let records: [GhostPlaneTapIndexReplay.Record] = [
            .init(
                source: source,
                target: .planeRoot,
                mutation: .setCustomProperty(name: "--dsh-accent", value: "#3b82f6")
            ),
            .init(
                source: source,
                target: .detailsTool,
                mutation: .setDataAttribute(name: "data-ghost-mode", value: "review")
            ),
            .init(
                source: source,
                target: .detailsTool,
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
