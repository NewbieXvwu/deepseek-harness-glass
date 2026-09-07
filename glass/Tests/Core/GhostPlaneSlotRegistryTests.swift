import XCTest
@testable import GlassCore

final class GhostPlaneSlotRegistryTests: XCTestCase {
    func testLoadsAllRc1SlotsWithSourceBackedOwnership() throws {
        let registry = try GhostPlaneSlotRegistry()
        XCTAssertEqual(registry.slots.count, 25)
        XCTAssertEqual(registry.greenSlots.count, 20)
        XCTAssertEqual(registry.redSlots.map(\.name).sorted(), [
            "conversation.chat.node",
            "conversation.composer",
            "conversation.session",
            "conversation.session.header",
        ])
        XCTAssertEqual(registry.managedSlots.map(\.name), ["conversation.view"])
        XCTAssertTrue(registry.slots.allSatisfy { $0.sourcePath.hasPrefix("packages/client/") })
        XCTAssertFalse(registry.slots.contains { $0.name == "tool.call.toolview" })
    }

    func testGreenRegistrationIsOrderedAndUnregisters() throws {
        var registry = try GhostPlaneSlotRegistry()
        let later = try registry.register(
            pluginID: "dsh-review", id: "review",
            slotName: "conversation.chat.turnTail", order: 100
        )
        let first = try registry.register(
            pluginID: "dsh-status", id: "status",
            slotName: "conversation.chat.turnTail", order: -5
        )
        XCTAssertEqual(registry.placements(in: "conversation.chat.turnTail").map(\.id), [first.id, later.id])
        registry.unregister(first)
        XCTAssertEqual(registry.placements(in: "conversation.chat.turnTail"), [later])
    }

    func testRedManagedUnknownAndDuplicateRegistrationsFailClosed() throws {
        var registry = try GhostPlaneSlotRegistry()
        _ = try registry.register(
            pluginID: "@deepseek-ai/review", id: "review",
            slotName: "conversation.details.tool"
        )
        XCTAssertThrowsError(try registry.register(
            pluginID: "@deepseek-ai/review", id: "review",
            slotName: "conversation.details.tool"
        )) { XCTAssertEqual($0 as? GhostPlaneSlotRegistry.Rejection, .duplicateRegistration) }
        XCTAssertThrowsError(try registry.register(
            pluginID: "review", id: "red", slotName: "conversation.chat.node"
        )) { XCTAssertEqual($0 as? GhostPlaneSlotRegistry.Rejection, .redZone) }
        XCTAssertThrowsError(try registry.register(
            pluginID: "review", id: "view", slotName: "conversation.view"
        )) { XCTAssertEqual($0 as? GhostPlaneSlotRegistry.Rejection, .managedContainerRequired) }
        XCTAssertThrowsError(try registry.register(
            pluginID: "review", id: "missing", slotName: "tool.call.toolview"
        )) { XCTAssertEqual($0 as? GhostPlaneSlotRegistry.Rejection, .unknownSlot) }
        XCTAssertThrowsError(try registry.register(
            pluginID: "../escape", id: "review", slotName: "conversation.details.tool"
        )) { XCTAssertEqual($0 as? GhostPlaneSlotRegistry.Rejection, .invalidPluginID) }
    }
}
