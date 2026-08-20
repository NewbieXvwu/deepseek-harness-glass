import XCTest

@testable import GlassCore
@testable import GlassUI

@MainActor
final class NativeWorkspaceStoreTests: XCTestCase {
    func testRecentWorkspaceProjectionMatchesRC8ActivityCreationAndHostOrder() {
        let sessions = [
            SessionSummaryDTO(
                sessionId: "session-latest", updatedAt: 1_800_000_000_000, running: false, blank: false,
                pendingInteraction: nil, parentSessionId: nil, origin: nil, cwd: "/latest",
                agentPreset: nil, projections: nil
            ),
            SessionSummaryDTO(
                sessionId: "session-earlier", updatedAt: 1_700_000_000_000, running: false, blank: false,
                pendingInteraction: nil, parentSessionId: nil, origin: nil, cwd: "/earlier",
                agentPreset: nil, projections: nil
            ),
            SessionSummaryDTO(
                sessionId: "session-tied", updatedAt: 1_800_000_000_000, running: false, blank: false,
                pendingInteraction: nil, parentSessionId: nil, origin: nil, cwd: "/tied",
                agentPreset: nil, projections: nil
            ),
        ]
        let snapshot = NativeWorkspaceStore.Snapshot(
            workspaces: [
                WorkspaceSummaryDTO(workspaceId: "empty", path: "/empty", title: "empty", sessionIds: [], createdAt: "2020-01-01T00:00:00.000Z", updatedAt: "2020-01-01T00:00:00.000Z"),
                WorkspaceSummaryDTO(workspaceId: "latest", path: "/latest", title: "latest", sessionIds: ["session-latest"], createdAt: "2021-01-01T00:00:00.000Z", updatedAt: "2021-01-01T00:00:00.000Z"),
                WorkspaceSummaryDTO(workspaceId: "tied", path: "/tied", title: "tied", sessionIds: ["session-tied"], createdAt: "2024-01-01T00:00:00.000Z", updatedAt: "2024-01-01T00:00:00.000Z"),
                WorkspaceSummaryDTO(workspaceId: "earlier", path: "/earlier", title: "earlier", sessionIds: ["session-earlier"], createdAt: "2025-01-01T00:00:00.000Z", updatedAt: "2025-01-01T00:00:00.000Z"),
            ],
            sessions: sessions,
            archivedSessionIDs: [],
            selectedSessionID: nil,
            selectedWorkspaceID: nil
        )

        XCTAssertEqual(NativeWorkspaceStore.recentWorkspaceID(in: snapshot), "latest")

        let emptyOnly = NativeWorkspaceStore.Snapshot(
            workspaces: [
                WorkspaceSummaryDTO(workspaceId: "older", path: "/older", title: "older", sessionIds: [], createdAt: "2020-01-01T00:00:00.000Z", updatedAt: "2020-01-01T00:00:00.000Z"),
                WorkspaceSummaryDTO(workspaceId: "newer", path: "/newer", title: "newer", sessionIds: [], createdAt: "2021-01-01T00:00:00.000Z", updatedAt: "2021-01-01T00:00:00.000Z"),
            ],
            sessions: [],
            archivedSessionIDs: [],
            selectedSessionID: nil,
            selectedWorkspaceID: nil
        )
        XCTAssertEqual(NativeWorkspaceStore.recentWorkspaceID(in: emptyOnly), "newer")
    }

    func testSearchSanitizerMatchesRC8NULAndUTF16BoundaryContract() {
        XCTAssertEqual(
            NativeWorkspaceStore.sanitizeSearchQuery("before\u{0000}after"),
            "beforeafter"
        )

        let withinBoundary = String(repeating: "a", count: 500)
        XCTAssertEqual(NativeWorkspaceStore.sanitizeSearchQuery(withinBoundary), withinBoundary)

        // 499 BMP code units followed by a two-code-unit scalar crosses the
        // 500-unit wire edge. RC8 backs up one unit so a dangling high
        // surrogate never reaches the Host search request.
        let pairAtBoundary = String(repeating: "a", count: 499) + "😀" + "z"
        let sanitizedBoundary = NativeWorkspaceStore.sanitizeSearchQuery(pairAtBoundary)
        XCTAssertEqual(sanitizedBoundary, String(repeating: "a", count: 499))
        XCTAssertEqual(sanitizedBoundary.utf16.count, 499)

        let ordinaryOverflow = String(repeating: "b", count: 501)
        let sanitizedOverflow = NativeWorkspaceStore.sanitizeSearchQuery(ordinaryOverflow)
        XCTAssertEqual(sanitizedOverflow, String(repeating: "b", count: 500))
        XCTAssertEqual(sanitizedOverflow.utf16.count, 500)
    }
}
