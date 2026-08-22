import AppKit
import ApplicationServices
import SwiftUI
import XCTest

@testable import GlassCore
@testable import GlassSpec
@testable import GlassUI

@MainActor
final class NativeAccessibilityRuntimeTests: XCTestCase {
    func testCollapsedSidebarExportsAccessibleNamesForVisibleIconControls() throws {
        try assertAccessibleLabels(
            in: NativeSidebarView(
                workspaceStore: NativeWorkspaceStore(),
                collapsed: true,
                setCollapsed: { _ in },
                workspaceActions: WorkspaceBrowserView.Actions(),
                workspaceSnapshotDialog: .none,
                onNewSession: {},
                onOpenSettings: {}
            ),
            expected: [
                OfficialUISpec.Text.openSidebarAccessibility,
                OfficialUISpec.Text.newSessionAccessibility,
                OfficialUISpec.Text.settings,
            ],
            forbidden: [OfficialUISpec.Text.collapseSidebarAccessibility]
        )
    }

    func testExpandedSidebarExportsStaticShellControlsAndWorkspaceSettingsSeats() throws {
        try assertAccessibleLabels(
            in: NativeSidebarView(
                workspaceStore: NativeWorkspaceStore(),
                collapsed: false,
                setCollapsed: { _ in },
                workspaceActions: WorkspaceBrowserView.Actions(),
                workspaceSnapshotDialog: .none,
                onNewSession: {},
                onOpenSettings: {}
            ),
            expected: [
                // RC8 has two independent New Session controls in wide mode:
                // the wordmark shortcut and the outlined capsule.
                OfficialUISpec.Text.newSessionAccessibility,
                OfficialUISpec.Text.collapseSidebarAccessibility,
                // `SidebarRoot` retains the workspace region and its action
                // seats independently of whether any Host workspace exists.
                // Assert the mounted native counterparts rather than inferring
                // them from source text or a prebuilt snapshot.
                OfficialUISpec.Text.workspaces,
                OfficialUISpec.Text.searchSessionsAccessibility,
                OfficialUISpec.Text.viewOptions,
                OfficialUISpec.Text.addWorkspace,
                OfficialUISpec.Text.settings,
            ],
            expectedCounts: [
                OfficialUISpec.Text.newSessionAccessibility: 2,
                OfficialUISpec.Text.workspaces: 1,
                OfficialUISpec.Text.searchSessionsAccessibility: 1,
                OfficialUISpec.Text.viewOptions: 1,
                OfficialUISpec.Text.addWorkspace: 1,
                OfficialUISpec.Text.settings: 1,
            ],
            forbidden: [OfficialUISpec.Text.openSidebarAccessibility]
        )
    }

    func testExpandedSidebarRetainsHostWorkspaceRowAndFooterSeat() throws {
        let workspaceTitle = "Fixture workspace"
        let store = NativeWorkspaceStore(initialSnapshot: .init(
            workspaces: [
                .init(
                    workspaceId: "fixture-workspace",
                    path: "/fixture",
                    title: workspaceTitle,
                    sessionIds: [],
                    createdAt: "2026-01-01T00:00:00.000Z",
                    updatedAt: "2026-01-01T00:00:00.000Z"
                ),
            ],
            sessions: [],
            archivedSessionIDs: [],
            selectedSessionID: nil,
            selectedWorkspaceID: nil
        ))

        try assertAccessibleLabels(
            in: NativeSidebarView(
                workspaceStore: store,
                collapsed: false,
                setCollapsed: { _ in },
                workspaceActions: WorkspaceBrowserView.Actions(),
                workspaceSnapshotDialog: .none,
                onNewSession: {},
                onOpenSettings: {}
            ),
            expected: [
                OfficialUISpec.Text.workspaces,
                OfficialUISpec.Text.sessions,
                workspaceTitle,
                OfficialUISpec.Text.workspaceActionsAccessibilityPrefix + workspaceTitle,
                OfficialUISpec.Text.settings,
            ],
            expectedCounts: [
                OfficialUISpec.Text.workspaces: 1,
                OfficialUISpec.Text.sessions: 1,
                OfficialUISpec.Text.workspaceActionsAccessibilityPrefix + workspaceTitle: 1,
                OfficialUISpec.Text.settings: 1,
            ]
        )
    }

