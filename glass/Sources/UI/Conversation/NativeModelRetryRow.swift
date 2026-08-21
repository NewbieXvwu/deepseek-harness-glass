import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native RC8 `ModelRetryItem` counterpart. It reads the reducer's current
/// typed retry attempt, never raw `llm/retry` JSON. Scheduled attempts refresh
/// their official remaining-seconds label at the same 250ms cadence as RC8.
struct NativeModelRetryRow: View {
    let retry: CoreRetryNode
    @State private var expanded = false
    @State private var countdownSeconds: Int?
    @State private var countdownDeadline = Date.distantPast

    private var current: CoreRetryAttempt? { retry.attempts.last }
    private var isScheduled: Bool { current?.state == .scheduled }

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
                    seconds: displayedSeconds(for: current)
                ))
                .font(OfficialUISpec.Typography.xs13)
                .foregroundStyle(OfficialUISpec.Token.secondary)
            }
            .padding(OfficialUISpec.Spacing.p12)
            .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
            .onAppear { resetCountdown() }
            .onChange(of: retry.attempts) { _, _ in resetCountdown() }
            .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
                refreshCountdown()
            }
        }
    }

    @ViewBuilder private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OfficialUISpec.Spacing.p4) {
            Text(label).font(OfficialUISpec.Typography.xsStrong13)
            Text(value.isEmpty ? "—" : value).font(OfficialUISpec.Typography.xs13)
        }
        .foregroundStyle(OfficialUISpec.Token.secondary)
    }

    private func displayedSeconds(for attempt: CoreRetryAttempt) -> Int {
        guard attempt.state == .scheduled else {
            return scheduledSeconds(for: attempt)
        }
        return countdownSeconds ?? scheduledSeconds(for: attempt)
    }

    private func scheduledSeconds(for attempt: CoreRetryAttempt) -> Int {
        max(0, Int(ceil(Double(attempt.delayMilliseconds) / 1_000)))
    }

    /// Source: RC8 ModelRetryItem schedules 250ms refreshes only for a typed
    /// scheduled attempt and stops at the stable final one-second display.
    private func resetCountdown() {
        guard let current, current.state == .scheduled else {
            countdownSeconds = nil
            countdownDeadline = .distantPast
            return
        }
        countdownDeadline = Date().addingTimeInterval(Double(current.delayMilliseconds) / 1_000)
        countdownSeconds = remainingSeconds()
    }

    private func refreshCountdown() {
        guard isScheduled, countdownSeconds != nil, countdownSeconds != 1 else { return }
        countdownSeconds = remainingSeconds()
    }

    private func remainingSeconds() -> Int {
        max(0, Int(ceil(countdownDeadline.timeIntervalSinceNow)))
    }

    private func label(for state: CoreRetryAttempt.State) -> String {
        switch state {
        case .scheduled: OfficialUISpec.Text.retryScheduled
        case .started: OfficialUISpec.Text.retryStarted
        case .cancelled: OfficialUISpec.Text.retryCancelled
        }
    }
}
