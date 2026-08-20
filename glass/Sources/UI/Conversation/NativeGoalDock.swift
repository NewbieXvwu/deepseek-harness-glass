import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Pure RC8 GoalBar visibility and copy decisions shared by the native dock and
/// its regression tests. Goal values remain whole Host projections; the clear
/// marker is presentation-only and never replaces that value.
enum NativeGoalDockPresentation {
    static func isVisible(_ goal: CoreGoalProjection?, locallyClearedGoalID: String?) -> Bool {
        guard let goal, goal.phase != .complete else { return false }
        return goal.id != locallyClearedGoalID
    }

    static func phaseLabel(for phase: CoreGoalProjection.Phase) -> String? {
        switch phase {
        case .active: OfficialUISpec.Text.goalPhaseActive
        case .paused: OfficialUISpec.Text.goalPhasePaused
        case .blocked: OfficialUISpec.Text.goalPhaseBlocked
        case .complete: nil
        }
    }

    static func failureText(_ failure: NativeSessionStore.GoalActionFailure?) -> String? {
        guard let failure else { return nil }
        return OfficialUISpec.Text.goalActionFailure(message: failure.message, code: failure.code)
    }
}

/// Native equivalent of the RC8 `conversation.input.dock` GoalBar. It owns only
/// local edit draft/focus state. The current goal, all mutations and their
/// eventual replacement/tombstone projection remain Host-owned.
struct NativeGoalDock: View {
    let goal: CoreGoalProjection
    let isSubmitting: Bool
    let failure: NativeSessionStore.GoalActionFailure?
    let edit: (String) -> Void
    let pause: () -> Void
    let resume: () -> Void
    let clear: () -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        VStack(spacing: OfficialUISpec.Spacing.p0) {
            if editing {
                editingBar
            } else {
                displayBar
            }
        }
        .frame(maxWidth: OfficialUISpec.Layout.composerMaximum - (OfficialUISpec.Layout.todoDockInset * 4))
        .id(goal.id)
        .onChange(of: goal.id) { _, _ in
            // RC8 clears a surviving edit draft when a new projection identity
            // arrives so Enter cannot overwrite a replacement goal.
            editing = false
            draft = ""
        }
    }

    private var displayBar: some View {
        HStack(spacing: OfficialUISpec.Layout.goalDockContentGap) {
            OfficialAssetImage(name: "icon-goal", template: true)
                .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                .foregroundStyle(OfficialUISpec.Token.caption)

            Text(NativeGoalDockPresentation.phaseLabel(for: goal.phase) ?? "")
                .font(OfficialUISpec.Typography.xsStrong13)
                .foregroundStyle(OfficialUISpec.Token.primary)
                .lineLimit(1)

            Text(goal.objective)
                .font(OfficialUISpec.Typography.xs13)
                .foregroundStyle(OfficialUISpec.Token.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(goal.phase == .blocked ? (goal.blockedReason?.message ?? "") : "")

            if let failureText = NativeGoalDockPresentation.failureText(failure) {
                Text(failureText)
                    .font(OfficialUISpec.Typography.xxs12)
                    .foregroundStyle(OfficialUISpec.Token.errorPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityLabel(failureText)
            }

            Spacer(minLength: 0)

            if goal.phase == .active {
                goalIconButton(asset: "icon-pause", accessibility: OfficialUISpec.Text.goalPauseAccessibility, action: pause)
            } else if goal.phase == .paused {
                goalIconButton(asset: "icon-play", accessibility: OfficialUISpec.Text.goalResumeAccessibility, action: resume)
            }
            goalIconButton(asset: "icon-tool-edit", accessibility: OfficialUISpec.Text.goalEditAccessibility) {
                draft = goal.objective
                editing = true
                editFocused = true
            }
            goalIconButton(asset: "icon-trash", accessibility: OfficialUISpec.Text.goalClearAccessibility, action: clear)
        }
        .goalDockBarStyle()
    }

    private var editingBar: some View {
        HStack(spacing: OfficialUISpec.Layout.goalDockContentGap) {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(OfficialUISpec.Typography.xs13)
                .foregroundStyle(OfficialUISpec.Token.primary)
                .focused($editFocused)
                .frame(height: OfficialUISpec.Layout.goalDockInputHeight)
                .padding(.horizontal, OfficialUISpec.Spacing.p8)
                .background(OfficialUISpec.Token.base, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.goalDockInputCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: OfficialUISpec.Layout.goalDockInputCornerRadius, style: .continuous)
                        .stroke(OfficialUISpec.Token.border, lineWidth: OfficialUISpec.Geometry.px1)
                }
                .onSubmit(saveDraft)
                .onExitCommand { cancelEditing() }
                .accessibilityLabel(OfficialUISpec.Text.goalObjectiveAccessibility)

            if let failureText = NativeGoalDockPresentation.failureText(failure) {
                Text(failureText)
                    .font(OfficialUISpec.Typography.xxs12)
                    .foregroundStyle(OfficialUISpec.Token.errorPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityLabel(failureText)
            }

            Spacer(minLength: 0)
            goalIconButton(
                asset: "icon-check",
                accessibility: OfficialUISpec.Text.goalSaveAccessibility,
                enabled: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: saveDraft
            )
            goalIconButton(asset: "icon-close", accessibility: OfficialUISpec.Text.goalCancelAccessibility, action: cancelEditing)
        }
        .goalDockBarStyle()
        .onAppear { editFocused = true }
    }

    @ViewBuilder
    private func goalIconButton(
        asset: String,
        accessibility: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            OfficialAssetImage(name: asset, template: true)
                .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                .frame(width: OfficialUISpec.Layout.goalDockIconControl, height: OfficialUISpec.Layout.goalDockIconControl)
        }
        .buttonStyle(NativeGoalIconButtonStyle())
        .disabled(isSubmitting || !enabled)
        .accessibilityLabel(accessibility)
    }

    private func saveDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSubmitting else { return }
        edit(trimmed)
    }

    private func cancelEditing() {
        guard !isSubmitting else { return }
        editing = false
        draft = ""
        editFocused = false
    }
}

private extension View {
    func goalDockBarStyle() -> some View {
        frame(minHeight: OfficialUISpec.Layout.goalDockHeight)
            .padding(.leading, OfficialUISpec.Layout.goalDockLeadingPadding)
            .padding(.trailing, OfficialUISpec.Layout.goalDockTrailingPadding)
            .padding(.vertical, OfficialUISpec.Layout.goalDockVerticalPadding)
            .background(OfficialUISpec.Token.specificTip, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.goalDockCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: OfficialUISpec.Layout.goalDockCornerRadius, style: .continuous)
                    .stroke(OfficialUISpec.Token.hairline, lineWidth: OfficialUISpec.Geometry.px1)
            }
    }
}

private struct NativeGoalIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OfficialUISpec.Token.caption)
            .background(
                configuration.isPressed ? OfficialUISpec.Token.interactiveHover : .clear,
                in: Circle()
            )
            .contentShape(Circle())
    }
}
