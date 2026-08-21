import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Typed presentation contract for a landed RC8 compaction checkpoint. It
/// never reads checkpoint payloads or raw events beyond the Core node fields.
enum NativeCompactionPresentation {
    static func isExpandable(_ compaction: CoreCompactionNode) -> Bool {
        compaction.summary != nil
    }

    static func summary(_ compaction: CoreCompactionNode) -> String {
        if let items = compaction.shadowedItemCount, let tokens = compaction.shadowedTokenCount {
            return OfficialUISpec.Text.compactionCompleted(items: items, tokens: tokens)
        }
        if isExpandable(compaction) { return OfficialUISpec.Text.compactionExpand }
        return OfficialUISpec.Text.compactionUnavailable
    }
}

/// Native RC8 `CompactionItem`: a landed checkpoint marker, not a replacement
/// for the history it shadows.
struct NativeCompactionRow: View {
    let compaction: CoreCompactionNode
    @State private var expanded = false

    private var isExpandable: Bool { NativeCompactionPresentation.isExpandable(compaction) }
    private var summary: String { NativeCompactionPresentation.summary(compaction) }

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: OfficialUISpec.Spacing.p8) {
                    Image(systemName: "rectangle.compress.vertical")
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(OfficialUISpec.Typography.xxxs11)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                    Text(OfficialUISpec.Text.compactionTitle)
                        .font(OfficialUISpec.Typography.xsStrong13)
                        .foregroundStyle(OfficialUISpec.Token.primary)
                    Rectangle()
                        .fill(OfficialUISpec.Token.hairline)
                        .frame(width: OfficialUISpec.Geometry.px1, height: OfficialUISpec.Geometry.px14)
                    Text(summary)
                        .font(OfficialUISpec.Typography.xs13)
                        .foregroundStyle(OfficialUISpec.Token.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, OfficialUISpec.Spacing.p8)
            }
            .buttonStyle(.plain)
            .disabled(!isExpandable)
            .accessibilityLabel(OfficialUISpec.Text.compactionTitle)
            .accessibilityValue(summary)

            if expanded, let summary = compaction.summary {
                NativeMarkdownText(markdown: summary, streaming: false)
                    .padding(OfficialUISpec.Spacing.p12)
                    .background(
                        OfficialUISpec.Token.elevated,
                        in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
