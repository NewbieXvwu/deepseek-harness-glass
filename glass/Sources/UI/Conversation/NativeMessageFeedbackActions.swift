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
    let like: () -> Void
    let dislike: () -> Void

    private var likeActive: Bool { item?.rating == .positive }
    private var dislikeActive: Bool { item?.rating == .negative }
    private var likeLabel: String { likeActive ? OfficialUISpec.Text.feedbackLikeActive : OfficialUISpec.Text.feedbackLike }
    private var dislikeLabel: String { dislikeActive ? OfficialUISpec.Text.feedbackDislikeActive : OfficialUISpec.Text.feedbackDislike }

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
        }
        .accessibilityElement(children: .contain)
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
