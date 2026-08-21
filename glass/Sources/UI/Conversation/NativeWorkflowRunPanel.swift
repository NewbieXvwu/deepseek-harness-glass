import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Pure RC8 presentation rules shared by the native workflow renderer and
/// regressions. A member never gains navigation from its label or a summary.
enum NativeWorkflowRunPresentation {
    enum DisclosureMode: Equatable {
        case clean
        case running
        case abnormal
    }

    struct DisclosureFacts: Equatable {
        let mode: DisclosureMode
        let activityCount: Int
    }

    struct DisclosureState: Equatable {
        let mode: DisclosureMode
        let activityCount: Int
        let open: Bool
        let pendingCleanCollapse: Bool
    }

    static func isNavigable(_ member: CoreWorkflowRunNode.Member) -> Bool {
        member.status == .running && !member.childID.isEmpty
    }

    static func runningPhaseKeys(_ workflow: CoreWorkflowRunNode) -> Set<String> {
        Set(workflow.phases.compactMap { phase in
            phase.members.contains(where: { $0.status == .running }) ? phase.key : nil
        })
    }

    /// Source: RC8 `phaseDisclosureFacts`; failed/cancelled/interrupted outrank
    /// running and all other phase states settle cleanly.
    static func phaseFacts(_ phase: CoreWorkflowRunNode.Phase) -> DisclosureFacts {
        let statuses = phase.members.map(\.status)
        let mode: DisclosureMode
        if statuses.contains(where: isAbnormal) {
            mode = .abnormal
        } else if statuses.contains(.running) {
            mode = .running
        } else {
            mode = .clean
        }
        return .init(mode: mode, activityCount: phase.members.count)
    }

    /// Source: RC8 `runDisclosureFacts`; status or phase abnormality outranks
    /// running, and the activity count is the typed phase-member total.
    static func runFacts(_ workflow: CoreWorkflowRunNode) -> DisclosureFacts {
        let phases = workflow.phases.map(phaseFacts)
        let mode: DisclosureMode
        if isAbnormal(workflow.status) || phases.contains(where: { $0.mode == .abnormal }) {
            mode = .abnormal
        } else if workflow.status == .running || phases.contains(where: { $0.mode == .running }) {
            mode = .running
        } else {
            mode = .clean
        }
        return .init(mode: mode, activityCount: phases.reduce(0) { $0 + $1.activityCount })
    }

    /// RC8 initializes clean disclosures closed and active/abnormal work open.
    static func initialDisclosureState(_ facts: DisclosureFacts) -> DisclosureState {
        .init(
            mode: facts.mode,
            activityCount: facts.activityCount,
            open: facts.mode != .clean,
            pendingCleanCollapse: false
        )
    }

    /// RC8 `advanceDisclosureState`. A disclosure that settles clean while its
    /// contents retain focus remains open until the focus boundary is exited.
    static func advanceDisclosureState(
        _ current: DisclosureState,
        facts: DisclosureFacts,
        focusWithin: Bool
    ) -> DisclosureState {
        let sameFacts = current.mode == facts.mode && current.activityCount == facts.activityCount
        if sameFacts {
            guard current.pendingCleanCollapse, !focusWithin else { return current }
            return .init(mode: current.mode, activityCount: current.activityCount, open: false, pendingCleanCollapse: false)
        }
        if facts.mode == .clean {
            let deferCollapse = current.open && focusWithin
            return .init(mode: facts.mode, activityCount: facts.activityCount, open: deferCollapse, pendingCleanCollapse: deferCollapse)
        }
        if current.mode == .clean || (facts.mode == .abnormal && current.mode != .abnormal) {
            return .init(mode: facts.mode, activityCount: facts.activityCount, open: true, pendingCleanCollapse: false)
        }
        return .init(mode: facts.mode, activityCount: facts.activityCount, open: current.open, pendingCleanCollapse: false)
    }

    static func collapsePending(_ state: DisclosureState) -> DisclosureState {
        guard state.pendingCleanCollapse else { return state }
        return .init(mode: state.mode, activityCount: state.activityCount, open: false, pendingCleanCollapse: false)
    }

    private static func isAbnormal(_ status: CoreWorkflowRunNode.Status) -> Bool {
        status == .failed || status == .cancelled || status == .interrupted
    }
}

/// Native RC8 `workflow-run` chat renderer. It retains only typed run/phase
/// facts. Member navigation is a shell-owned intent and is offered only for a
/// live member explicitly projected by the durable workflow run.
struct NativeWorkflowRunPanel: View {
    let workflow: CoreWorkflowRunNode
    let openSession: (String) -> Void
    @State private var runDisclosure: NativeWorkflowRunPresentation.DisclosureState?
    @State private var phaseDisclosures: [String: NativeWorkflowRunPresentation.DisclosureState] = [:]
    @FocusState private var focusedWorkflowMemberID: String?

