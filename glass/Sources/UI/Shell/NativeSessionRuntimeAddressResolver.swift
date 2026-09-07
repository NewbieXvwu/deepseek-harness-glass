#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
#endif

/// Maps the exact catalog-selected child route into the rc.1 session address.
/// A stale route can never retarget an unrelated ordinary session.
enum NativeSessionRuntimeAddressResolver {
    static func resolve(
        sessionID: String,
        subagentRoute: NativeSessionStore.SubagentRoute?
    ) -> SessionAddress {
        guard let route = subagentRoute, route.childSessionID == sessionID else {
            return .session(sessionID: sessionID)
        }
        let mode: SessionAddress.ChildMode
        switch route.mode {
        case .oneShot: mode = .oneShot
        case .continuable: mode = .continuable
        }
        return .subagent(
            parentSessionID: route.parentSessionID,
            childSessionID: route.childSessionID,
            mode: mode
        )
    }
}