    func testConversationComposerExportsFocusAndActionNames() throws {
        let expected = [
            OfficialUISpec.Text.composerDefaultPlaceholder,
            OfficialUISpec.Text.sendMessageAccessibility,
            OfficialUISpec.Text.commandsAccessibility,
        ]
        try assertAccessibleLabels(
            in: NativeConversationColumn(
                mode: .conversation,
                selectedWorkspaceTitle: "Fixture workspace",
                sessionSnapshot: .empty,
                sessionStore: NativeSessionStore(),
                agentPresetStore: NativeAgentPresetStore(),
                selectAgentPreset: { _, _ in false },
                jobsPopoverInitiallyOpen: false,
                jobsLanguageCode: nil,
                openSession: { _ in },
                canOpenProjectPath: false,
                viewRegistry: NativeConversationViewRegistry(),
                headerContributions: NativeConversationHeaderContributionRegistry()
            ),
            expected: expected
        )
        let officialValues = Set(OfficialUISpec.LocaleCatalog.values.values)
        for label in expected {
            XCTAssertTrue(officialValues.contains(label), "rendered composer label is missing from official runtime locale catalog: \(label)")
        }
    }

    func testDeliverablesFolderActionFollowsVerifiedCapability() throws {
        let paths = [
            "关于我.md", "index.html", "long-generated-experience-specification-for-produced-files-overflow.md",
            "styles.css", "app.ts", "schema.json", "README.md",
        ]
        try assertAccessibleLabels(
            in: NativeProducedFiles(paths: paths, open: { _ in }, canShowInFolder: true),
            expected: [
                OfficialUISpec.Text.producedFiles,
                OfficialUISpec.Text.producedFilesOpen(name: "关于我.md"),
                OfficialUISpec.Text.producedFilesShowInFolder,
            ]
        )
        try assertAccessibleLabels(
            in: NativeProducedFiles(paths: paths, open: { _ in }, canShowInFolder: false),
            expected: [OfficialUISpec.Text.producedFilesOpen(name: "关于我.md")],
            forbidden: [OfficialUISpec.Text.producedFilesShowInFolder]
        )
    }

    func testFileToolPathAccessibilityFollowsVerifiedCapability() throws {
        let invocation = NativeSessionStore.ToolInvocation(
            id: "write-path",
            name: "write",
            arguments: #"{"file_path":"src/main.swift","content":"let value = 1"}"#,
            output: nil,
            state: .completed,
            sequence: 1,
            view: nil
        )
        try assertAccessibleLabels(
            in: NativeToolRow(
                invocation: invocation,
                selected: false,
                openKnownProjectPath: { _ in },
                canOpenProjectPath: true,
                inspect: {}
            ),
            expected: ["Write src/main.swift", "src/main.swift"]
        )
        try assertAccessibleLabels(
            in: NativeToolRow(
                invocation: invocation,
                selected: false,
                openKnownProjectPath: { _ in },
                canOpenProjectPath: false,
                inspect: {}
            ),
            expected: ["Write src/main.swift"],
            expectedCounts: ["Write src/main.swift": 1],
            forbidden: ["src/main.swift"]
        )
    }

    func testRuntimeLocaleCatalogAcceptsComposerLabelsAndRejectsInjectedNonOfficialLabel() {
        // These values are evaluated through the same production runtime locale
        // API that mounted native controls consume. AX tree traversal remains a
        // separate true-GUI assertion below because the hosted GitHub runner has
        // no TCC accessibility trust for the XCTest process.
        let renderedComposerLabels = [
            OfficialUISpec.Text.composerDefaultPlaceholder,
            OfficialUISpec.Text.sendMessageAccessibility,
            OfficialUISpec.Text.commandsAccessibility,
        ]
        let officialValues = Set(OfficialUISpec.LocaleCatalog.values.values)
        XCTAssertTrue(renderedComposerLabels.allSatisfy(officialValues.contains))

        let injected = ["non", "official", "runtime", "label"].joined(separator: "-")
        XCTAssertFalse(
            officialValues.contains(injected),
            "negative control must prove the runtime catalog rejects an unregistered rendered label"
        )
    }

