import Foundation

/// Explicit native ownership states for the bundled DeepSeek Harness Host.
/// A URL is data carried by `.ready`, never a substitute for lifecycle state.
enum HostLifecycleState: Equatable, Sendable {
    case idle
    case starting
    case authenticating(URL)
    case connecting(URL)
    case classifying(URL)
    case ready(HostConnection)
    case recovering(attempt: Int)
    case failed(HostFailure)
    case stopping

    var endpoint: URL? {
        switch self {
        case let .authenticating(url), let .connecting(url), let .classifying(url): return url
        case let .ready(connection): return connection.endpoint
        default: return nil
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}
