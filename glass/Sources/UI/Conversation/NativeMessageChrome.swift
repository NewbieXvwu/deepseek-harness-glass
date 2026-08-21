import AppKit
import Foundation
import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Pure native counterpart of RC8 `formatMessageClock`. Host session event
/// times are Unix epoch milliseconds; the formatter has no transcript state and
/// can therefore be used by durable history and live-tail rows identically.
enum NativeMessageClockFormatter {
    static func label(
        timeMilliseconds: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let date = Date(timeIntervalSince1970: timeMilliseconds / 1_000)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let current = calendar.dateComponents([.year, .month, .day], from: now)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let clock = String(format: "%02d:%02d", hour, minute)

        guard components.year != current.year || components.month != current.month || components.day != current.day else {
            return clock
        }

        let month = components.month ?? 0
        let day = components.day ?? 0
        if components.year == current.year {
            return "\(month)/\(day) \(clock)"
        }
        return "\(components.year ?? 0)-\(month)-\(day) \(clock)"
    }
}

/// Native message chrome matching the RC8 copy/check lifecycle. A row owns
/// only presentation-local feedback; it writes the durable plain text provided
/// by Core and never mutates transcript state.
struct NativeMessageActionRow: View {
    enum ClockPosition {
        case start
        case end
    }

    /// Durable Host message identity that scopes presentation-local copy feedback.
    let messageID: String
    let text: String
    let time: Double?
    let clockPosition: ClockPosition
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: OfficialUISpec.Layout.chatMessageActionGap) {
            if clockPosition == .start { clock }
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .frame(
                        width: OfficialUISpec.Layout.chatMessageActionSize,
                        height: OfficialUISpec.Layout.chatMessageActionSize
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(OfficialUISpec.Token.caption)
            .accessibilityLabel(copied ? OfficialUISpec.Text.copied : OfficialUISpec.Text.copy)
            if clockPosition == .end { clock }
        }
        .frame(minHeight: OfficialUISpec.Layout.chatMessageActionSize)
        .onChange(of: messageID) { _, _ in
            resetTask?.cancel()
            resetTask = nil
            copied = false
        }
        .onDisappear {
            resetTask?.cancel()
            resetTask = nil
        }
    }

    @ViewBuilder
    private var clock: some View {
        if let time {
            Text(NativeMessageClockFormatter.label(timeMilliseconds: time))
                .font(OfficialUISpec.Typography.xxs12)
                .foregroundStyle(OfficialUISpec.Token.caption)
                .monospacedDigit()
                .accessibilityLabel(NativeMessageClockFormatter.label(timeMilliseconds: time))
        }
    }

    private func copy() {
        guard !messageID.isEmpty, !copied else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return }
        copied = true
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            copied = false
            resetTask = nil
        }
    }
}

/// The initial native status tail. It remains outside the text row so streaming
/// deltas update their keyed message without causing the entire scroll column to
/// recompose; duration/metrics are omitted until their Host contracts land.
struct NativeRunningTurnStatus: View {
    var body: some View {
        Text(OfficialUISpec.Text.deepDiving)
            .font(OfficialUISpec.Typography.sStrong14)
            .foregroundStyle(OfficialUISpec.Token.businessBlue)
            .frame(height: OfficialUISpec.Layout.chatRunningStatusHeight, alignment: .leading)
            .accessibilityLabel(OfficialUISpec.Text.deepDiving)
    }
}
