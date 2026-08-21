import XCTest
@testable import GlassUI

final class WorkspaceBrowserOrderingTests: XCTestCase {
    func testWorkspaceDropUsesHalfAnchorAndRejectsSelfOrAdjacentMoves() {
        let order = ["alpha", "bravo", "charlie"]

        XCTAssertEqual(
            NativeWorkspaceBrowserOrdering.workspaceDecision(
                workspaceID: "bravo",
                overWorkspaceID: "alpha",
                half: .after,
                workspaceIDs: order
            ),
            .noOp
        )
        XCTAssertEqual(
            NativeWorkspaceBrowserOrdering.workspaceDecision(
                workspaceID: "bravo",
                overWorkspaceID: "charlie",
                half: .before,
                workspaceIDs: order
            ),
            .noOp
        )
        XCTAssertEqual(
            NativeWorkspaceBrowserOrdering.workspaceDecision(
                workspaceID: "bravo",
                overWorkspaceID: "charlie",
                half: .after,
                workspaceIDs: order
            ),
            .host(workspaceID: "bravo", beforeWorkspaceID: nil)
        )
        XCTAssertEqual(
            NativeWorkspaceBrowserOrdering.workspaceDecision(
                workspaceID: "charlie",
                overWorkspaceID: "alpha",
                half: .before,
                workspaceIDs: order
            ),
            .host(workspaceID: "charlie", beforeWorkspaceID: "alpha")
        )
    }

    func testSessionDropKeepsLocalOrderForUngroupedAndUpdatedModes() {
        let order = ["alpha", "bravo", "charlie"]

        XCTAssertEqual(
            NativeWorkspaceBrowserOrdering.sessionDecision(
                sessionID: "charlie",
                accountKey: "workspace-a",
                overSessionID: "alpha",
                half: .before,
                orderedSessionIDs: order,
                orderMode: .manual
            ),
            .host(
                sessionID: "charlie",
                workspaceID: "workspace-a",
                beforeSessionID: "alpha",
                viewOrder: ["charlie", "alpha", "bravo"]
            )
        )

        XCTAssertEqual(
            NativeWorkspaceBrowserOrdering.sessionDecision(
                sessionID: "charlie",
                accountKey: "workspace-a",
                overSessionID: "alpha",
                half: .before,
                orderedSessionIDs: order,
                orderMode: .updated
            ),
            .local(order: ["charlie", "alpha", "bravo"])
        )

        XCTAssertEqual(
            NativeWorkspaceBrowserOrdering.sessionDecision(
                sessionID: "charlie",
                accountKey: NativeWorkspaceBrowserOrdering.ungroupedAccountKey,
                overSessionID: "alpha",
                half: .before,
                orderedSessionIDs: order,
                orderMode: .manual
            ),
            .local(order: ["charlie", "alpha", "bravo"])
        )

        XCTAssertEqual(
            NativeWorkspaceBrowserOrdering.sessionDecision(
                sessionID: "charlie",
                accountKey: NativeWorkspaceBrowserOrdering.flatSessionOrderKey,
                overSessionID: "alpha",
                half: .before,
                orderedSessionIDs: order,
                orderMode: .manual
            ),
            .local(order: ["charlie", "alpha", "bravo"])
        )
    }

    func testSessionDropRejectsSelfAndAdjacentAnchorsWithoutLocalOrHostMutation() {
        let order = ["alpha", "bravo", "charlie"]

        XCTAssertEqual(
            NativeWorkspaceBrowserOrdering.sessionDecision(
                sessionID: "bravo",
                accountKey: "workspace-a",
                overSessionID: "bravo",
                half: .before,
                orderedSessionIDs: order,
                orderMode: .manual
            ),
            .noOp
        )
        XCTAssertEqual(
            NativeWorkspaceBrowserOrdering.sessionDecision(
                sessionID: "bravo",
                accountKey: "workspace-a",
                overSessionID: "charlie",
                half: .before,
                orderedSessionIDs: order,
                orderMode: .manual
            ),
            .noOp
        )
    }

    func testBlankSessionPromotionMovesNewBlankToFrontAndIsIdempotent() {
        let initial = ["alpha", "blank", "bravo", "blank"]
        let promoted = NativeWorkspaceBrowserOrdering.orderPromotingBlankSession("blank", in: initial)

        XCTAssertEqual(promoted, ["blank", "alpha", "bravo"])
        XCTAssertEqual(
            NativeWorkspaceBrowserOrdering.orderPromotingBlankSession("blank", in: promoted),
            promoted
        )
    }

    func testReconciledLocalOrderDropsStaleIDsAndAppendsNewHostIDs() {
        XCTAssertEqual(
            NativeWorkspaceBrowserOrdering.reconciledOrder(
                hostIDs: ["alpha", "bravo", "charlie"],
                storedOrder: ["stale", "charlie", "charlie", "alpha"]
            ),
            ["charlie", "alpha", "bravo"]
        )
    }
}
