import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Initial native surface for RC8's separately registered `trajectory` target.
/// The complete web view is a turn ledger with toolbar, timeline, search, and
/// details panes. This first renderer intentionally exposes only already-typed
/// target-owned input messages, so it never replays raw history or treats Chat
/// nodes as trajectory chronology.
///
/// Source: `ui-trajectory/src/client/TrajectoryView.tsx:142-149` reads the
/// trajectory inspection snapshot rather than the Chat target; `TrajectoryTable`
/// owns the later ledger/detail capabilities, which remain separate work.
struct NativeTrajectoryView: View {
    @ObservedObject var sessionStore: NativeSessionStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
                ForEach(sessionStore.trajectoryNodes, id: \.key) { node in
                    if node.visibility != .hidden,
                       let input = node.data as? CoreUserMessageNode {
                        NativeTrajectoryInputMessageRow(input: input)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OfficialUISpec.Spacing.p16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(OfficialUISpec.Text.trajectory)
    }
}

private struct NativeTrajectoryInputMessageRow: View {
    let input: CoreUserMessageNode

    private var text: String {
        input.content.compactMap(\.text).joined(separator: "\n")
    }

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(OfficialUISpec.Typography.s14)
                .foregroundStyle(OfficialUISpec.Token.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OfficialUISpec.Spacing.p12)
                .background(
                    OfficialUISpec.Token.elevated,
                    in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous)
                        .stroke(OfficialUISpec.Token.hairline, lineWidth: OfficialUISpec.Geometry.px1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(text)
        }
    }
}
