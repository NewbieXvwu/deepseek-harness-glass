import Foundation

/// Explicit native ownership states for the bundled DeepSeek Harness Host.
/// A URL is data carried by `.ready`, never a substitute for lifecycle state.
enum HostLifecycleState: Equatable, Sendable {
    case idle
    case startingOwned
    case verifying(URL)
    case ready(HostConnection)
    case recovering(attempt: Int)
    case failed(HostFailure)
    case stopping

    var endpoint: URL? {
        switch self {
        case let .verifying(url): return url
        case let .ready(connection): return connection.endpoint
        default: return nil
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}
