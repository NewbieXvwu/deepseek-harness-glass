import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native counterpart of RC8 `TurnErrorItem`. Visibility/terminality are owned
/// by `CoreTurnErrorNode`; this renderer merely presents its typed failure.
struct NativeTurnErrorNotice: View {
    let error: CoreTurnErrorNode

    var body: some View {
        HStack(alignment: .top, spacing: OfficialUISpec.Spacing.p8) {
            Circle()
                .fill(OfficialUISpec.Token.errorPrimary)
                .frame(width: OfficialUISpec.Geometry.px8, height: OfficialUISpec.Geometry.px8)
                .padding(.top, OfficialUISpec.Spacing.p4)
            VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p2) {
                Text(OfficialUISpec.Text.turnErrorTitle)
                    .font(OfficialUISpec.Typography.xsStrong13)
                    .foregroundStyle(OfficialUISpec.Token.errorPrimary)
                Text(error.message)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                if let code = error.code, !code.isEmpty {
                    Text(code)
                        .font(OfficialUISpec.Typography.xs13.monospaced())
                        .foregroundStyle(OfficialUISpec.Token.caption)
                }
            }
        }
        .padding(OfficialUISpec.Spacing.p12)
        .background(OfficialUISpec.Token.errorSecondary.opacity(0.16), in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous).stroke(OfficialUISpec.Token.errorSecondary, lineWidth: OfficialUISpec.Geometry.px1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(OfficialUISpec.Text.turnErrorTitle)
    }
}
