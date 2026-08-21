import Foundation

@main
struct GhostPlaneSlotRegistryPortableCheck {
    static func main() throws {
        var registry = GhostPlaneSlotRegistry()
        let second = try registry.register(pluginID: "dsh-review", id: "review", slot: .chatTurnTail, order: 100)
        let first = try registry.register(pluginID: "dsh-status", id: "status", slot: .chatTurnTail, order: -5)
        precondition(registry.placements(in: .chatTurnTail).map(\.id) == [first.id, second.id])
        do {
            _ = try registry.register(pluginID: "dsh-review", id: "review", slot: .chatTurnTail, order: 100)
            preconditionFailure("duplicate placement must fail closed")
        } catch GhostPlaneSlotRegistry.Rejection.duplicateRegistration {}
        do {
            _ = try registry.register(pluginID: "../escape", id: "status", slot: .session)
            preconditionFailure("unsafe plugin identity must fail closed")
        } catch GhostPlaneSlotRegistry.Rejection.invalidPluginID {}
        registry.unregister(first)
        precondition(registry.placements(in: .chatTurnTail) == [second])
    }
}
