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
            ]
        )
    }

    func testConversationComposerExportsFocusAndActionNames() throws {
        try assertAccessibleLabels(
            in: NativeConversationColumn(
                mode: .conversation,
                selectedWorkspaceTitle: "Fixture workspace",
                sessionStore: NativeSessionStore(),
                jobsPopoverInitiallyOpen: false
            ),
            expected: [
                OfficialUISpec.Text.composerDefaultPlaceholder,
                OfficialUISpec.Text.sendMessageAccessibility,
                OfficialUISpec.Text.commandsAccessibility,
            ]
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

    private func assertAccessibleLabels<V: View>(in view: V, expected: [String]) throws {
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Accessibility trust is required to read the window's accessibility tree.")
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
            throw XCTSkip("The headless macOS runner exposes no SwiftUI accessibility elements despite AX trust; run this tree assertion in a GUI accessibility-test host. The static locked core-path gate remains mandatory in CI.")
        }
        for label in expected {
            XCTAssertTrue(labels.contains(label), "expected \(label), exported labels: \(labels)")
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
