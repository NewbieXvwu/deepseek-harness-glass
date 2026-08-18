import SwiftUI

/// Native counterpart of `ApprovalPanel.tsx`: an approval request replaces the
/// normal composer until the Host broadcasts its resolved frame.
struct NativeApprovalPanel: View {
    let approval: NativeSessionStore.PendingApproval
    let command: String?
    let submitting: Bool
    let answer: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(OfficialUISpec.Token.warningPrimary)
                    .frame(width: 8, height: 8)
                Text(OfficialUISpec.Text.approvalWaiting)
                    .font(.system(size: 13, weight: .regular))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OfficialUISpec.Layout.approvalStripHorizontalPadding)
            .padding(.vertical, OfficialUISpec.Layout.approvalStripVerticalPadding)
            .background(OfficialUISpec.Token.warningTertiary)
            .foregroundStyle(OfficialUISpec.Token.warningPrimary)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(approval.reason ?? OfficialUISpec.Text.approvalEscalation(toolName: approval.toolName))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OfficialUISpec.Token.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let command {
                        Text(command)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(OfficialUISpec.Token.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: OfficialUISpec.Layout.approvalBodyMaximumHeight)
            .accessibilityLabel(OfficialUISpec.Text.approvalDetailsAccessibility)

            HStack(spacing: OfficialUISpec.Layout.approvalActionGap) {
                Spacer(minLength: 0)
                Button(action: { answer(false) }) {
                    Text(OfficialUISpec.Text.approvalReject)
                }
                .buttonStyle(NativeApprovalButtonStyle(primary: false))
                .disabled(submitting)
                Button(action: { answer(true) }) {
                    Text(OfficialUISpec.Text.approvalAllowOnce)
                }
                .buttonStyle(NativeApprovalButtonStyle(primary: true))
                .disabled(submitting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: OfficialUISpec.Layout.chatContentMaximum)
        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.approvalCardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OfficialUISpec.Layout.approvalCardCornerRadius, style: .continuous)
                .strokeBorder(OfficialUISpec.Token.warningBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 16, y: 6)
        .padding(.horizontal, OfficialUISpec.Layout.composerClearance + 16)
        .padding(.vertical, 8)
    }
}

private struct NativeApprovalButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? Color.white : OfficialUISpec.Token.primary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                primary ? OfficialUISpec.Token.businessBlue.opacity(configuration.isPressed ? 0.84 : 1) : OfficialUISpec.Token.elevated,
                in: Capsule()
            )
            .overlay {
                if !primary {
                    Capsule().strokeBorder(OfficialUISpec.Token.border, lineWidth: 1)
                }
            }
    }
}

/// Native counterpart of the generic `QuestionComposer.tsx` flow. The view
/// maintains local drafts only; the pending request and final answer remain
/// Host-owned and leave the composer only on `question/resolved`.
struct NativeQuestionComposer: View {
    private struct Draft {
        var selected: Set<String> = []
        var custom = ""
        var skipped = false

