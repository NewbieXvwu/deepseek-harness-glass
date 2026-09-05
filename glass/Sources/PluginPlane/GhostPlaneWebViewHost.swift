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
        case invalidNativeBridgeEvent
    }

    public let webView: WKWebView
    private let policy: GhostPlaneLoopbackPolicy
    private let responsePolicy: GhostPlaneResponsePolicy
    private let temporaryFiles: GhostPlaneTemporaryFileStore
    private var skeletonReady = false
    /// The main-frame request is retained only until its matching response
    /// policy callback. It lets Core reject even same-origin redirects rather
    /// than treating the final endpoint as a fresh capability.
    private var pendingMainFrameRequestURL: URL?
    private var eventFence = GhostPlaneEventBridgeFence(documentEpoch: 1)
    private var documentEpoch: UInt64 = 1
    /// Optional native sink receives only wire-decoded, fence-admitted plane events.
    /// It never receives raw WKScriptMessage bodies or page objects.
    public var onPlaneEvent: ((GhostPlaneBridgeEvent) -> Void)?

    public init(policy: GhostPlaneLoopbackPolicy) {
        self.policy = policy
        responsePolicy = GhostPlaneResponsePolicy(loopback: policy)
        temporaryFiles = GhostPlaneTemporaryFileStore()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(temporaryFiles, forURLScheme: GhostPlaneTemporaryFileStore.scheme)
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(Self.tapIndexBootstrap)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(self, name: "ghostPlaneEvents")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
    }

    /// Loads only native-authored, content-empty skeleton HTML at the exact
    /// policy origin. Plugin bundle URLs still have to pass navigation policy
    /// and the separate module-manifest admission before activation.
    @discardableResult
    public func loadSkeleton(_ html: String) -> WKNavigation? {
        skeletonReady = false
        temporaryFiles.revokeAll()
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
                        contentWorld: .page
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
                        contentWorld: .page
        )
    }


    /// Rebinds every bridge fence to a new native document generation. Old
    /// asynchronous scroll/event work may still complete, but the page-side
    /// epoch fence will reject it after this transition.
    public func beginDocument(epoch: UInt64) {
        guard epoch > 0 else { return }
        documentEpoch = epoch
        eventFence = GhostPlaneEventBridgeFence(documentEpoch: epoch)
        temporaryFiles.revokeAll()
    }

    @discardableResult
    public func leaseTemporaryFile(
        at url: URL, id: UUID, suggestedName: String, mediaType: String
    ) throws -> URL {
        try temporaryFiles.lease(
            fileURL: url, id: id, suggestedName: suggestedName, mediaType: mediaType
        ).url
    }

    @discardableResult
    public func leaseTemporaryData(
        _ data: Data, id: UUID, suggestedName: String, mediaType: String
    ) throws -> URL {
        try temporaryFiles.lease(
            data: data, id: id, suggestedName: suggestedName, mediaType: mediaType
        ).url
    }

    public func releaseTemporaryFile(id: UUID) { temporaryFiles.revoke(id) }

    public func emitNativeKeyEvent(
        _ event: NSEvent,
        phase: GhostPlaneBridgeEvent.Keyboard.Phase,
        isComposing: Bool = false
    ) async throws {
        try await emitNativeBridgeEvent(
            GhostPlaneAppKitEventAdapter.keyboard(from: event, phase: phase, isComposing: isComposing)
        )
    }

    @discardableResult
    public func emitNativePasteboardImages(_ pasteboard: NSPasteboard = .general) async throws -> Int {
        let events = GhostPlaneAppKitEventAdapter.imagePasteEvents(from: pasteboard, host: self)
        for event in events { try await emitNativeBridgeEvent(event) }
        return events.count
    }

    /// Emits a Core-fenced native event as a fixed JSON DTO. The document can
    /// observe it only after bootstrap validation; this method never serializes
    /// AppKit/WebKit objects or injects executable JavaScript source.
    public func emitNativeBridgeEvent(_ event: GhostPlaneBridgeEvent) async throws {
        guard skeletonReady else { throw TapIndexApplicationError.skeletonNotReady }
        guard let message = eventFence.emitNative(event),
              let object = try JSONSerialization.jsonObject(with: GhostPlaneBridgeWireEncoder.encode(message)) as? [String: Any]
        else { throw TapIndexApplicationError.invalidNativeBridgeEvent }
        let ids: [UUID]
        switch event {
        case .imagePaste(let image): ids = [image.attachmentID]
        case .drag(let drag): ids = drag.attachmentIDs
        default: ids = []
        }
        var descriptors: [[String: String]] = []
        descriptors.reserveCapacity(ids.count)
        for id in ids {
            guard let descriptor = temporaryFiles.descriptor(for: id) else {
                throw TapIndexApplicationError.invalidNativeBridgeEvent
            }
            descriptors.append(descriptor.rendererPayload)
        }
        _ = try await webView.callAsyncJavaScript(
            """
            const ghostPlane = window.__DSH_GHOST_PLANE__;
            if (ghostPlane === undefined || typeof ghostPlane.applyNativeBridgeEvent !== 'function') {
              throw new Error('Ghost Plane native bridge bootstrap is unavailable');
            }
            return await ghostPlane.applyNativeBridgeEvent(arguments.message, arguments.files);
            """,
            arguments: ["message": object, "files": descriptors],
                        contentWorld: .page
        )
        switch event {
        case .imagePaste(let image): temporaryFiles.revoke(image.attachmentID)
        case .drag(let drag) where drag.phase == .drop || drag.phase == .leave:
            for id in drag.attachmentIDs { temporaryFiles.revoke(id) }
        default: break
        }
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
            return ghostPlane.applyScrollOffset(
              arguments.documentEpoch, arguments.sequence, arguments.scrollOffset
            );
            """,
            arguments: scalar.rendererArguments,
                        contentWorld: .page
        )
    }

    private func allow(_ url: URL?) -> Bool {
        guard let url else { return false }
        switch policy.decision(for: url) {
        case .allowSkeletonDocument, .allowPluginResource, .allowPluginCombo:
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
            const validPackageID = (id) => typeof id === 'string' && id.length > 0 && id.length <= 128
              && (/^[A-Za-z0-9._-]+$/.test(id) || /^@[A-Za-z0-9._-]+\\/[A-Za-z0-9._-]+$/.test(id));
            const validRegistration = (registration) => registration !== null
              && typeof registration === 'object'
              && validPackageID(registration.id)
              && typeof registration.factory === 'function';
            const load = (registration) => {
              if (!validRegistration(registration)) throw new Error('Ghost Plane module registration was rejected');
              const id = registration.id;
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
                  || !pluginIDs.every(validPackageID)) {
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
            'ghost-details-tool',
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
          let scrollEpoch = 0;
          let scrollSequence = 0;
          const applyScrollOffset = (documentEpoch, sequence, scrollOffset) => {
            if (!Number.isSafeInteger(documentEpoch) || documentEpoch < 1
                || !Number.isSafeInteger(sequence) || sequence < 1
                || typeof scrollOffset !== 'number' || !Number.isFinite(scrollOffset)) {
              throw new Error('Ghost Plane scroll sample was rejected');
            }
            if (documentEpoch < scrollEpoch) return false;
            if (documentEpoch > scrollEpoch) {
              scrollEpoch = documentEpoch;
              scrollSequence = 0;
            }
            if (sequence <= scrollSequence) return false;
            const content = document.getElementById('ghost-scroll-content');
            if (content === null) throw new Error('Ghost Plane scroll content is absent');
            scrollSequence = sequence;
            content.style.transform = `translate3d(0, ${-scrollOffset}px, 0)`;
            content.style.setProperty('--ghost-scroll-offset', String(scrollOffset));
            content.dataset.ghostScrollEpoch = String(documentEpoch);
            content.dataset.ghostScrollSequence = String(sequence);
            return true;
          };
          const buildFileTransfer = async (files) => {
            if (!Array.isArray(files)) throw new Error('Ghost Plane file descriptors were rejected');
            const transfer = new DataTransfer();
            for (const descriptor of files) {
              if (descriptor === null || typeof descriptor !== 'object'
                  || typeof descriptor.url !== 'string' || !descriptor.url.startsWith('dsh-glass-attachment://')
                  || typeof descriptor.suggestedName !== 'string' || descriptor.suggestedName.length < 1
                  || typeof descriptor.mediaType !== 'string' || descriptor.mediaType.length < 1) {
                throw new Error('Ghost Plane temporary file descriptor was rejected');
              }
              const response = await fetch(descriptor.url, { cache: 'no-store' });
              const bytes = await response.blob();
              transfer.items.add(new File([bytes], descriptor.suggestedName, { type: descriptor.mediaType }));
            }
            return transfer;
          };
          const bridgeTarget = () => document.activeElement instanceof HTMLElement
            ? document.activeElement
            : (document.body ?? document.documentElement);
          let bridgeEpoch = 0;
          let bridgeSequence = 0;
          const applyNativeBridgeEvent = async (message, files) => {
            if (message === null || typeof message !== 'object'
                || message.direction !== 'nativeToPlane'
                || !Number.isSafeInteger(message.documentEpoch) || message.documentEpoch < 1
                || !Number.isSafeInteger(message.sequence) || message.sequence < 1
                || message.event === null || typeof message.event !== 'object'
                || !['keyboard', 'imagePaste', 'selection', 'drag'].includes(message.event.kind)) {
              throw new Error('Ghost Plane native bridge event was rejected');
            }
            if (message.documentEpoch < bridgeEpoch) return false;
            if (message.documentEpoch > bridgeEpoch) {
              bridgeEpoch = message.documentEpoch;
              bridgeSequence = 0;
            }
            if (message.sequence <= bridgeSequence) return false;
            bridgeSequence = message.sequence;
            const stillCurrent = () => message.documentEpoch === bridgeEpoch && message.sequence === bridgeSequence;
            const event = message.event;
            switch (event.kind) {
              case 'keyboard': {
                const modifiers = event.modifiers >>> 0;
                const type = event.phase === 'down' ? 'keydown' : event.phase === 'up' ? 'keyup' : null;
                if (type === null) throw new Error('Ghost Plane keyboard phase was rejected');
                bridgeTarget().dispatchEvent(new KeyboardEvent(type, {
                  key: event.key, code: event.code, location: event.location, repeat: event.isRepeat,
                  isComposing: event.isComposing, shiftKey: (modifiers & 1) !== 0,
                  ctrlKey: (modifiers & 2) !== 0, altKey: (modifiers & 4) !== 0,
                  metaKey: (modifiers & 8) !== 0, bubbles: true, cancelable: true, composed: true,
                }));
                break;
              }
              case 'imagePaste': {
                const transfer = await buildFileTransfer(files);
                if (!stillCurrent()) return false;
                if (transfer.files.length !== 1) throw new Error('Ghost Plane image paste requires one File');
                bridgeTarget().dispatchEvent(new ClipboardEvent('paste', {
                  clipboardData: transfer, bubbles: true, cancelable: true, composed: true,
                }));
                break;
              }
              case 'selection': {
                const anchor = document.getElementById(event.anchorID);
                const focus = document.getElementById(event.focusID);
                const selection = window.getSelection();
                if (anchor === null || focus === null || selection === null
                    || !Number.isSafeInteger(event.anchorOffset) || event.anchorOffset < 0
                    || !Number.isSafeInteger(event.focusOffset) || event.focusOffset < 0
                    || event.anchorOffset > anchor.childNodes.length || event.focusOffset > focus.childNodes.length) {
                  throw new Error('Ghost Plane selection was rejected');
                }
                selection.setBaseAndExtent(anchor, event.anchorOffset, focus, event.focusOffset);
                document.dispatchEvent(new Event('selectionchange'));
                break;
              }
              case 'drag': {
                const transfer = await buildFileTransfer(files);
                if (!stillCurrent()) return false;
                const types = { enter: 'dragenter', over: 'dragover', leave: 'dragleave', drop: 'drop' };
                const type = types[event.dragPhase];
                if (type === undefined) throw new Error('Ghost Plane drag phase was rejected');
                transfer.dropEffect = ['copy', 'move', 'link', 'none'].includes(event.operation) ? event.operation : 'none';
                const target = document.elementFromPoint(event.x, event.y) ?? bridgeTarget();
                target.dispatchEvent(new DragEvent(type, {
                  dataTransfer: transfer, clientX: event.x, clientY: event.y,
                  bubbles: true, cancelable: true, composed: true,
                }));
                break;
              }
            }
            document.dispatchEvent(new CustomEvent('dsh-ghost-plane-native-event', { detail: message }));
            return true;
          };
          Object.defineProperty(window, '__DSH_GHOST_PLANE__', {
            configurable: false,
            enumerable: false,
            writable: false,
            value: Object.freeze({ applyTapIndex, applyScrollOffset, applyNativeBridgeEvent, promoteModuleFactories: moduleLoader.promote }),
          });
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true,
        in: .page
    )
}

extension GhostPlaneWebViewHost: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "ghostPlaneEvents",
              JSONSerialization.isValidJSONObject(message.body),
              let data = try? JSONSerialization.data(withJSONObject: message.body),
              let bridgeMessage = try? GhostPlaneBridgeWireDecoder.decode(data),
              case .deliver(let event) = eventFence.receivePlane(bridgeMessage)
        else { return }
        onPlaneEvent?(event)
    }
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
        case .allowSkeletonDocument, .allowPluginResource, .allowPluginCombo:
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
