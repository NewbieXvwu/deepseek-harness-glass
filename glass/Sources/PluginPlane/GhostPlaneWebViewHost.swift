import AppKit
import GlassCore
import WebKit

/// The only project target that owns a WKWebView for the registered Ghost
/// Plane. Core/UI/App never import this target; every navigation is delegated
/// to the shared fail-closed loopback policy before WebKit can follow it.
@MainActor
public final class GhostPlaneWebViewHost: NSObject {
    public enum TapIndexApplicationError: Swift.Error, Equatable {
        /// The host never writes into an arbitrary page. A replay becomes
        /// possible only after the native-owned skeleton has completed loading.
        case skeletonNotReady
    }

    public let webView: WKWebView
    private let policy: GhostPlaneLoopbackPolicy
    private var skeletonReady = false

    public init(policy: GhostPlaneLoopbackPolicy) {
        self.policy = policy
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(Self.tapIndexBootstrap)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
    }

    /// Loads only native-authored, content-empty skeleton HTML at the exact
    /// policy origin. Plugin bundle URLs still have to pass navigation policy
    /// and the separate module-manifest admission before activation.
    @discardableResult
    public func loadSkeleton(_ html: String) -> WKNavigation? {
        skeletonReady = false
        return webView.loadHTMLString(html, baseURL: policy.origin)
    }

    /// Applies a Core-admitted `tapIndex` compatibility plan to the native
    /// skeleton. The plan reaches JavaScript only as primitive call arguments,
    /// never as source interpolation, raw callback text, selector or HTML.
    ///
    /// The bootstrap repeats target/kind/prefix validation inside the document
    /// as defense in depth. It intentionally knows nothing about module loading
    /// or bridge capabilities; those remain hard gates for a later activation
    /// stage.
    public func applyTapIndex(_ replay: GhostPlaneTapIndexReplay) async throws {
        guard skeletonReady else { throw TapIndexApplicationError.skeletonNotReady }
        _ = try await webView.callAsyncJavaScript(
            """
            const ghostPlane = window.__DSH_GHOST_PLANE__;
            if (ghostPlane === undefined || typeof ghostPlane.applyTapIndex !== 'function') {
              throw new Error('Ghost Plane tapIndex bootstrap is unavailable');
            }
            return ghostPlane.applyTapIndex(arguments.records);
            """,
            arguments: ["records": replay.rendererPayload()],
            in: nil,
            in: .page
        )
    }

    /// Delivers the native-authoritative scalar to the one Ghost Plane document.
    /// The value is already sequence/epoch fenced by `GhostPlaneScrollSynchronizer`;
    /// this host adds document-readiness protection and passes only the numeric
    /// argument into a fixed bootstrap function.
    public func applyScrollOffset(_ scalar: GhostPlaneScrollScalar) async throws {
        guard skeletonReady else { throw TapIndexApplicationError.skeletonNotReady }
        _ = try await webView.callAsyncJavaScript(
            """
            const ghostPlane = window.__DSH_GHOST_PLANE__;
            if (ghostPlane === undefined || typeof ghostPlane.applyScrollOffset !== 'function') {
              throw new Error('Ghost Plane scroll bootstrap is unavailable');
            }
            return ghostPlane.applyScrollOffset(arguments.scrollOffset);
            """,
            arguments: scalar.rendererArguments,
            in: nil,
            in: .page
        )
    }

    private func allow(_ url: URL?) -> Bool {
        guard let url else { return false }
        switch policy.decision(for: url) {
        case .allowSkeletonDocument, .allowPluginResource:
            true
        case .deny:
            false
        }
    }

    private static let tapIndexBootstrap = WKUserScript(
        source: """
        (() => {
          'use strict';
          const targetIDs = new Set([
            'ghost-plane-root', 'ghost-session-header', 'ghost-conversation-scroll',
            'ghost-chat-flow', 'ghost-composer-seat', 'ghost-turn-tail',
            'ghost-toolview', 'ghost-details-tool',
          ]);
          const lowerToken = (value, maximum) => typeof value === 'string'
            && value.length > 0 && value.length <= maximum && /^[a-z0-9-]+$/.test(value);
          const customProperty = (name) => typeof name === 'string'
            && (name.startsWith('--dsh-') || name.startsWith('--ghost-'))
            && lowerToken(name.slice(2), 96);
          const safeCSSValue = (value) => typeof value === 'string'
            && value.length > 0 && value.length <= 256
            && !/(url|expression|@import)/i.test(value)
            && /^[ #%,()+./0-9A-Za-z-]+$/.test(value);
          const dataName = (name) => typeof name === 'string'
            && name.startsWith('data-ghost-') && lowerToken(name.slice('data-'.length), 96);
          const dataValue = (value) => typeof value === 'string'
            && value.length > 0 && value.length <= 128 && /^[A-Za-z0-9._:-]+$/.test(value);
          const compatibilityClass = (name) => typeof name === 'string'
            && name.startsWith('ghost-compat-') && lowerToken(name, 96);
          const applyTapIndex = (records) => {
            if (!Array.isArray(records)) throw new Error('Ghost Plane tapIndex records must be an array');
            for (const record of records) {
              if (record === null || typeof record !== 'object' || !targetIDs.has(record.targetID)) {
                throw new Error('Ghost Plane tapIndex target was rejected');
              }
              const target = document.getElementById(record.targetID);
              if (target === null) throw new Error('Ghost Plane skeleton target is absent');
              switch (record.kind) {
                case 'customProperty':
                  if (!customProperty(record.name) || !safeCSSValue(record.value)) {
                    throw new Error('Ghost Plane custom property was rejected');
                  }
                  target.style.setProperty(record.name, record.value);
                  break;
                case 'dataAttribute':
                  if (!dataName(record.name) || !dataValue(record.value)) {
                    throw new Error('Ghost Plane data attribute was rejected');
                  }
                  target.setAttribute(record.name, record.value);
                  break;
                case 'compatibilityClass':
                  if (!compatibilityClass(record.name)) {
                    throw new Error('Ghost Plane compatibility class was rejected');
                  }
                  target.classList.add(record.name);
                  break;
                default:
                  throw new Error('Ghost Plane tapIndex mutation kind was rejected');
              }
            }
            return true;
          };
          const applyScrollOffset = (scrollOffset) => {
            if (typeof scrollOffset !== 'number' || !Number.isFinite(scrollOffset)) {
              throw new Error('Ghost Plane scroll offset was rejected');
            }
            const content = document.getElementById('ghost-scroll-content');
            if (content === null) throw new Error('Ghost Plane scroll content is absent');
            content.style.transform = `translate3d(0, ${-scrollOffset}px, 0)`;
            content.style.setProperty('--ghost-scroll-offset', String(scrollOffset));
            return true;
          };
          Object.defineProperty(window, '__DSH_GHOST_PLANE__', {
            configurable: false,
            enumerable: false,
            writable: false,
            value: Object.freeze({ applyTapIndex, applyScrollOffset }),
          });
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true,
        in: .page
    )
}

extension GhostPlaneWebViewHost: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(allow(navigationAction.request.url) ? .allow : .cancel)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(allow(navigationResponse.response.url) ? .allow : .cancel)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // A document can become ready only after its final navigation endpoint
        // remains inside the precise skeleton origin. Redirected/external pages
        // never become writable by the native compatibility renderer.
        skeletonReady = policy.decision(for: webView.url ?? policy.origin) == .allowSkeletonDocument
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        skeletonReady = false
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        skeletonReady = false
    }
}
