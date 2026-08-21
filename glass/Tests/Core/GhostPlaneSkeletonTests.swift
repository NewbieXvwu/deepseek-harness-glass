@testable import GlassCore
@testable import GlassSpec

final class GhostPlaneSkeletonTests: XCTestCase {
    func testSkeletonUsesOfficialColumnLayoutAndRetainsEmptyStructuralContracts() throws {
        let input = GhostPlaneSkeletonInput(
            viewportWidth: 1_280,
            sidebarPreference: 240,
            detailsPreference: 320,
            anchors: [
                .init(key: "message:1", kind: .user),
                .init(key: "call:tool-1", kind: .tool),
                .init(key: "turn:1", kind: .turnTail),
            ]
        )
        let skeleton = try GhostPlaneSkeleton.build(input)
        let official = OfficialColumnLayout.resolve(viewport: 1_280, sidebarPreference: 240, detailsPreference: 320)

        XCTAssertEqual(skeleton.layout.sidebarWidth, Double(official.sidebar))
        XCTAssertEqual(skeleton.layout.centerWidth, Double(official.center))
        XCTAssertEqual(skeleton.layout.detailsWidth, Double(official.details))
        XCTAssertEqual(skeleton.elements.anchorElementIDs["message:1"], "ghost-chat-anchor-message:1")
        XCTAssertEqual(skeleton.elements.scrollContentID, "ghost-scroll-content")
        XCTAssertTrue(skeleton.html.contains("data-conversation-scroll=\"\""))
        XCTAssertTrue(skeleton.html.contains("data-ghost-scroll-content=\"\""))
        XCTAssertTrue(skeleton.html.contains("data-chat-flow=\"\""))
        XCTAssertTrue(skeleton.html.contains("data-chat-flow-kind=\"tool\""))
        XCTAssertTrue(skeleton.html.contains("data-phase=\"active\""))
        XCTAssertTrue(skeleton.html.contains("data-composer-seat=\"\""))
        XCTAssertTrue(skeleton.html.contains("data-slot=\"conversation.chat.turnTail\""))
        XCTAssertTrue(skeleton.html.contains("data-slot=\"tool.call.toolview\""))
        XCTAssertTrue(skeleton.html.contains("data-chat-anchor-key=\"call:tool-1\""))
        XCTAssertTrue(skeleton.html.contains("data-streaming=\"false\""))
        XCTAssertFalse(skeleton.html.contains("user authored content"))
    }

    func testSkeletonRejectsDuplicateOrUnsafeAnchorBeforeHTMLEmission() {
        XCTAssertThrowsError(try GhostPlaneSkeleton.build(.init(
            viewportWidth: 800,
            sidebarPreference: 0,
            detailsPreference: 0,
            anchors: [
                .init(key: "message:1", kind: .user),
                .init(key: "message:1", kind: .assistant),
            ]
        ))) { XCTAssertEqual($0 as? GhostPlaneSkeleton.Error, .duplicateAnchorKey) }

        XCTAssertThrowsError(try GhostPlaneSkeleton.build(.init(
            viewportWidth: 800,
            sidebarPreference: 0,
            detailsPreference: 0,
            anchors: [.init(key: "<script>", kind: .assistant)]
        ))) { XCTAssertEqual($0 as? GhostPlaneSkeleton.Error, .invalidAnchorKey) }
    }

    func testSelectorInventoryIsExplicitAndStable() {
        XCTAssertEqual(GhostPlaneSkeleton.requiredSelectors, [
            "[data-conversation-scroll]",
            "[data-chat-flow]",
            "[data-chat-anchor-key]",
            "[data-chat-flow-key]",
            "[data-chat-flow-kind]",
            "[data-streaming]",
            "[data-phase]",
            "[data-composer-seat]",
            "[data-slot=conversation.session]",
            "[data-slot=conversation.session.header]",
            "[data-slot=conversation.chat.node]",
            "[data-slot=conversation.chat.turnTail]",
            "[data-slot=conversation.details.tool]",
            "[data-slot=conversation.composer]",
            "[data-slot=tool.call.toolview]",
        ])
    }
}
