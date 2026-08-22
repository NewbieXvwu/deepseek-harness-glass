import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Compact read-only companion to the composer. It has no local counters: the
/// caller supplies a projection from materialized Host conversation nodes.
struct NativeStatsDock: View {
    let stats: NativeStatsDockPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
            Text(formatted("stats.counts", values: [
                "turns": String(stats.turns),
                "steps": String(stats.steps),
            ]))
            if let input = stats.inputTokens, let output = stats.outputTokens {
                Text(formatted("stats.tokens", values: [
                    "input": String(input),
                    "output": String(output),
                ]))
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // 官方锁定基线仅验证 en；zh 语义由 Host locale 数据保证
    private func formatted(_ key: String, values: [String: String]) -> String {
        var text = OfficialUISpec.LocaleCatalog.value(namespace: "ui-conversation", key: key, language: "en") ?? ""
        for (name, value) in values {
            text = text.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return text
    }
}
