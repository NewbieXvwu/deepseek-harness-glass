import Foundation
import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

/// Native RC8 `ProducedFiles` turn tail. Layout keeps the one-line chip lane
/// and the six-item cap; all paths originate from the reducer-owned
/// `deliverables` turn location rather than closing assistant prose.
struct NativeProducedFiles: View {
    let paths: [String]
    let open: (String) -> Void
    private let shownLimit = 6

    private var shown: ArraySlice<String> { paths.prefix(shownLimit) }
    private var hiddenCount: Int { max(0, paths.count - shown.count) }

    var body: some View {
        HStack(spacing: OfficialUISpec.Spacing.p8) {
            Text(OfficialUISpec.Text.producedFiles)
                .font(OfficialUISpec.Typography.xs13)
                .foregroundStyle(OfficialUISpec.Token.caption)
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                ForEach(Array(shown), id: \.self) { path in
                    Button { open(path) } label: {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, OfficialUISpec.Spacing.p8)
                    }
                    .buttonStyle(.plain)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .background(OfficialUISpec.Token.interactiveHover, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r6, style: .continuous))
                    .accessibilityLabel(OfficialUISpec.Text.producedFilesOpen(name: path))
                }
                if hiddenCount > 0 {
                    Text(OfficialUISpec.Text.producedFilesMore(hiddenCount))
                        .font(OfficialUISpec.Typography.xs13)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, OfficialUISpec.Spacing.p16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(OfficialUISpec.Text.producedFiles)
    }
}
