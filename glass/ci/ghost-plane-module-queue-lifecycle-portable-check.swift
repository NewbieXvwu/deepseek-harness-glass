import Foundation

@main
struct GhostPlaneModuleQueueLifecyclePortableCheck {
    static func main() {
        var lifecycle = GhostPlaneModuleQueueLifecycle()
        let runtime = GhostPlaneModuleActivationGate.ActivationPermit(pluginID: "runtime", revision: "r1", graphRevision: "graph")
        let review = GhostPlaneModuleActivationGate.ActivationPermit(pluginID: "review", revision: "r1", graphRevision: "graph")
        guard case .success = lifecycle.recordAdmittedFactory(runtime) else { preconditionFailure("runtime queue admission failed") }
        guard case .success = lifecycle.recordAdmittedFactory(review) else { preconditionFailure("review queue admission failed") }
        precondition(lifecycle.switchToLive() == .success(["runtime", "review"]))
        precondition(lifecycle.containsLiveFactory(pluginID: "runtime"))
        guard case .failure(.duplicateFactory) = lifecycle.recordAdmittedFactory(review) else { preconditionFailure("duplicate live factory must reject") }
        precondition(lifecycle.switchToLive() == .failure(.alreadyLive))
    }
}
