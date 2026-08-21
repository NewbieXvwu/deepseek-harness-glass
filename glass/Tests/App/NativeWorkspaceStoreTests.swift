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

    func testBrowserVisibilityMatchesRC8OrdinaryBlankSubagentArchivedAndUngroupedRules() {
        func session(
            _ id: String,
            blank: Bool = false,
            origin: String? = nil
        ) -> SessionSummaryDTO {
            .init(
                sessionId: id,
                updatedAt: 1,
                running: false,
                blank: blank,
                pendingInteraction: nil,
                parentSessionId: origin == "subagent" ? "parent" : nil,
                origin: origin,
                cwd: "/fixture",
                agentPreset: nil,
                projections: nil
            )
        }

        let ordinary = session("ordinary")
        let selectedBlank = session("selected-blank", blank: true)
        let unselectedBlank = session("unselected-blank", blank: true)
        let subagent = session("subagent-child", origin: "subagent")
        let archived = session("archived")
        let ungrouped = session("ungrouped")
        let snapshot = NativeWorkspaceStore.Snapshot(
            workspaces: [
                .init(
                    workspaceId: "fixture-workspace",
                    path: "/fixture",
                    title: "Fixture",
                    sessionIds: [ordinary.sessionId, selectedBlank.sessionId, unselectedBlank.sessionId, subagent.sessionId, archived.sessionId],
                    createdAt: "2026-01-01T00:00:00.000Z",
                    updatedAt: "2026-01-01T00:00:00.000Z"
                ),
            ],
            sessions: [ordinary, selectedBlank, unselectedBlank, subagent, archived, ungrouped],
            archivedSessionIDs: [archived.sessionId],
            selectedSessionID: selectedBlank.sessionId,
            selectedWorkspaceID: "fixture-workspace"
        )

        XCTAssertEqual(snapshot.visibleSessions.map(\.sessionId), [ordinary.sessionId, selectedBlank.sessionId, ungrouped.sessionId])
        XCTAssertEqual(snapshot.sessions(in: snapshot.workspaces[0]).map(\.sessionId), [ordinary.sessionId, selectedBlank.sessionId])
        XCTAssertEqual(snapshot.ungroupedSessions.map(\.sessionId), [ungrouped.sessionId])
    }

    func testBlankSessionReuseRequiresWorkspaceMembershipCanonicalCWDAndNonArchivedState() {
        let reusable = SessionSummaryDTO(
            sessionId: "reusable", updatedAt: 1, running: false, blank: true,
            pendingInteraction: nil, parentSessionId: nil, origin: nil, cwd: "/workspace-a",
            agentPreset: nil, projections: nil
        )
        let archived = SessionSummaryDTO(
            sessionId: "archived", updatedAt: 2, running: false, blank: true,
            pendingInteraction: nil, parentSessionId: nil, origin: nil, cwd: "/workspace-a",
            agentPreset: nil, projections: nil
        )
        let wrongCWD = SessionSummaryDTO(
            sessionId: "wrong-cwd", updatedAt: 3, running: false, blank: true,
            pendingInteraction: nil, parentSessionId: nil, origin: nil, cwd: "/elsewhere",
            agentPreset: nil, projections: nil
        )
        let unaccounted = SessionSummaryDTO(
            sessionId: "unaccounted", updatedAt: 4, running: false, blank: true,
            pendingInteraction: nil, parentSessionId: nil, origin: nil, cwd: "/workspace-a",
            agentPreset: nil, projections: nil
        )
        let snapshot = NativeWorkspaceStore.Snapshot(
            workspaces: [
                WorkspaceSummaryDTO(
                    workspaceId: "workspace-a", path: "/workspace-a", title: "A",
                    sessionIds: ["archived", "wrong-cwd", "reusable"],
                    createdAt: "2026-01-01T00:00:00.000Z", updatedAt: "2026-01-01T00:00:00.000Z"
                ),
            ],
            sessions: [archived, wrongCWD, unaccounted, reusable],
            archivedSessionIDs: ["archived"],
            selectedSessionID: nil,
            selectedWorkspaceID: nil
        )

        XCTAssertEqual(
            NativeWorkspaceBlankSessionReuse.reusableSessionID(workspaceID: "workspace-a", in: snapshot),
            "reusable"
        )
        XCTAssertNil(NativeWorkspaceBlankSessionReuse.reusableSessionID(workspaceID: "missing", in: snapshot))

        let allCandidatesArchived = NativeWorkspaceStore.Snapshot(
            workspaces: snapshot.workspaces,
            sessions: snapshot.sessions,
            archivedSessionIDs: ["archived", "reusable"],
            selectedSessionID: nil,
            selectedWorkspaceID: nil
        )
        XCTAssertNil(
            NativeWorkspaceBlankSessionReuse.reusableSessionID(workspaceID: "workspace-a", in: allCandidatesArchived)
        )
    }

    func testRailSearchArmsWideInputAndFocusesOnlyAfterExpansionSettles() {
        let armed = NativeWorkspaceBrowserSearchOnExpand.armedState()
        XCTAssertEqual(armed, .init(searchExpanded: true, awaitsWideFocus: true))
        XCTAssertFalse(NativeWorkspaceBrowserSearchOnExpand.shouldFocus(
            collapsed: true,
            awaitsWideFocus: armed.awaitsWideFocus
        ))
        XCTAssertTrue(NativeWorkspaceBrowserSearchOnExpand.shouldFocus(
            collapsed: false,
            awaitsWideFocus: armed.awaitsWideFocus
        ))
        XCTAssertEqual(
            NativeWorkspaceBrowserSearchOnExpand.settledState(searchExpanded: armed.searchExpanded),
            .init(searchExpanded: true, awaitsWideFocus: false)
        )
        XCTAssertEqual(
            NativeWorkspaceBrowserSearchOnExpand.dismissedState(),
            .init(searchExpanded: false, awaitsWideFocus: false)
        )
    }

    func testSearchWithoutVerifiedHostDoesNotInventPrivateResults() {
        let store = NativeWorkspaceStore()
        store.searchQuery = "host-authoritative"

        store.search(query: store.searchQuery, using: nil)

        XCTAssertEqual(store.remoteSearch.query, "host-authoritative")
        XCTAssertEqual(store.remoteSearch.status, .failed)
        XCTAssertTrue(store.remoteSearch.items.isEmpty)
        XCTAssertFalse(store.remoteSearch.hasMore)
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
