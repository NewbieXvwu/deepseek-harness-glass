import Foundation
import XCTest
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

        XCTAssertEqual(skeleton.layout.sidebarWidth, 264)
        XCTAssertEqual(skeleton.layout.centerWidth, 696)
        XCTAssertEqual(skeleton.layout.detailsWidth, 320)
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
}
