import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

@MainActor
final class NativeConversationHeaderTests: XCTestCase {
    func testUnknownRetainedViewResolvesToStableChatFallback() {
        XCTAssertEqual(NativeConversationViewRegistry.resolve(selectedID: nil)?.id, "chat")
        XCTAssertEqual(NativeConversationViewRegistry.resolve(selectedID: "removed-plugin-view")?.id, "chat")
        XCTAssertEqual(NativeConversationViewRegistry.resolve(selectedID: "chat")?.label, OfficialUISpec.Text.chat)
        XCTAssertEqual(NativeConversationViewRegistry.registeredTabs.count, 1)
    }

    func testJobsFixtureProvidesOfficialSessionTitleAndPresetProjection() throws {
        let store = NativeWorkspaceStore()
        store.loadSnapshotJobsFixtureWorkspace()

        let selected = try XCTUnwrap(store.snapshot.sessions.first { $0.sessionId == "fx-alpha" })
        XCTAssertEqual(selected.displayTitle, OfficialUISpec.Text.fixtureJobsSessionTitle)
        XCTAssertEqual(selected.agentPreset, "standard")
    }

    func testSubagentAncestryAndBlankHeaderVisibilityMirrorRC8Rules() {
        let root = summary(
            id: "root",
            title: "Parent session",
            blank: false,
            parent: nil,
            origin: nil,
            preset: "standard"
        )
        let child = summary(
            id: "child",
            title: "Subagent session",
            blank: true,
            parent: "root",
            origin: "subagent",
            preset: nil
        )
        let snapshot = NativeWorkspaceStore.Snapshot(
            workspaces: [],
            sessions: [root, child],
            archivedSessionIDs: [],
            selectedSessionID: "child",
            selectedWorkspaceID: nil
        )

        let blank = NativeSessionHeaderPresentation(
            snapshot: snapshot,
            sessionID: "child",
            composerIsBlank: true,
            selectedViewID: "removed-plugin-view"
        )
        XCTAssertEqual(blank.breadcrumbs.map(\.title), ["Parent session", "Subagent session"])
        XCTAssertEqual(blank.agentPreset, nil)
        XCTAssertTrue(blank.hidesChrome)
        XCTAssertEqual(blank.activeTab?.id, NativeConversationViewRegistry.chatID)

        let drafted = NativeSessionHeaderPresentation(
            snapshot: snapshot,
            sessionID: "child",
            composerIsBlank: false,
            selectedViewID: nil
        )
        XCTAssertFalse(drafted.hidesChrome)
    }

    private func summary(
        id: String,
        title: String,
        blank: Bool,
        parent: String?,
        origin: String?,
        preset: String?
    ) -> SessionSummaryDTO {
        SessionSummaryDTO(
            sessionId: id,
            updatedAt: 0,
            running: false,
            blank: blank,
            pendingInteraction: nil,
            parentSessionId: parent,
            origin: origin,
            cwd: nil,
            agentPreset: preset,
            projections: SessionProjectionsDTO(asOfSeq: 0, values: ["title": .string(title)])
        )
    }
}
