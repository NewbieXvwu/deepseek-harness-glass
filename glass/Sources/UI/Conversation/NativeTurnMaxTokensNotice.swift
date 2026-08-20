import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Native RC8 `TurnMaxTokensItem`: a persistent warning anchored by the Core
/// node at the official closing assistant/raw end sequence decision.
struct NativeTurnMaxTokensNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: OfficialUISpec.Spacing.p8) {
            Circle()
                .fill(OfficialUISpec.Token.warningPrimary)
                .frame(width: OfficialUISpec.Geometry.px8, height: OfficialUISpec.Geometry.px8)
                .padding(.top, OfficialUISpec.Spacing.p4)
            VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p2) {
                Text(OfficialUISpec.Text.maxTokensTitle)
                    .font(OfficialUISpec.Typography.xsStrong13)
                    .foregroundStyle(OfficialUISpec.Token.warningPrimary)
                Text(OfficialUISpec.Text.maxTokensHint)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
            }
        }
        .padding(OfficialUISpec.Spacing.p12)
        .background(OfficialUISpec.Token.warningTertiary, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous).stroke(OfficialUISpec.Token.warningBorder, lineWidth: OfficialUISpec.Geometry.px1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(OfficialUISpec.Text.maxTokensTitle). \(OfficialUISpec.Text.maxTokensHint)")
    }
}
