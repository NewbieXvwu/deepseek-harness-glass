import XCTest
@testable import GlassCore

final class GhostPlaneSlotRegistryTests: XCTestCase {
    func testRegistryOrdersFixedSlotEntriesAndSupportsDisposal() throws {
        var registry = GhostPlaneSlotRegistry()
        let later = try registry.register(pluginID: "dsh-review", id: "review", slot: .chatTurnTail, order: 100)
        let first = try registry.register(pluginID: "dsh-status", id: "status", slot: .chatTurnTail, order: -5)
        XCTAssertEqual(registry.placements(in: .chatTurnTail).map(\.id), [first.id, later.id])
        registry.unregister(first)
        XCTAssertEqual(registry.placements(in: .chatTurnTail), [later])
    }

    func testRegistryRejectsUnsafeOrDuplicatePlacementIdentity() throws {
        var registry = GhostPlaneSlotRegistry()
        _ = try registry.register(pluginID: "dsh-review", id: "review", slot: .toolview)
        XCTAssertThrowsError(try registry.register(pluginID: "dsh-review", id: "review", slot: .toolview)) {
            XCTAssertEqual($0 as? GhostPlaneSlotRegistry.Rejection, .duplicateRegistration)
        }
        XCTAssertThrowsError(try registry.register(pluginID: "../escape", id: "review", slot: .toolview)) {
            XCTAssertEqual($0 as? GhostPlaneSlotRegistry.Rejection, .invalidPluginID)
        }
    }
}
