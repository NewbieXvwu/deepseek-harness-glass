import SwiftUI
import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

@MainActor
final class NativeConversationHeaderTests: XCTestCase {
    func testUnknownRetainedViewResolvesToStableChatFallback() {
        let registry = NativeConversationViewRegistry()
        XCTAssertEqual(registry.resolve(selectedID: nil)?.id, "chat")
        XCTAssertEqual(registry.resolve(selectedID: "removed-plugin-view")?.id, "chat")
        XCTAssertEqual(registry.resolve(selectedID: "chat")?.label, OfficialUISpec.Text.chat)
        XCTAssertEqual(registry.registeredTabs.count, 1)
    }

    func testViewRegistryOrdersLabelsRejectsDuplicatesAndDisposesSafely() throws {
        let registry = NativeConversationViewRegistry()
        let late = try registry.register(id: "z-late", order: 20, label: "Late") { _ in AnyView(EmptyView()) }
        let early = try registry.register(id: "early", order: -1, label: "Early") { _ in AnyView(EmptyView()) }
        let bare = try registry.register(id: "bare", order: 10) { _ in AnyView(EmptyView()) }

        XCTAssertEqual(registry.registeredTabs.map(\.id), ["early", "chat", "bare", "z-late"])
        XCTAssertEqual(registry.registeredTabs.map(\.label), ["Early", OfficialUISpec.Text.chat, "bare", "Late"])
        XCTAssertThrowsError(try registry.register(id: "early", order: 30) { _ in AnyView(EmptyView()) }) { error in
            XCTAssertEqual(error as? NativeConversationContributionRegistryError, .duplicateViewID("early"))
        }

        registry.unregister(early)
        XCTAssertEqual(registry.resolve(selectedID: "early")?.id, NativeConversationViewRegistry.chatID)
        XCTAssertEqual(registry.registeredTabs.map(\.id), ["chat", "bare", "z-late"])
        registry.unregister(early) // A stale disposer cannot remove another entry.
        XCTAssertEqual(registry.registeredTabs.map(\.id), ["chat", "bare", "z-late"])
        registry.unregister(bare)
        registry.unregister(late)
        XCTAssertEqual(registry.registeredTabs.map(\.id), ["chat"])
    }

    func testShellRegistersNativeTrajectoryTabWithTypedRenderer() {
        let sessionStore = NativeSessionStore()
        sessionStore.loadSnapshotToolingFixture()
        let presentation = NativeShellPresentation(mode: .conversation, sessionStore: sessionStore)
        let context = NativeConversationContributionContext(
            sessionID: sessionStore.selectedSessionID,
            sessionSnapshot: .empty,
            sessionStore: sessionStore
        )

        XCTAssertEqual(
            presentation.conversationViewRegistry.registeredTabs.map(\.id),
            [NativeConversationViewRegistry.chatID, "trajectory"]
        )
        XCTAssertEqual(
            presentation.conversationViewRegistry.registeredTabs.map(\.label),
            [OfficialUISpec.Text.chat, OfficialUISpec.Text.trajectory]
        )
        XCTAssertEqual(presentation.conversationViewRegistry.resolve(selectedID: "trajectory")?.id, "trajectory")
        XCTAssertNotNil(presentation.conversationViewRegistry.render(selectedID: "trajectory", context: context))
    }

    func testWorkflowNavigationAndDisclosureFailClosedToTypedRunningChildren() {
        let running = CoreWorkflowRunNode.Member(seq: 1, label: "Active child", phase: "Plan", childID: "child-running", status: .running)
        let finished = CoreWorkflowRunNode.Member(seq: 2, label: "Finished child", phase: "Plan", childID: "child-finished", status: .completed)
        let malformed = CoreWorkflowRunNode.Member(seq: 3, label: "Missing id", phase: "Review", childID: "", status: .running)
        let workflow = CoreWorkflowRunNode(
            name: "Workflow",
            status: .running,
            phases: [
                .init(key: "plan", phase: "Plan", members: [running, finished]),
                .init(key: "review", phase: "Review", members: [malformed]),
            ]
        )

        XCTAssertTrue(NativeWorkflowRunPresentation.isNavigable(running))
        XCTAssertFalse(NativeWorkflowRunPresentation.isNavigable(finished))
        XCTAssertFalse(NativeWorkflowRunPresentation.isNavigable(malformed))
        XCTAssertEqual(NativeWorkflowRunPresentation.runningPhaseKeys(workflow), ["plan", "review"])
        XCTAssertEqual(OfficialUISpec.Text.workflowMemberCount(2), "2 members")
    }

