import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Pure RC8 presentation rules shared by the native workflow renderer and
/// regressions. A member never gains navigation from its label or a summary.
enum NativeWorkflowRunPresentation {
    static func isNavigable(_ member: CoreWorkflowRunNode.Member) -> Bool {
        member.status == .running && !member.childID.isEmpty
    }

    static func runningPhaseKeys(_ workflow: CoreWorkflowRunNode) -> Set<String> {
        Set(workflow.phases.compactMap { phase in
            phase.members.contains(where: { $0.status == .running }) ? phase.key : nil
        })
    }
}

/// Native RC8 `workflow-run` chat renderer. It retains only typed run/phase
/// facts. Member navigation is a shell-owned intent and is offered only for a
/// live member explicitly projected by the durable workflow run.
struct NativeWorkflowRunPanel: View {
    let workflow: CoreWorkflowRunNode
    let openSession: (String) -> Void
    @State private var runExpanded = true
    @State private var expandedPhaseKeys: Set<String> = []

    private var memberCount: Int {
        workflow.phases.reduce(0) { $0 + $1.members.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            Button { runExpanded.toggle() } label: {
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
        .onAppear { expandRunningPhases() }
        .onChange(of: workflow) { _, _ in expandRunningPhases() }
    }

    @ViewBuilder
    private func phaseDisclosure(_ phase: CoreWorkflowRunNode.Phase) -> some View {
        let expanded = expandedPhaseKeys.contains(phase.key)
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
                    memberRow(member)
                }
            }
        }
    }

    @ViewBuilder
    private func memberRow(_ member: CoreWorkflowRunNode.Member) -> some View {
        if NativeWorkflowRunPresentation.isNavigable(member) {
            Button {
                openSession(member.childID)
            } label: {
                memberContent(member)
            }
            .buttonStyle(.plain)
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

    private func togglePhase(_ key: String) {
        if expandedPhaseKeys.contains(key) {
            expandedPhaseKeys.remove(key)
        } else {
            expandedPhaseKeys.insert(key)
        }
    }

    /// RC8 status-driven defaults reopen the active work rather than requiring a
    /// user to discover it under collapsed disclosures after an event update.
    private func expandRunningPhases() {
        expandedPhaseKeys.formUnion(NativeWorkflowRunPresentation.runningPhaseKeys(workflow))
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
