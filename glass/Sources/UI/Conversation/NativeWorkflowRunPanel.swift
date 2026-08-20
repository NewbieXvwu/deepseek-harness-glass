import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Initial native counterpart of RC8's keyed `workflow-run` chat renderer.
/// It renders only the Core-owned run snapshot; raw workflow events and inferred
/// child/session topology never reach this view.
struct NativeWorkflowRunPanel: View {
    let workflow: CoreWorkflowRunNode

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                Circle().fill(color(for: workflow.status)).frame(width: OfficialUISpec.Geometry.px8, height: OfficialUISpec.Geometry.px8)
                Text(workflow.name.isEmpty ? OfficialUISpec.Text.workflowEmptyMember : workflow.name)
                    .font(OfficialUISpec.Typography.xsStrong13)
                    .foregroundStyle(OfficialUISpec.Token.primary)
                Text(label(for: workflow.status))
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
            }
            if workflow.phases.isEmpty {
                Text(OfficialUISpec.Text.workflowNoMembers)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            } else {
                ForEach(workflow.phases, id: \.key) { phase in
                    VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
                        Text(phase.phase == nil ? OfficialUISpec.Text.workflowUnphased : (phase.phase?.isEmpty == true ? OfficialUISpec.Text.workflowEmptyPhase : phase.phase!))
                            .font(OfficialUISpec.Typography.xsStrong13)
                            .foregroundStyle(OfficialUISpec.Token.secondary)
                        ForEach(phase.members, id: \.seq) { member in
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
                        }
                    }
                }
            }
        }
        .padding(OfficialUISpec.Spacing.p12)
        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous).stroke(OfficialUISpec.Token.hairline, lineWidth: OfficialUISpec.Geometry.px1) }
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
