import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native RC8 composer context-occupancy seat. It reads the Host token-meter
/// projection directly and deliberately has no locally sampled token counter.
@MainActor
struct NativeContextMeter: View {
    @ObservedObject var sessionStore: NativeSessionStore
    @State private var isOpen = false

    init(sessionStore: NativeSessionStore) {
        self.sessionStore = sessionStore
    }

    private var state: CoreContextMeterState? {
        guard let sessionID = sessionStore.selectedSessionID else { return nil }
        return CoreContextMeterState.value(from: sessionStore.projections, sessionID: sessionID)
    }

    private var breakdown: CoreContextMeterBreakdown? {
        guard let sessionID = sessionStore.selectedSessionID else { return nil }
        return CoreContextMeterBreakdown.value(from: sessionStore.projections, sessionID: sessionID)
    }

    private var language: String { Locale.current.language.languageCode?.identifier ?? "en" }

    var body: some View {
        if let state {
            Button {
                isOpen.toggle()
            } label: {
                ZStack {
                    Circle()
                        .stroke(OfficialUISpec.Token.border, lineWidth: OfficialUISpec.Geometry.px2)
                    Circle()
                        .trim(from: 0, to: CGFloat(state.percent) / 100)
                        .stroke(OfficialUISpec.Token.businessBlue, style: .init(lineWidth: OfficialUISpec.Geometry.px2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(state.percent)%")
                        .font(OfficialUISpec.Typography.xxxsStrong11)
                        .monospacedDigit()
                }
                .frame(width: OfficialUISpec.Geometry.px28, height: OfficialUISpec.Geometry.px28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(t("context.aria", replacements: ["percent": "\(state.percent)%"]))
            .accessibilityValue("\(state.usedTokens)/\(state.contextWindow)")
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                contextDetail(state, breakdown: breakdown)
            }
        }
    }

    private func contextDetail(_ state: CoreContextMeterState, breakdown: CoreContextMeterBreakdown?) -> some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            Text(t("context.used"))
                .font(OfficialUISpec.Typography.baseStrong16)
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                Text("\(state.percent)%")
                    .font(OfficialUISpec.Typography.baseStrong16)
                    .monospacedDigit()
                Text("~\(formatTokens(state.usedTokens)) / \(formatTokens(state.contextWindow))")
                    .font(OfficialUISpec.Typography.s14)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: Double(state.percent), total: 100)
                .tint(OfficialUISpec.Token.businessBlue)
            if let breakdown {
                Divider()
                breakdownRow(label: t("context.system"), tokens: breakdown.systemTokens)
                breakdownRow(label: t("context.tools"), tokens: breakdown.toolsTokens)
                breakdownRow(label: t("context.messages"), tokens: breakdown.messageTokens)
            }
        }
        .padding(OfficialUISpec.Spacing.p16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("context.used"))
    }

    private func breakdownRow(label: String, tokens: Int) -> some View {
        HStack(spacing: OfficialUISpec.Spacing.p8) {
            Text(label)
                .font(OfficialUISpec.Typography.s14)
            Spacer(minLength: OfficialUISpec.Spacing.p0)
            Text("~\(formatTokens(tokens))")
                .font(OfficialUISpec.Typography.s14)
                .foregroundStyle(OfficialUISpec.Token.secondary)
                .monospacedDigit()
        }
    }

    private func formatTokens(_ value: Int) -> String {
        guard value >= 1_000 else { return "\(value)" }
        let rounded = Double(value) / 1_000
        if rounded >= 100 || rounded.rounded() == rounded { return "\(Int(rounded.rounded()))K" }
        return String(format: "%.1fK", rounded)
    }

    private func t(_ key: String, replacements: [String: String] = [:]) -> String {
        var value = OfficialUISpec.LocaleCatalog.value(
            namespace: "ui-conversation",
            key: key,
            language: language
        ) ?? key
        for (token, replacement) in replacements {
            value = value.replacingOccurrences(of: "{\(token)}", with: replacement)
        }
        return value
    }
}
