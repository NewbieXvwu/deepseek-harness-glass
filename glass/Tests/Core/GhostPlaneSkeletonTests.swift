import XCTest
@testable import GlassCore

final class GhostPlaneSkeletonTests: XCTestCase {
    func testBuildUsesOnlyRc1DomAnchorsAndTransparentGreenSeats() throws {
        let skeleton = try GhostPlaneSkeleton.build(.init(
            viewportWidth: 1280,
            sidebarPreference: 280,
            detailsPreference: 320,
            anchors: [
                .init(key: "message:1", kind: .assistant),
                .init(key: "tool:2", kind: .tool),
            ]
        ))
        XCTAssertEqual(skeleton.elements.anchorElementIDs["message:1"], "ghost-chat-anchor-message:1")
        XCTAssertEqual(skeleton.elements.scrollContentID, "ghost-scroll-content")
        XCTAssertTrue(skeleton.html.contains("data-conversation-scroll"))
        XCTAssertTrue(skeleton.html.contains("data-chat-flow"))
        XCTAssertTrue(skeleton.html.contains("data-composer-seat"))
        XCTAssertTrue(skeleton.html.contains("data-ghost-slot=\"conversation.chat.turnTail\""))
        XCTAssertTrue(skeleton.html.contains("data-ghost-slot=\"conversation.details.tool\""))
        XCTAssertTrue(skeleton.html.contains("data-ghost-slot=\"conversation.input.right\""))
        XCTAssertTrue(skeleton.html.contains("data-ghost-owner-key=\"message:1\""))
        XCTAssertFalse(skeleton.html.contains("data-slot="))
        XCTAssertFalse(skeleton.html.contains("tool.call.toolview"))
        XCTAssertFalse(skeleton.html.contains("conversation.chat.node\""))
        XCTAssertFalse(skeleton.html.contains("conversation.session\""))
        XCTAssertFalse(skeleton.html.contains("conversation.view\""))
    }

    func testSelectorInventoryMatchesFreshRc1Contract() throws {
        let fixture = try OfficialGhostPlaneContract.load()
        try OfficialGhostPlaneContract.validateSkeletonSelectors(
            GhostPlaneSkeleton.requiredSelectors,
            against: fixture
        )
        XCTAssertEqual(GhostPlaneSkeleton.requiredSelectors.count, 8)
    }

    func testRejectsDuplicateAndInvalidAnchorKeys() {
        XCTAssertThrowsError(try GhostPlaneSkeleton.build(.init(
            viewportWidth: 1000, sidebarPreference: 200, detailsPreference: 200,
            anchors: [.init(key: "same", kind: .assistant), .init(key: "same", kind: .tool)]
        )))
        XCTAssertThrowsError(try GhostPlaneSkeleton.build(.init(
            viewportWidth: 1000, sidebarPreference: 200, detailsPreference: 200,
            anchors: [.init(key: "bad key", kind: .assistant)]
        )))
    }
}
