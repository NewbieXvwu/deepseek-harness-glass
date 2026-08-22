import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Native UI-facing projection of a Host lifecycle state. The product-visible
/// words are generated official locale entries; diagnostics remain data from the
/// Host controller and never become unregistered UI copy.
struct HostLifecyclePresentation: Equatable, Sendable {
    let title: String
    let detail: String?
    let retryTitle: String?
    let permitsInteraction: Bool

    static func make(state: HostLifecycleState, language: String = "en") -> HostLifecyclePresentation {
        let loading = locale("loading", language: language)
        let failed = locale("load.failed", language: language)
        let retry = locale("retry", language: language)
        switch state {
        case .idle:
            return HostLifecyclePresentation(title: loading, detail: nil, retryTitle: nil, permitsInteraction: false)
        case let .probingExternal(endpoint):
            return HostLifecyclePresentation(title: loading, detail: endpoint?.absoluteString, retryTitle: nil, permitsInteraction: false)
        case .startingOwned, .verifying, .recovering:
            return HostLifecyclePresentation(title: loading, detail: nil, retryTitle: nil, permitsInteraction: false)
        case .ready:
            // The locked official locale exposes no "ready" copy; the loading
            // title is a placeholder and consumers gate on permitsInteraction
            // (true) rather than the title.
            return HostLifecyclePresentation(title: loading, detail: nil, retryTitle: nil, permitsInteraction: true)
        case let .unverified(status):
            return HostLifecyclePresentation(title: failed, detail: status.reason, retryTitle: retry, permitsInteraction: false)
        case let .failed(failure):
            return HostLifecyclePresentation(title: failed, detail: failure.message, retryTitle: retry, permitsInteraction: false)
        case .stopping:
            return HostLifecyclePresentation(title: loading, detail: nil, retryTitle: nil, permitsInteraction: false)
        }
    }

    private static func locale(_ key: String, language: String) -> String {
        OfficialUISpec.LocaleCatalog.value(namespace: "locale", key: key, language: language) ?? key
    }
}
