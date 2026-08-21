import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native RC8 message-feedback action subset. It is mounted only for a settled
/// assistant node carrying a typed message ID; mutation state remains Store/Host
/// owned, and this view never writes a local rating on click.
struct NativeMessageFeedbackActions: View {
    let item: MessageFeedbackItemDTO?
    let isSubmitting: Bool
    let loadFailed: Bool
    let actionFailureCode: String?
    let like: () -> Void
    let dislike: () -> Void
    let saveNote: (String) -> Void

    @State private var noteOpen = false
    @State private var draft = ""
    @State private var noteMutationBaseVersion: String?

    private var likeActive: Bool { item?.rating == .positive }
    private var dislikeActive: Bool { item?.rating == .negative }
    private var likeLabel: String { likeActive ? OfficialUISpec.Text.feedbackLikeActive : OfficialUISpec.Text.feedbackLike }
    private var dislikeLabel: String { dislikeActive ? OfficialUISpec.Text.feedbackDislikeActive : OfficialUISpec.Text.feedbackDislike }
    private var actionFailureText: String? {
        guard let actionFailureCode else { return nil }
        return actionFailureCode == "version-conflict"
            ? OfficialUISpec.Text.feedbackErrorConflict
            : OfficialUISpec.Text.feedbackErrorGeneric
    }

    var body: some View {
        HStack(spacing: OfficialUISpec.Spacing.p4) {
            actionButton(
                systemImage: "hand.thumbsup",
                label: likeLabel,
                active: likeActive,
                action: like
            )
            actionButton(
                systemImage: "hand.thumbsdown",
                label: dislikeLabel,
                active: dislikeActive,
                action: dislike
            )
            if item != nil {
                noteTrigger
            }
            if let actionFailureText {
                failureRow(actionFailureText)
            } else if loadFailed {
                failureRow(OfficialUISpec.Text.feedbackErrorLoad)
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: isSubmitting) { wasSubmitting, nowSubmitting in
            guard wasSubmitting, !nowSubmitting, let base = noteMutationBaseVersion else { return }
            defer { noteMutationBaseVersion = nil }
            guard actionFailureCode == nil, item?.version != base else { return }
            noteOpen = false
        }
    }

    private var noteTrigger: some View {
        Button {
            if noteOpen {
                noteOpen = false
            } else {
                draft = item?.note ?? ""
                noteMutationBaseVersion = nil
                noteOpen = true
            }
        } label: {
            Text(item?.note ?? OfficialUISpec.Text.feedbackNoteOpen)
                .font(OfficialUISpec.Typography.xs13)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(OfficialUISpec.Token.caption)
        .accessibilityLabel(OfficialUISpec.Text.feedbackNoteOpen)
        .popover(isPresented: $noteOpen, arrowEdge: .bottom) {
            noteEditor
        }
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            Text(OfficialUISpec.Text.feedbackNoteDialog)
                .font(OfficialUISpec.Typography.xsStrong13)
                .foregroundStyle(OfficialUISpec.Token.primary)
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(OfficialUISpec.Text.feedbackNotePlaceholder)
                        .font(OfficialUISpec.Typography.xs13)
                        .foregroundStyle(OfficialUISpec.Token.placeholder)
                        .padding(.top, OfficialUISpec.Spacing.p6)
                        .padding(.leading, OfficialUISpec.Spacing.p5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.primary)
                    .frame(minHeight: OfficialUISpec.Geometry.px72)
                    .accessibilityLabel(OfficialUISpec.Text.feedbackNoteAccessibility)
            }
            .overlay {
                RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous)
                    .stroke(OfficialUISpec.Token.border, lineWidth: 1)
            }
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                Button(OfficialUISpec.Text.feedbackNoteSave) {
                    noteMutationBaseVersion = item?.version
                    saveNote(draft)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
                Button(OfficialUISpec.Text.feedbackNoteCancel) {
                    noteMutationBaseVersion = nil
                    noteOpen = false
                }
                .buttonStyle(.bordered)
                .disabled(isSubmitting)
            }
            if let actionFailureText {
                failureRow(actionFailureText)
            }
        }
        .padding(OfficialUISpec.Spacing.p8)
        .frame(width: OfficialUISpec.Geometry.px320)
        .accessibilityElement(children: .contain)
    }

    private func failureRow(_ text: String) -> some View {
        Text(text)
            .font(OfficialUISpec.Typography.xs13)
            .foregroundStyle(OfficialUISpec.Token.errorPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private func actionButton(
        systemImage: String,
        label: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(OfficialUISpec.Typography.xs13)
                .frame(width: OfficialUISpec.Geometry.px28, height: OfficialUISpec.Geometry.px28)
                .background(active ? OfficialUISpec.Token.businessBlueSoft : Color.clear, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? OfficialUISpec.Token.businessBlue : OfficialUISpec.Token.caption)
        .disabled(isSubmitting)
        .accessibilityLabel(label)
        .accessibilityValue(active ? label : "")
    }
}
