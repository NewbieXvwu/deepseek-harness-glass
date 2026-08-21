import AppKit
import GlassCore
import WebKit

/// The only project target that owns a WKWebView for the registered Ghost
/// Plane. Core/UI/App never import this target; every navigation is delegated
/// to the shared fail-closed loopback policy before WebKit can follow it.
@MainActor
public final class GhostPlaneWebViewHost: NSObject {
    public let webView: WKWebView
    private let policy: GhostPlaneLoopbackPolicy

    public init(policy: GhostPlaneLoopbackPolicy) {
        self.policy = policy
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
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
        webView.loadHTMLString(html, baseURL: policy.origin)
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
}