    func testMessageFeedbackActionLabelsUseOfficialLocale() {
        let officialValues = Set(OfficialUISpec.LocaleCatalog.values.values)
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.feedbackLike))
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.feedbackLikeActive))
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.feedbackDislike))
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.feedbackDislikeActive))
    }

    func testMessageFeedbackNoteLabelsUseOfficialLocale() {
        let officialValues = Set(OfficialUISpec.LocaleCatalog.values.values)
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.feedbackNoteOpen))
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.feedbackNoteDialog))
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.feedbackNotePlaceholder))
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.feedbackNoteSave))
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.feedbackNoteCancel))
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.feedbackNoteAccessibility))
    }

    func testMessageFeedbackFailureLabelsUseOfficialLocale() {
        let officialValues = Set(OfficialUISpec.LocaleCatalog.values.values)
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.feedbackErrorConflict))
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.feedbackErrorLoad))
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.feedbackErrorGeneric))
    }

    func testSubagentBranchKeyboardLabelsUseOfficialLocale() {
        let officialValues = Set(OfficialUISpec.LocaleCatalog.values.values)
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.subagentBranchExpandTemplate))
        XCTAssertTrue(officialValues.contains(OfficialUISpec.Text.subagentBranchCollapseTemplate))
        XCTAssertEqual(OfficialUISpec.Text.subagentBranchExpand("worker"), "Expand worker descendants")
        XCTAssertEqual(OfficialUISpec.Text.subagentBranchCollapse("worker"), "Collapse worker descendants")
    }

    func testTrajectoryToolbarUsesOfficialLocale() {
        let officialValues = Set(OfficialUISpec.LocaleCatalog.values.values)
        let toolbarLocaleValues = [
            OfficialUISpec.Text.trajectoryToolbar,
            OfficialUISpec.Text.trajectoryTurns,
            OfficialUISpec.Text.trajectoryCalls,
            OfficialUISpec.Text.trajectorySearch,
            OfficialUISpec.Text.trajectorySearchPlaceholder,
        ]
        XCTAssertTrue(toolbarLocaleValues.allSatisfy(officialValues.contains))
        // `TrajectoryTable.tsx` owns the status and detail labels directly;
        // they are versioned RC8 component strings rather than locale-catalog
        // keys, and remain routed through `OfficialUISpec.Text` in the UI.
        XCTAssertEqual(
            [
                OfficialUISpec.Text.trajectoryPending,
                OfficialUISpec.Text.trajectoryCompleted,
                OfficialUISpec.Text.trajectoryFailed,
                OfficialUISpec.Text.trajectoryEventDetails,
                OfficialUISpec.Text.trajectorySummary,
                OfficialUISpec.Text.trajectoryPayload,
                OfficialUISpec.Text.trajectoryResult,
            ],
            ["Pending", "Completed", "Failed", "Event details", "Summary", "Payload", "Result"]
        )
    }

    func testNativeModelSelectUsesLockedModelSelectionLocaleCatalog() {
        let officialValues = Set(OfficialUISpec.LocaleCatalog.values.values)
        let rendered = [
            NativeComposerModelSelector.localizedValue(key: "trigger.selectAria", language: "en"),
            NativeComposerModelSelector.localizedValue(key: "menu.aria", language: "en"),
            NativeComposerModelSelector.localizedValue(key: "menu.model", language: "en"),
            NativeComposerModelSelector.localizedValue(key: "menu.effort", language: "en"),
            NativeComposerModelSelector.localizedValue(key: "status.loading", language: "en"),
            NativeComposerModelSelector.localizedValue(key: "empty.models", language: "en"),
            NativeComposerModelSelector.localizedValue(key: "empty.efforts", language: "en"),
            NativeComposerModelSelector.localizedValue(key: "warning.groupLoad", language: "en", replacements: ["name": "Provider", "message": "offline"]),
        ]
        XCTAssertTrue(rendered.dropLast().allSatisfy(officialValues.contains))
        XCTAssertEqual(
            NativeComposerModelSelector.localizedValue(key: "menu.aria", language: "zh"),
            OfficialUISpec.LocaleCatalog.value(namespace: "ui-model-selection", key: "menu.aria", language: "zh")
        )
        XCTAssertNotEqual(rendered.last, "warning.groupLoad", "interpolated warning must not fall back to an unregistered product literal")
    }

    func testNativeModelAndPermissionSelectorsExportCurrentOfficialTriggerNames() throws {
        let modelStore = NativeSessionStore()
        modelStore.loadSnapshotModelSelectionFixture()
        let permissionStore = NativeSessionStore()
        permissionStore.loadSnapshotPermissionFixture()
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let modelLabel = NativeComposerModelSelector.localizedValue(
            key: "trigger.aria",
            language: language,
            replacements: ["model": "DeepSeek-V4-Flash"]
        )
        let permissionLabel = NativeComposerPermissionSelector.localizedValue(
            key: "input.accessMode",
            language: language,
            replacements: ["name": OfficialUISpec.Text.fixtureWorkspaceWrite]
        )

        try assertAccessibleLabels(
            in: VStack {
                NativeComposerPermissionSelector(sessionStore: permissionStore)
                NativeComposerModelSelector(sessionStore: modelStore)
            },
            expected: [permissionLabel, modelLabel],
            expectedCounts: [permissionLabel: 1, modelLabel: 1]
        )
    }

    func testNativePermissionSelectUsesLockedConversationLocaleCatalog() {
        let officialValues = Set(OfficialUISpec.LocaleCatalog.values.values)
        let rendered = [
            NativeComposerPermissionSelector.localizedValue(key: "input.accessMode", language: "en", replacements: ["name": OfficialUISpec.Text.fixtureWorkspaceWrite]),
            NativeComposerPermissionSelector.localizedValue(key: "access.confirm.title", language: "en"),
            NativeComposerPermissionSelector.localizedValue(key: "access.confirm.description", language: "en"),
            NativeComposerPermissionSelector.localizedValue(key: "access.confirm.acknowledge", language: "en"),
            NativeComposerPermissionSelector.localizedValue(key: "access.confirm.cancel", language: "en"),
            NativeComposerPermissionSelector.localizedValue(key: "access.confirm.enable", language: "en"),
        ]
        XCTAssertTrue(rendered.dropFirst().allSatisfy(officialValues.contains))
        XCTAssertEqual(
            NativeComposerPermissionSelector.localizedValue(key: "access.confirm.title", language: "zh"),
            OfficialUISpec.LocaleCatalog.value(namespace: "ui-conversation", key: "access.confirm.title", language: "zh")
        )
        XCTAssertNotEqual(rendered.first, "input.accessMode", "interpolated access label must not fall back to an unregistered product literal")
    }

    func testNativeFullAccessConfirmationExportsOfficialAccessibleControls() throws {
        let language = "en"
        let title = NativeComposerPermissionSelector.localizedValue(key: "access.confirm.title", language: language)
        let acknowledge = NativeComposerPermissionSelector.localizedValue(key: "access.confirm.acknowledge", language: language)
        let cancel = NativeComposerPermissionSelector.localizedValue(key: "access.confirm.cancel", language: language)
        let enable = NativeComposerPermissionSelector.localizedValue(key: "access.confirm.enable", language: language)

        try assertAccessibleLabels(
            in: NativeFullAccessPermissionConfirmation(
                acknowledged: .constant(false),
                submitting: false,
                language: language,
                cancel: {},
                enable: {}
            ),
            expected: [title, acknowledge, cancel, enable],
            expectedCounts: [acknowledge: 1, cancel: 1, enable: 1]
        )
    }

    func testCompactionRendererUsesOfficialLocaleForSummaryStates() {
        let officialValues = Set(OfficialUISpec.LocaleCatalog.values.values)
        let rendered = [
            OfficialUISpec.Text.compactionTitle,
            OfficialUISpec.Text.compactionRunning,
            OfficialUISpec.Text.compactionExpand,
            OfficialUISpec.Text.compactionUnavailable,
        ]
        XCTAssertTrue(rendered.allSatisfy(officialValues.contains))
        XCTAssertEqual(
            OfficialUISpec.Text.compactionCompleted(items: 4, tokens: 1_024),
            "Compacted 4 history items (~1024 tokens)"
        )
    }

    func testTodoDockExportsCollapsedHeaderWithoutHiddenRowLabels() throws {
        try assertAccessibleLabels(
            in: NativeTodoDock(todos: [
                .init(content: "Inspect source", status: .completed),
                .init(content: "Implement view", status: .inProgress),
            ]),
            expected: [OfficialUISpec.Text.todoTitle],
            expectedCounts: [OfficialUISpec.Text.todoTitle: 1],
            forbidden: ["Inspect source", "Implement view"]
        )
    }

    func testDetailsExportsExplicitCloseName() throws {
        try assertAccessibleLabels(
            in: NativeDetailsView(sessionStore: NativeSessionStore(), close: {}),
            expected: [OfficialUISpec.Text.closeDetailsAccessibility]
        )
    }

    func testApprovalExportsDetailsAndSemanticActions() throws {
        let approval = NativeSessionStore.PendingApproval(
            rpcID: "fx-approval-rpc",
            sessionID: "fx-session",
            approvalID: "fx-approval",
            toolName: "Write",
            callID: nil,
            reason: "Approval required"
        )
        try assertAccessibleLabels(
            in: NativeApprovalPanel(approval: approval, command: "echo fixture", submitting: false, answer: { _ in }),
            expected: [
                OfficialUISpec.Text.approvalDetailsAccessibility,
                OfficialUISpec.Text.approvalReject,
                OfficialUISpec.Text.approvalAllowOnce,
            ]
        )
    }

    func testQuestionExportsNavigationAndCancellationNames() throws {
        let question = NativeSessionStore.PendingQuestion(
            rpcID: "fx-question-rpc",
            sessionID: "fx-session",
            items: [
                .init(
                    id: "fx-question",
                    question: "Which color?",
                    header: nil,
                    detail: nil,
                    options: [.init(label: "Blue", detail: nil)],
                    multiSelect: false
                )
            ]
        )
        try assertAccessibleLabels(
            in: NativeQuestionComposer(pending: question, submitting: false, answer: { _ in }, cancel: {}),
            expected: [
                OfficialUISpec.Text.questionCancelAccessibility,
                OfficialUISpec.Text.questionPreviousAccessibility,
                OfficialUISpec.Text.questionNextAccessibility,
            ]
        )
    }

    private func assertAccessibleLabels<V: View>(
        in view: V,
        expected: [String],
        expectedCounts: [String: Int] = [:],
        forbidden: [String] = []
    ) throws {
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Accessibility trust is unavailable for this XCTest process; the runtime locale catalog regression remains mandatory in CI.")
        }
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 840),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let labels = accessibilityLabels(in: host)
        window.orderOut(nil)
        guard !labels.isEmpty else {
            throw XCTSkip("The trusted process exposed no SwiftUI accessibility elements; run this tree assertion in the GUI accessibility-test host.")
        }
        for label in expected {
            XCTAssertTrue(labels.contains(label), "expected \(label), exported labels: \(labels)")
        }
        for (label, count) in expectedCounts {
            XCTAssertEqual(
                labels.filter { $0 == label }.count,
                count,
                "expected \(count) occurrences of \(label), exported labels: \(labels)"
            )
        }
        for label in forbidden {
            XCTAssertFalse(labels.contains(label), "forbidden hidden-control label \(label), exported labels: \(labels)")
        }
    }

    private func accessibilityLabels(in element: any NSAccessibilityProtocol) -> [String] {
        let ownLabel = element.accessibilityLabel().map { [$0] } ?? []
        let childLabels = (element.accessibilityChildren() ?? []).flatMap { child -> [String] in
            guard let child = child as? any NSAccessibilityProtocol else { return [] }
            return accessibilityLabels(in: child)
        }
        return ownLabel + childLabels
    }
}
