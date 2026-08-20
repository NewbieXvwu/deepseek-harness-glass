import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native RC8 `SubagentReadOnlyComposer` counterpart. This view is selected
/// only from the Host-owned `subagent` identity projection; it never infers a
/// one-shot mode from a catalog row or session summary.
struct NativeSubagentReadOnlyComposer: View {
    enum Reason { case oneShot, parentUnavailable }
    let reason: Reason

    private var title: String {
        switch reason {
        case .oneShot: OfficialUISpec.Text.subagentOneShotReadOnlyTitle
        case .parentUnavailable: OfficialUISpec.Text.subagentParentUnavailableReadOnlyTitle
        }
    }

    private var bodyText: String {
        switch reason {
        case .oneShot: OfficialUISpec.Text.subagentOneShotReadOnlyBody
        case .parentUnavailable: OfficialUISpec.Text.subagentParentUnavailableReadOnlyBody
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p6) {
            Text(title)
                .font(OfficialUISpec.Typography.xsStrong13)
                .foregroundStyle(OfficialUISpec.Token.primary)
            Text(bodyText)
                .font(OfficialUISpec.Typography.xs13)
                .foregroundStyle(OfficialUISpec.Token.secondary)
        }
        .padding(OfficialUISpec.Spacing.p12)
        .frame(maxWidth: OfficialUISpec.Layout.composerMaximum, alignment: .leading)
        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.composerCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OfficialUISpec.Layout.composerCornerRadius, style: .continuous)
                .strokeBorder(OfficialUISpec.Token.border, lineWidth: OfficialUISpec.Geometry.px1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