    private var memberCount: Int {
        workflow.phases.reduce(0) { $0 + $1.members.count }
    }

    private var runExpanded: Bool {
        (runDisclosure ?? NativeWorkflowRunPresentation.initialDisclosureState(NativeWorkflowRunPresentation.runFacts(workflow))).open
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            Button { toggleRun() } label: {
                HStack(spacing: OfficialUISpec.Spacing.p8) {
                    Image(systemName: runExpanded ? "chevron.down" : "chevron.right")
                        .font(OfficialUISpec.Typography.xxxs11)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                    Circle().fill(color(for: workflow.status)).frame(width: OfficialUISpec.Geometry.px8, height: OfficialUISpec.Geometry.px8)
                    Text(workflow.name.isEmpty ? OfficialUISpec.Text.workflowEmptyMember : workflow.name)
                        .font(OfficialUISpec.Typography.xsStrong13)
                        .foregroundStyle(OfficialUISpec.Token.primary)
                    if !runExpanded {
                        Rectangle().fill(OfficialUISpec.Token.hairline).frame(width: OfficialUISpec.Geometry.px1, height: OfficialUISpec.Geometry.px14)
                        Text(OfficialUISpec.Text.workflowMemberCount(memberCount))
                            .font(OfficialUISpec.Typography.xs13)
                            .foregroundStyle(OfficialUISpec.Token.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(label(for: workflow.status))
                        .font(OfficialUISpec.Typography.xs13)
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(workflow.name.isEmpty ? OfficialUISpec.Text.workflowEmptyMember : workflow.name)

            if runExpanded {
                if workflow.phases.isEmpty {
                    Text(OfficialUISpec.Text.workflowNoMembers)
                        .font(OfficialUISpec.Typography.xs13)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                } else {
                    ForEach(workflow.phases, id: \.key) { phase in
                        phaseDisclosure(phase)
                    }
                }
            }
        }
        .padding(OfficialUISpec.Spacing.p12)
        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous).stroke(OfficialUISpec.Token.hairline, lineWidth: OfficialUISpec.Geometry.px1) }
        .onAppear { synchronizeDisclosures() }
        .onChange(of: workflow) { _, _ in synchronizeDisclosures() }
        .onChange(of: focusedWorkflowMemberID) { _, _ in settlePendingDisclosures() }
    }

    @ViewBuilder
    private func phaseDisclosure(_ phase: CoreWorkflowRunNode.Phase) -> some View {
        let disclosure = phaseDisclosureState(for: phase)
        let expanded = disclosure.open
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
            Button {
                togglePhase(phase.key)
            } label: {
                HStack(spacing: OfficialUISpec.Spacing.p8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(OfficialUISpec.Typography.xxxs11)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                    Text(phaseTitle(phase))
                        .font(OfficialUISpec.Typography.xsStrong13)
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                    if !expanded {
                        Rectangle().fill(OfficialUISpec.Token.hairline).frame(width: OfficialUISpec.Geometry.px1, height: OfficialUISpec.Geometry.px14)
                        Text(OfficialUISpec.Text.workflowMemberCount(phase.members.count))
                            .font(OfficialUISpec.Typography.xs13)
                            .foregroundStyle(OfficialUISpec.Token.caption)
                    }
                    Spacer(minLength: 0)
                    Text(phaseStatus(phase))
                        .font(OfficialUISpec.Typography.xs13)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(phase.members, id: \.seq) { member in
                    memberRow(member, phaseKey: phase.key)
                }
            }
        }
    }

    @ViewBuilder
    private func memberRow(_ member: CoreWorkflowRunNode.Member, phaseKey: String) -> some View {
        if NativeWorkflowRunPresentation.isNavigable(member) {
            Button {
                openSession(member.childID)
            } label: {
                memberContent(member)
            }
            .buttonStyle(.plain)
            .focused($focusedWorkflowMemberID, equals: focusKey(phaseKey: phaseKey, member: member))
            .accessibilityLabel(member.label.isEmpty ? OfficialUISpec.Text.workflowEmptyMember : member.label)
        } else {
            memberContent(member)
        }
    }

    private func memberContent(_ member: CoreWorkflowRunNode.Member) -> some View {
        HStack(spacing: OfficialUISpec.Spacing.p8) {
            Circle().fill(color(for: member.status)).frame(width: OfficialUISpec.Geometry.px6, height: OfficialUISpec.Geometry.px6)
            Text(member.label.isEmpty ? OfficialUISpec.Text.workflowEmptyMember : member.label)
                .font(OfficialUISpec.Typography.xs13)
                .foregroundStyle(OfficialUISpec.Token.primary)
            Spacer(minLength: 0)
            Text(label(for: member.status))
                .font(OfficialUISpec.Typography.xs13)
                .foregroundStyle(OfficialUISpec.Token.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, OfficialUISpec.Spacing.p16)
        .padding(.vertical, OfficialUISpec.Spacing.p2)
    }

    private func toggleRun() {
        let current = runDisclosure ?? NativeWorkflowRunPresentation.initialDisclosureState(NativeWorkflowRunPresentation.runFacts(workflow))
        runDisclosure = .init(
            mode: current.mode,
            activityCount: current.activityCount,
            open: !current.open,
            pendingCleanCollapse: false
        )
    }

    private func togglePhase(_ key: String) {
        guard let phase = workflow.phases.first(where: { $0.key == key }) else { return }
        let current = phaseDisclosureState(for: phase)
        phaseDisclosures[key] = .init(
            mode: current.mode,
            activityCount: current.activityCount,
            open: !current.open,
            pendingCleanCollapse: false
        )
    }

    /// RC8 `useLayoutEffect` equivalent. Any transition into clean state defers
    /// collapse while a focusable live child remains inside its content.
    private func synchronizeDisclosures() {
        let currentRun = runDisclosure ?? NativeWorkflowRunPresentation.initialDisclosureState(NativeWorkflowRunPresentation.runFacts(workflow))
        var nextPhases: [String: NativeWorkflowRunPresentation.DisclosureState] = [:]
        var phaseStartedCycle = false
        for phase in workflow.phases {
            let facts = NativeWorkflowRunPresentation.phaseFacts(phase)
            let previous = phaseDisclosures[phase.key] ?? NativeWorkflowRunPresentation.initialDisclosureState(facts)
            let next = NativeWorkflowRunPresentation.advanceDisclosureState(
                previous,
                facts: facts,
                focusWithin: focusIsWithin(phaseKey: phase.key)
            )
            nextPhases[phase.key] = next
            if previous.mode == .clean, facts.mode != .clean || previous.activityCount != facts.activityCount {
                phaseStartedCycle = true
            }
        }
        let runFacts = NativeWorkflowRunPresentation.runFacts(workflow)
        let advancedRun = NativeWorkflowRunPresentation.advanceDisclosureState(
            currentRun,
            facts: runFacts,
            focusWithin: focusedWorkflowMemberID != nil
        )
        runDisclosure = phaseStartedCycle && runFacts.mode != .clean && !advancedRun.open
            ? .init(mode: advancedRun.mode, activityCount: advancedRun.activityCount, open: true, pendingCleanCollapse: false)
            : advancedRun
        phaseDisclosures = nextPhases
    }

    private func settlePendingDisclosures() {
        if focusedWorkflowMemberID == nil, let runDisclosure {
            self.runDisclosure = NativeWorkflowRunPresentation.collapsePending(runDisclosure)
        }
        for (key, state) in phaseDisclosures where !focusIsWithin(phaseKey: key) {
            phaseDisclosures[key] = NativeWorkflowRunPresentation.collapsePending(state)
        }
    }

    private func phaseDisclosureState(for phase: CoreWorkflowRunNode.Phase) -> NativeWorkflowRunPresentation.DisclosureState {
        phaseDisclosures[phase.key] ?? NativeWorkflowRunPresentation.initialDisclosureState(
            NativeWorkflowRunPresentation.phaseFacts(phase)
        )
    }

    private func focusIsWithin(phaseKey: String) -> Bool {
        focusedWorkflowMemberID?.hasPrefix("\(phaseKey)\u{001F}") == true
    }

    private func focusKey(phaseKey: String, member: CoreWorkflowRunNode.Member) -> String {
        "\(phaseKey)\u{001F}\(member.seq)"
    }

    private func phaseTitle(_ phase: CoreWorkflowRunNode.Phase) -> String {
        phase.phase == nil ? OfficialUISpec.Text.workflowUnphased : (phase.phase?.isEmpty == true ? OfficialUISpec.Text.workflowEmptyPhase : phase.phase!)
    }

    private func phaseStatus(_ phase: CoreWorkflowRunNode.Phase) -> String {
        if phase.members.contains(where: { $0.status == .running }) { return OfficialUISpec.Text.workflowRunning }
        return label(for: phase.members.last?.status ?? workflow.status)
    }

    private func label(for status: CoreWorkflowRunNode.Status) -> String {
        switch status {
        case .running: OfficialUISpec.Text.workflowRunning
        case .completed: OfficialUISpec.Text.workflowCompleted
        case .failed: OfficialUISpec.Text.workflowFailed
        case .cancelled: OfficialUISpec.Text.workflowCancelled
        case .interrupted: OfficialUISpec.Text.workflowInterrupted
        }
    }

    private func color(for status: CoreWorkflowRunNode.Status) -> Color {
        switch status {
        case .running: OfficialUISpec.Token.businessBlue
        case .completed: OfficialUISpec.Token.success
        case .failed: OfficialUISpec.Token.errorPrimary
        case .cancelled, .interrupted: OfficialUISpec.Token.warningPrimary
        }
    }
}
