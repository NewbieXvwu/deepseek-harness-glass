import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Native RC8 `ModelRetryItem` counterpart. It reads the reducer's current
/// typed retry attempt, never raw `llm/retry` JSON. The live timer refinement
/// remains separate from this durable scheduled/started/cancelled projection.
struct NativeModelRetryRow: View {
    let retry: CoreRetryNode
    @State private var expanded = false

    private var current: CoreRetryAttempt? { retry.attempts.last }

    var body: some View {
        if let current {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
                    detail(OfficialUISpec.Text.retryDelay, "\(current.delayMilliseconds)ms")
                    detail(OfficialUISpec.Text.retryFailure, current.failureMessage)
                }
                .padding(.top, OfficialUISpec.Spacing.p8)
            } label: {
                Text(OfficialUISpec.Text.retryStatus(
                    label: label(for: current.state),
                    retry: current.retry,
                    maximum: current.unlimited ? "∞" : String(current.maximumRetries ?? current.retry),
                    seconds: max(0, Int(ceil(Double(current.delayMilliseconds) / 1_000)))
                ))
                .font(OfficialUISpec.Typography.xs13)
                .foregroundStyle(OfficialUISpec.Token.secondary)
                .accessibilityRole(.status)
            }
            .padding(OfficialUISpec.Spacing.p12)
            .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
        }
    }

    @ViewBuilder private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OfficialUISpec.Spacing.p4) {
            Text(label).font(OfficialUISpec.Typography.xsStrong13)
            Text(value.isEmpty ? "—" : value).font(OfficialUISpec.Typography.xs13)
        }
        .foregroundStyle(OfficialUISpec.Token.secondary)
    }

    private func label(for state: CoreRetryAttempt.State) -> String {
        switch state {
        case .scheduled: OfficialUISpec.Text.retryScheduled
        case .started: OfficialUISpec.Text.retryStarted
        case .cancelled: OfficialUISpec.Text.retryCancelled
        }
    }
}