    func testWorkflowDisclosureDefersCleanCollapseUntilFocusLeavesContent() {
        let running = NativeWorkflowRunPresentation.DisclosureFacts(mode: .running, activityCount: 1)
        let clean = NativeWorkflowRunPresentation.DisclosureFacts(mode: .clean, activityCount: 1)
        let active = NativeWorkflowRunPresentation.initialDisclosureState(running)

        let pending = NativeWorkflowRunPresentation.advanceDisclosureState(
            active,
            facts: clean,
            focusWithin: true
        )
        XCTAssertTrue(pending.open)
        XCTAssertTrue(pending.pendingCleanCollapse)

        let settled = NativeWorkflowRunPresentation.advanceDisclosureState(
            pending,
            facts: clean,
            focusWithin: false
        )
        XCTAssertFalse(settled.open)
        XCTAssertFalse(settled.pendingCleanCollapse)
    }

    func testWorkflowDisclosureReopensNewActivityAndAbnormalEscalation() {
        let clean = NativeWorkflowRunPresentation.DisclosureFacts(mode: .clean, activityCount: 0)
        let running = NativeWorkflowRunPresentation.DisclosureFacts(mode: .running, activityCount: 1)
        let abnormal = NativeWorkflowRunPresentation.DisclosureFacts(mode: .abnormal, activityCount: 1)
        let closed = NativeWorkflowRunPresentation.initialDisclosureState(clean)

        let active = NativeWorkflowRunPresentation.advanceDisclosureState(
            closed,
            facts: running,
            focusWithin: false
        )
        XCTAssertTrue(active.open)

        let userClosedRunning = NativeWorkflowRunPresentation.DisclosureState(
            mode: .running,
            activityCount: 1,
            open: false,
            pendingCleanCollapse: false
        )
        let escalated = NativeWorkflowRunPresentation.advanceDisclosureState(
            userClosedRunning,
            facts: abnormal,
            focusWithin: false
        )
        XCTAssertTrue(escalated.open)
        XCTAssertFalse(escalated.pendingCleanCollapse)
    }

    func testHeaderContributionSlotsRemainSeparateAndDisposeByNonce() throws {
        let registry = NativeConversationHeaderContributionRegistry()
        let action = try registry.register(slot: .actions, id: "action", order: 1) { _ in AnyView(EmptyView()) }
        let utility = try registry.register(slot: .utilities, id: "utility", order: 0) { _ in AnyView(EmptyView()) }
        let context = NativeConversationContributionContext(
            sessionID: nil,
            sessionSnapshot: .init(workspaces: [], sessions: [], archivedSessionIDs: [], selectedSessionID: nil, selectedWorkspaceID: nil),
            sessionStore: NativeSessionStore()
        )

        XCTAssertEqual(registry.render(slot: .actions, context: context).count, 1)
        XCTAssertEqual(registry.render(slot: .utilities, context: context).count, 1)
        XCTAssertThrowsError(try registry.register(slot: .actions, id: "action", order: 2) { _ in AnyView(EmptyView()) }) { error in
            XCTAssertEqual(error as? NativeConversationContributionRegistryError, .duplicateHeaderContribution(slot: .actions, id: "action"))
        }
        registry.unregister(action)
        XCTAssertTrue(registry.render(slot: .actions, context: context).isEmpty)
        XCTAssertEqual(registry.render(slot: .utilities, context: context).count, 1)
        registry.unregister(utility)
        XCTAssertTrue(registry.render(slot: .utilities, context: context).isEmpty)
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
            selectedViewID: "removed-plugin-view",
            viewRegistry: NativeConversationViewRegistry()
        )
        XCTAssertEqual(blank.breadcrumbs.map(\.title), ["Parent session", "Subagent session"])
        XCTAssertEqual(blank.agentPreset, nil)
        XCTAssertTrue(blank.hidesChrome)
        XCTAssertEqual(blank.activeTab?.id, NativeConversationViewRegistry.chatID)

        let drafted = NativeSessionHeaderPresentation(
            snapshot: snapshot,
            sessionID: "child",
            composerIsBlank: false,
            selectedViewID: nil,
            viewRegistry: NativeConversationViewRegistry()
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
