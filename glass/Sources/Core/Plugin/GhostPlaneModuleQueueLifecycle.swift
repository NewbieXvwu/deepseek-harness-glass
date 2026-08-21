import Foundation

/// Opaque lifecycle ledger for the ModuleLoader queue-to-live transition. The
/// actual factory remains in the document; native Core tracks only identities
/// previously admitted by `GhostPlaneModuleActivationGate`, so queue state can
/// never itself grant code execution.
public struct GhostPlaneModuleQueueLifecycle: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case queue, live }
    public enum Rejection: Error, Equatable, Sendable { case duplicateFactory, unknownFactory, alreadyLive }
    public private(set) var mode: Mode = .queue
    private var queued: [String] = []
    private var live: Set<String> = []
    public init() {}

    public mutating func recordAdmittedFactory(_ permit: GhostPlaneModuleActivationGate.ActivationPermit) -> Result<Void, Rejection> {
        let id = permit.pluginID
        guard !queued.contains(id), !live.contains(id) else { return .failure(.duplicateFactory) }
        switch mode {
        case .queue: queued.append(id)
        case .live: live.insert(id)
        }
        return .success(())
    }

    /// One-way transition preserving queue order. The caller must obtain every
    /// permit separately; this method has no factory, export or require input.
    public mutating func switchToLive() -> Result<[String], Rejection> {
        guard mode == .queue else { return .failure(.alreadyLive) }
        mode = .live
        let drained = queued
        live.formUnion(queued)
        queued.removeAll(keepingCapacity: false)
        return .success(drained)
    }

    public func containsLiveFactory(pluginID: String) -> Bool { live.contains(pluginID) }
}