        var answered: Bool {
            !selected.isEmpty || !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    let pending: NativeSessionStore.PendingQuestion
    let submitting: Bool
    let answer: ([NativeSessionStore.QuestionAnswer]) -> Void
    let cancel: () -> Void

    @State private var index = 0
    @State private var drafts: [Draft]
    @State private var minimized = false
    @State private var feedback: String?

    init(
        pending: NativeSessionStore.PendingQuestion,
        submitting: Bool,
        answer: @escaping ([NativeSessionStore.QuestionAnswer]) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.pending = pending
        self.submitting = submitting
        self.answer = answer
        self.cancel = cancel
        _drafts = State(initialValue: Array(repeating: Draft(), count: pending.items.count))
    }

    private var current: NativeSessionStore.PendingQuestion.Item { pending.items[index] }
    private var draft: Draft { drafts[index] }
    private var hasOptions: Bool { !current.options.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !minimized {
                bodyContent
                footer
            }
        }
        .frame(maxWidth: OfficialUISpec.Layout.chatContentMaximum)
        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.approvalCardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OfficialUISpec.Layout.approvalCardCornerRadius, style: .continuous)
                .strokeBorder(OfficialUISpec.Token.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 16, y: 6)
        .padding(.horizontal, OfficialUISpec.Layout.composerClearance + 16)
        .padding(.vertical, 8)
        .id(pending.id)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let header = current.header {
                    Text(header)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OfficialUISpec.Token.caption)
                }
                Text(current.question)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(OfficialUISpec.Token.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Button(action: { minimized.toggle() }) {
                    OfficialAssetImage(name: "icon-chevron-down", template: true)
                        .rotationEffect(.degrees(minimized ? 180 : 0))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(OfficialCircleIconButtonStyle())
                .disabled(submitting)
                .accessibilityLabel(minimized ? OfficialUISpec.Text.questionMaximizeAccessibility : OfficialUISpec.Text.questionMinimizeAccessibility)
                Button(action: cancel) {
                    OfficialAssetImage(name: "icon-close", template: true)
                        .frame(width: 16, height: 16)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(OfficialCircleIconButtonStyle())
                .disabled(submitting)
                .accessibilityLabel(OfficialUISpec.Text.questionCancelAccessibility)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var bodyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let detail = current.detail {
                    Text(detail)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(current.options.enumerated()), id: \.element.id) { offset, option in
                        optionButton(option, position: offset + 1)
                    }
                    customAnswer
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: OfficialUISpec.Layout.approvalBodyMaximumHeight)
    }

    private func optionButton(_ option: NativeSessionStore.PendingQuestion.Option, position: Int) -> some View {
        let selected = draft.selected.contains(option.label)
        return Button(action: { choose(option.label) }) {
            HStack(spacing: 10) {
                if current.multiSelect {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(selected ? OfficialUISpec.Token.businessBlue : OfficialUISpec.Token.border, lineWidth: 1)
                            .background(selected ? OfficialUISpec.Token.businessBlue : Color.clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        if selected {
                            OfficialAssetImage(name: "icon-check", template: true)
                                .frame(width: 12, height: 12)
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: 16, height: 16)
                } else {
                    Text(String(position))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? Color.white : OfficialUISpec.Token.secondary)
                        .frame(width: 18, height: 18)
                        .background(selected ? OfficialUISpec.Token.businessBlue : OfficialUISpec.Token.interactiveHover, in: Circle())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OfficialUISpec.Token.primary)
                    if let detail = option.detail {
                        Text(detail)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(OfficialUISpec.Token.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected && !current.multiSelect ? OfficialUISpec.Token.businessBlueSoft : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(submitting)
        .accessibilityLabel(option.label)
    }

    @ViewBuilder
    private var customAnswer: some View {
        if hasOptions {
            TextField(OfficialUISpec.Text.questionCustomPlaceholder, text: customBinding)
                .font(.system(size: 13, weight: .regular))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(OfficialUISpec.Token.base, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(OfficialUISpec.Token.border, lineWidth: 1)
                }
                .disabled(submitting)
                .onSubmit { continueFlow() }
        } else {
            TextEditor(text: customBinding)
                .font(.system(size: 13, weight: .regular))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 56, maxHeight: 120)
                .padding(8)
                .background(OfficialUISpec.Token.base, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(OfficialUISpec.Token.border, lineWidth: 1)
                }
                .disabled(submitting)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Button(action: { move(to: index - 1) }) {
                    OfficialAssetImage(name: "icon-chevron-left", template: true)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(OfficialCircleIconButtonStyle())
                .disabled(index == 0 || submitting)
                .accessibilityLabel(OfficialUISpec.Text.questionPreviousAccessibility)
                Text(OfficialUISpec.Text.questionProgress(current: index + 1, total: pending.items.count))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                Button(action: { move(to: index + 1) }) {
                    OfficialAssetImage(name: "icon-chevron-right", template: true)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(OfficialCircleIconButtonStyle())
                .disabled(index == pending.items.count - 1 || submitting)
                .accessibilityLabel(OfficialUISpec.Text.questionNextAccessibility)
            }
            Spacer(minLength: 0)
            if let feedback {
                Text(feedback)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(OfficialUISpec.Token.warningPrimary)
                    .lineLimit(2)
            }
            Button(action: skip) {
                Text(OfficialUISpec.Text.questionSkip)
            }
            .buttonStyle(NativeApprovalButtonStyle(primary: false))
            .disabled(submitting)
            Button(action: continueFlow) {
                Text(submitting
                    ? OfficialUISpec.Text.questionSubmitting
                    : index == pending.items.count - 1 ? OfficialUISpec.Text.questionSubmit : OfficialUISpec.Text.questionNext)
            }
            .buttonStyle(NativeApprovalButtonStyle(primary: true))
            .disabled(submitting || !draft.answered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var customBinding: Binding<String> {
        Binding(
            get: { drafts[index].custom },
            set: { custom in
                drafts[index].custom = custom
                drafts[index].skipped = false
                if !current.multiSelect { drafts[index].selected = [] }
                feedback = nil
            }
        )
    }

    private func choose(_ label: String) {
        if current.multiSelect {
            if drafts[index].selected.contains(label) {
                drafts[index].selected.remove(label)
            } else {
                drafts[index].selected.insert(label)
            }
        } else {
            drafts[index].selected = [label]
            drafts[index].custom = ""
        }
        drafts[index].skipped = false
        feedback = nil
        if !current.multiSelect, index < pending.items.count - 1 { move(to: index + 1) }
    }

    private func move(to candidate: Int) {
        guard pending.items.indices.contains(candidate) else { return }
        index = candidate
        feedback = nil
    }

    private func continueFlow() {
        guard draft.answered else {
            feedback = OfficialUISpec.Text.questionUnanswered
            return
        }
        if index < pending.items.count - 1 {
            move(to: index + 1)
        } else {
            submit()
        }
    }

    private func skip() {
        drafts[index] = Draft(selected: [], custom: "", skipped: true)
        feedback = nil
        if index < pending.items.count - 1 {
            move(to: index + 1)
        } else {
            submit()
        }
    }

    private func submit() {
        guard let missing = drafts.indices.first(where: { !drafts[$0].answered && !drafts[$0].skipped }) else {
            answer(pending.items.indices.map { offset in
                let item = pending.items[offset]
                let draft = drafts[offset]
                return NativeSessionStore.QuestionAnswer(
                    id: item.id,
                    selected: draft.skipped ? [] : Array(draft.selected),
                    custom: draft.skipped ? nil : draft.custom.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            })
            return
        }
        move(to: missing)
        feedback = OfficialUISpec.Text.questionIncomplete
    }
}
