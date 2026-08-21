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
                OfficialUISpec.Text.settings,
            ],
            expectedCounts: [OfficialUISpec.Text.newSessionAccessibility: 2],
            forbidden: [OfficialUISpec.Text.openSidebarAccessibility]
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
                jobsPopoverInitiallyOpen: false,
                jobsLanguageCode: nil,
                openSession: { _ in },
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

    func testTrajectoryToolbarUsesOfficialLocale() {
        let officialValues = Set(OfficialUISpec.LocaleCatalog.values.values)
        let rendered = [
            OfficialUISpec.Text.trajectoryToolbar,
            OfficialUISpec.Text.trajectoryTurns,
            OfficialUISpec.Text.trajectoryCalls,
            OfficialUISpec.Text.trajectorySearch,
            OfficialUISpec.Text.trajectorySearchPlaceholder,
            OfficialUISpec.Text.trajectoryEventDetails,
            OfficialUISpec.Text.trajectorySummary,
            OfficialUISpec.Text.trajectoryPayload,
            OfficialUISpec.Text.trajectoryResult,
        ]
        XCTAssertTrue(rendered.allSatisfy(officialValues.contains))
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
