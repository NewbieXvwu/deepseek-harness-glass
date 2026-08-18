import SwiftUI

private struct NativeCappedContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Mirrors the official CSS `max-height` policy: content stays intrinsic below
/// the cap, then becomes vertically scrollable above it.
private struct NativeCappedVerticalScroll<Content: View>: View {
    let maximumHeight: CGFloat
    let content: Content
    @State private var measuredHeight: CGFloat = 1

    init(maximumHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maximumHeight = maximumHeight
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: NativeCappedContentHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .frame(height: min(maximumHeight, max(1, measuredHeight)))
        .onPreferenceChange(NativeCappedContentHeightKey.self) { measuredHeight = $0 }
    }
}

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

            NativeCappedVerticalScroll(maximumHeight: OfficialUISpec.Layout.approvalBodyMaximumHeight) {
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
        .padding(.top, OfficialUISpec.Layout.approvalSeatTop)
        .padding(.bottom, OfficialUISpec.Layout.approvalSeatBottom)
    }
}

private struct NativeApprovalButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(primary ? Color.white : OfficialUISpec.Token.primary)
            .padding(.horizontal, OfficialUISpec.Layout.actionButtonHorizontalPadding)
            .frame(height: OfficialUISpec.Layout.actionButtonHeight)
            .background(
                primary ? OfficialUISpec.Token.businessBlue.opacity(configuration.isPressed ? 0.84 : 1) : OfficialUISpec.Token.elevated,
                in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.actionButtonCornerRadius, style: .continuous)
            )
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: OfficialUISpec.Layout.actionButtonCornerRadius, style: .continuous)
                        .strokeBorder(OfficialUISpec.Token.border, lineWidth: 1)
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
        .padding(.bottom, OfficialUISpec.Layout.questionCardBottomPadding)
        .frame(maxWidth: OfficialUISpec.Layout.chatContentMaximum)
        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.questionCardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OfficialUISpec.Layout.questionCardCornerRadius, style: .continuous)
                .strokeBorder(OfficialUISpec.Token.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 16, y: 6)
        .padding(.horizontal, OfficialUISpec.Layout.composerClearance + 16)
        .padding(.top, OfficialUISpec.Layout.questionSeatTop)
        .padding(.bottom, OfficialUISpec.Layout.questionSeatBottom)
        .id(pending.id)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                if let header = current.header {
                    Text(header)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OfficialUISpec.Token.caption)
                }
                Text(current.question)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(OfficialUISpec.Token.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            HStack(spacing: OfficialUISpec.Layout.questionHeaderActionGap) {
                Button(action: { minimized.toggle() }) {
                    OfficialAssetImage(name: "icon-chevron-down", template: true)
                        .rotationEffect(.degrees(minimized ? 180 : 0))
                        .frame(width: OfficialUISpec.Layout.questionIconControl, height: OfficialUISpec.Layout.questionIconControl)
                }
                .buttonStyle(OfficialCircleIconButtonStyle())
                .disabled(submitting)
                .accessibilityLabel(minimized ? OfficialUISpec.Text.questionMaximizeAccessibility : OfficialUISpec.Text.questionMinimizeAccessibility)
                Button(action: cancel) {
                    OfficialAssetImage(name: "icon-close", template: true)
                        .frame(width: 16, height: 16)
                        .frame(width: OfficialUISpec.Layout.questionIconControl, height: OfficialUISpec.Layout.questionIconControl)
                }
                .buttonStyle(OfficialCircleIconButtonStyle())
                .disabled(submitting)
                .accessibilityLabel(OfficialUISpec.Text.questionCancelAccessibility)
            }
        }
        .padding(.leading, OfficialUISpec.Layout.questionHeaderLeading)
        .padding(.trailing, OfficialUISpec.Layout.questionHeaderTrailing)
        .padding(.top, OfficialUISpec.Layout.questionHeaderTop)
    }

    private var bodyContent: some View {
        NativeCappedVerticalScroll(maximumHeight: OfficialUISpec.Layout.approvalBodyMaximumHeight) {
            VStack(alignment: .leading, spacing: 0) {
                if let detail = current.detail {
                    Text(detail)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                        .padding(.horizontal, 2)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(current.options.enumerated()), id: \.element.id) { offset, option in
                        optionButton(option, position: offset + 1)
                    }
                    customAnswer
                }
            }
            .padding(.horizontal, OfficialUISpec.Layout.questionOptionsHorizontalPadding)
            .padding(.top, OfficialUISpec.Layout.questionOptionsTopMargin + OfficialUISpec.Layout.questionOptionsVerticalPadding)
            .padding(.bottom, OfficialUISpec.Layout.questionOptionsVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func optionButton(_ option: NativeSessionStore.PendingQuestion.Option, position: Int) -> some View {
        let selected = draft.selected.contains(option.label)
        let display = recommendedLabel(option.label)
        return Button(action: { choose(option.label) }) {
            HStack(alignment: .top, spacing: OfficialUISpec.Layout.questionOptionGap) {
                if current.multiSelect {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(selected ? OfficialUISpec.Token.primary : OfficialUISpec.Token.border, lineWidth: 1)
                            .background(selected ? OfficialUISpec.Token.primary : Color.clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        if selected {
                            OfficialAssetImage(name: "icon-check", template: true)
                                .frame(width: 12, height: 12)
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: OfficialUISpec.Layout.questionOptionIndicator, height: OfficialUISpec.Layout.questionOptionIndicator)
                    .padding(.top, 2)
                } else {
                    Text(String(position))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                        .frame(width: OfficialUISpec.Layout.questionOptionIndicator, height: OfficialUISpec.Layout.questionOptionIndicator)
                        .background(OfficialUISpec.Token.interactiveHover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.top, 2)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(display.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(OfficialUISpec.Token.primary)
                    if display.recommended {
                        Text(OfficialUISpec.Text.questionRecommended)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(OfficialUISpec.Token.businessBlue)
                            .padding(.horizontal, 4)
                            .background(OfficialUISpec.Token.businessBlueSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    if let detail = option.detail {
                        Text(detail)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(OfficialUISpec.Token.caption)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, OfficialUISpec.Layout.questionOptionsHorizontalPadding)
            .padding(.vertical, 8)
            .frame(minHeight: OfficialUISpec.Layout.questionOptionOuterHeight)
            .background(selected && !current.multiSelect ? OfficialUISpec.Token.interactiveHover : Color.clear, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.questionOptionCornerRadius, style: .continuous))
            .overlay {
                if selected && !current.multiSelect {
                    RoundedRectangle(cornerRadius: OfficialUISpec.Layout.questionOptionCornerRadius, style: .continuous)
                        .strokeBorder(OfficialUISpec.Token.border, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(submitting)
        .accessibilityLabel(display.label)
    }

    @ViewBuilder
    private var customAnswer: some View {
        if hasOptions {
            HStack(alignment: .top, spacing: OfficialUISpec.Layout.questionOptionGap) {
                OfficialAssetImage(name: "icon-tool-edit", template: true)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .frame(width: OfficialUISpec.Layout.questionOptionIndicator, height: OfficialUISpec.Layout.questionOptionIndicator)
                    .background(OfficialUISpec.Token.interactiveHover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.top, 2)
                TextField(OfficialUISpec.Text.questionCustomPlaceholder, text: customBinding)
                    .font(.system(size: 14, weight: .regular))
                    .textFieldStyle(.plain)
                    .frame(height: 24)
                    .disabled(submitting)
                    .onSubmit { continueFlow() }
            }
            .padding(.leading, 8)
            .padding(.trailing, OfficialUISpec.Layout.questionOptionsHorizontalPadding)
            .padding(.vertical, 8)
            .frame(minHeight: OfficialUISpec.Layout.questionOptionOuterHeight)
            .background(draft.custom.isEmpty ? Color.clear : OfficialUISpec.Token.interactiveHover, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.questionOptionCornerRadius, style: .continuous))
            .overlay {
                if !draft.custom.isEmpty {
                    RoundedRectangle(cornerRadius: OfficialUISpec.Layout.questionOptionCornerRadius, style: .continuous)
                        .strokeBorder(OfficialUISpec.Token.border, lineWidth: 1)
                }
            }
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
        HStack(spacing: OfficialUISpec.Layout.questionFooterActionGap) {
            HStack(spacing: 6) {
                Button(action: { move(to: index - 1) }) {
                    OfficialAssetImage(name: "icon-chevron-left", template: true)
                        .frame(width: OfficialUISpec.Layout.questionIconControl, height: OfficialUISpec.Layout.questionIconControl)
                }
                .buttonStyle(OfficialCircleIconButtonStyle())
                .disabled(index == 0 || submitting)
                .accessibilityLabel(OfficialUISpec.Text.questionPreviousAccessibility)
                Text(OfficialUISpec.Text.questionProgress(current: index + 1, total: pending.items.count))
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 4)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                Button(action: { move(to: index + 1) }) {
                    OfficialAssetImage(name: "icon-chevron-right", template: true)
                        .frame(width: OfficialUISpec.Layout.questionIconControl, height: OfficialUISpec.Layout.questionIconControl)
                }
                .buttonStyle(OfficialCircleIconButtonStyle())
                .disabled(index == pending.items.count - 1 || submitting)
                .accessibilityLabel(OfficialUISpec.Text.questionNextAccessibility)
            }
            Text(feedback ?? "")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(OfficialUISpec.Token.warningPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: OfficialUISpec.Layout.questionFooterFeedbackMinimumHeight, alignment: .trailing)
            HStack(spacing: OfficialUISpec.Layout.questionFooterActionGap) {
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
        }
        .padding(.top, OfficialUISpec.Layout.questionFooterTopMargin)
        .padding(.leading, OfficialUISpec.Layout.questionFooterLeading)
        .padding(.trailing, OfficialUISpec.Layout.questionFooterTrailing)
    }

    /// Source: `QuestionComposer.tsx:parseRecommendedLabel`; selection keeps
    /// the original Host value while the conventional suffix becomes a badge.
    private func recommendedLabel(_ label: String) -> (label: String, recommended: Bool) {
        let suffixes = [" (Recommended)", "（Recommended）", " (推荐)", "（推荐）"]
        for suffix in suffixes where label.lowercased().hasSuffix(suffix.lowercased()) {
            return (String(label.dropLast(suffix.count)), true)
        }
        return (label, false)
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
