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
        case duplicateModulePermit
    }

    public let webView: WKWebView
    private let policy: GhostPlaneLoopbackPolicy
    private let responsePolicy: GhostPlaneResponsePolicy
    private var skeletonReady = false
    /// The main-frame request is retained only until its matching response
    /// policy callback. It lets Core reject even same-origin redirects rather
    /// than treating the final endpoint as a fresh capability.
    private var pendingMainFrameRequestURL: URL?

    public init(policy: GhostPlaneLoopbackPolicy) {
        self.policy = policy
        responsePolicy = GhostPlaneResponsePolicy(loopback: policy)
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
        pendingMainFrameRequestURL = policy.origin
        guard let securedHTML = GhostPlaneContentSecurityPolicy.inject(into: html) else {
            pendingMainFrameRequestURL = nil
            return nil
        }
        return webView.loadHTMLString(securedHTML, baseURL: policy.origin)
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

    /// Promotes only native graph-admitted permit identities from the document
    /// queue into its live factory table. This call deliberately does not invoke
    /// a factory or provide exports/services; the later materializer must still
    /// satisfy typed injection before execution.
    public func promoteModuleFactories(_ permits: [GhostPlaneModuleActivationGate.ActivationPermit]) async throws {
        guard skeletonReady else { throw TapIndexApplicationError.skeletonNotReady }
        let ids = permits.map(\.pluginID)
        guard Set(ids).count == ids.count else { throw TapIndexApplicationError.duplicateModulePermit }
        _ = try await webView.callAsyncJavaScript(
            """
            const ghostPlane = window.__DSH_GHOST_PLANE__;
            if (ghostPlane === undefined || typeof ghostPlane.promoteModuleFactories !== 'function') {
              throw new Error('Ghost Plane module promotion bootstrap is unavailable');
            }
            return ghostPlane.promoteModuleFactories(arguments.pluginIDs);
            """,
            arguments: ["pluginIDs": ids],
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
            return true
        case .deny:
            return false
        }
    }

    private static let tapIndexBootstrap = WKUserScript(
        source: """
        (() => {
          'use strict';
          // Official ClientModuleSystem boots against a queue-form global facade,
          // then switches it to live factory registration. The native Ghost Plane
          // owns this one facade; no plugin may replace the table or register an
          // invalid factory shape. Actual bundle arrival/materialization stays
          // behind the later hard injection gate.
          const moduleLoader = (() => {
            let mode = { value: 'queue' };
            const pendingQueue = [];
            const factories = new Map();
            const validRegistration = (registration) => registration !== null
              && typeof registration === 'object'
              && typeof registration.id === 'string' && registration.id.length > 0
              && registration.id.length <= 128
              && /^[A-Za-z0-9._-]+(?:\\/client)?$/.test(registration.id)
              && typeof registration.factory === 'function';
            const load = (registration) => {
              if (!validRegistration(registration)) throw new Error('Ghost Plane module registration was rejected');
              const id = registration.id.endsWith('/client') ? registration.id.slice(0, -'/client'.length) : registration.id;
              if (mode.value === 'queue') {
                pendingQueue.push(Object.freeze({ id, factory: registration.factory }));
                return;
              }
              if (factories.has(id)) throw new Error(`Ghost Plane duplicate module factory: ${id}`);
              factories.set(id, registration.factory);
            };
            const promote = (pluginIDs) => {
              if (mode.value !== 'queue') throw new Error('Ghost Plane module loader is already live');
              if (!Array.isArray(pluginIDs) || pluginIDs.length === 0 || new Set(pluginIDs).size !== pluginIDs.length
                  || !pluginIDs.every(id => typeof id === 'string' && /^[A-Za-z0-9._-]+$/.test(id))) {
                throw new Error('Ghost Plane native module permits were rejected');
              }
              const permitted = new Set(pluginIDs);
              if (pendingQueue.length !== permitted.size || pendingQueue.some(registration => !permitted.has(registration.id))) {
                throw new Error('Ghost Plane queue does not exactly match native module permits');
              }
              for (const registration of pendingQueue) {
                if (factories.has(registration.id)) throw new Error(`Ghost Plane duplicate module factory: ${registration.id}`);
                factories.set(registration.id, registration.factory);
              }
              pendingQueue.splice(0);
              mode.value = 'live';
              return true;
            };
            return Object.freeze({ load, pendingQueue, factories, promote, get mode() { return mode.value; } });
          })();
          Object.defineProperty(window, '__ModuleLoader__', {
            configurable: false,
            enumerable: false,
            writable: false,
            value: moduleLoader,
          });
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
            value: Object.freeze({ applyTapIndex, applyScrollOffset, promoteModuleFactories: moduleLoader.promote }),
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
        let url = navigationAction.request.url
        let permitted = allow(url)
        if permitted && (navigationAction.targetFrame?.isMainFrame ?? true) {
            pendingMainFrameRequestURL = url
        }
        decisionHandler(permitted ? .allow : .cancel)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        guard navigationResponse.isForMainFrame,
              let requestURL = pendingMainFrameRequestURL,
              let responseURL = navigationResponse.response.url,
              let http = navigationResponse.response as? HTTPURLResponse
        else {
            skeletonReady = false
            decisionHandler(.cancel)
            return
        }
        switch responsePolicy.decision(
            requestURL: requestURL,
            responseURL: responseURL,
            statusCode: http.statusCode,
            mimeType: navigationResponse.response.mimeType
        ) {
        case .allowSkeletonDocument, .allowPluginResource:
            decisionHandler(.allow)
        case .deny:
            skeletonReady = false
            decisionHandler(.cancel)
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // A document can become ready only after its final navigation endpoint
        // remains inside the precise skeleton origin. Redirected/external pages
        // never become writable by the native compatibility renderer.
        skeletonReady = policy.decision(for: webView.url ?? policy.origin) == .allowSkeletonDocument
        pendingMainFrameRequestURL = nil
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        skeletonReady = false
        pendingMainFrameRequestURL = nil
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        skeletonReady = false
        pendingMainFrameRequestURL = nil
    }
}
