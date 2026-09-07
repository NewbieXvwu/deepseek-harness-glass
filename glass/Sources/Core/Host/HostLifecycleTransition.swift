import Foundation

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Auditable lifecycle edge emitted whenever the owned Host controller changes
/// explicit state. The endpoint, when present, remains payload of the state;
/// transition identity is always the declared case rather than URL nil-ness.
struct HostLifecycleTransition: Equatable, Sendable {
    let from: HostLifecycleState
    let to: HostLifecycleState
    let at: Date

    var summary: String {
        "\(Self.name(from)) -> \(Self.name(to))"
    }

    private static func name(_ state: HostLifecycleState) -> String {
        switch state {
        case .idle: return "idle"
        case .starting: return "starting"
        case .authenticating: return "authenticating"
        case .connecting: return "connecting"
        case .classifying: return "classifying"
        case .ready: return "ready"
        case .recovering: return "recovering"
        case .failed: return "failed"
        case .stopping: return "stopping"
        }
    }
}
