import Foundation
import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassSpec
#endif

private struct NativeProducedFilesLaneWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NativeProducedFilesChipWidthsKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

private struct NativeProducedFilesMoreWidthsKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

/// Pure RC8 `fitProducedFiles` equivalent. `moreWidthsByHidden` uses the
/// remaining-file count as its key so native measurement retains the exact
/// singular/plural localized width that the official browser tests.
enum NativeProducedFilesLayout {
    static func shouldRender(paths: [String]) -> Bool { !paths.isEmpty }

    static func shownCount(
        available: CGFloat,
        chipWidths: [CGFloat],
        moreWidthsByHidden: [Int: CGFloat],
        totalCount: Int,
        gap: CGFloat
    ) -> Int {
        guard available > 0 else { return chipWidths.count }
        var prefixWidths = [CGFloat(0)]
        for width in chipWidths {
            prefixWidths.append(prefixWidths.last! + width)
        }
        var largestFit = 0
        for shown in prefixWidths.indices {
            let hidden = totalCount - shown
            let more = hidden > 0 ? moreWidthsByHidden[hidden] : nil
            // Measurement has not settled yet; preserve the official initial
            // six-chip cap rather than transiently hiding an unknown prefix.
            if hidden > 0, more == nil { return chipWidths.count }
            let itemCount = shown + (more == nil ? 0 : 1)
            let needed = prefixWidths[shown] + (more ?? 0) + max(0, CGFloat(itemCount - 1)) * gap
            if needed <= available { largestFit = shown }
        }
        return largestFit
    }
}

/// Native RC8 `ProducedFiles` turn tail. Paths originate solely from the
/// reducer-owned `deliverables` turn location rather than closing assistant
/// prose. The measured lane mirrors the official 0–6 visible-chip fit.
struct NativeProducedFiles: View {
    let paths: [String]
    let open: (String) -> Void
    /// rc.1 directory disclosure is gated by the authenticated
    /// `session/canOpenWorkspacePath` capability. Snapshot and disconnected
    /// callers remain fail-closed.
    let canShowInFolder: Bool

    private let shownLimit = 6
    @State private var laneWidth: CGFloat = 0
    @State private var chipWidths: [String: CGFloat] = [:]
    @State private var moreWidths: [Int: CGFloat] = [:]

    private var candidates: [String] { Array(paths.prefix(shownLimit)) }

    private var shownCount: Int {
        let widths = candidates.map { chipWidths[$0] ?? 0 }
        guard widths.allSatisfy({ $0 > 0 }) else { return candidates.count }
        return NativeProducedFilesLayout.shownCount(
            available: laneWidth,
            chipWidths: widths,
            moreWidthsByHidden: moreWidths,
            totalCount: paths.count,
            gap: OfficialUISpec.Spacing.p8
        )
    }

    private var shown: ArraySlice<String> { candidates.prefix(shownCount) }
    private var hiddenCount: Int { max(0, paths.count - shown.count) }

    private var measuredHiddenCounts: [Int] {
        Array(Set((0 ... candidates.count).compactMap { shown in
            let hidden = paths.count - shown
            return hidden > 0 ? hidden : nil
        })).sorted()
    }

    var body: some View {
        Group {
            if NativeProducedFilesLayout.shouldRender(paths: paths) {
                Grid(alignment: .leading, horizontalSpacing: OfficialUISpec.Spacing.p8, verticalSpacing: OfficialUISpec.Spacing.p6) {
            GridRow {
                Text(OfficialUISpec.Text.producedFiles)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
                    .fixedSize(horizontal: true, vertical: false)
                fileLane
            }
            if hiddenCount > 0, canShowInFolder {
                GridRow {
                    Color.clear
                        .frame(width: 0, height: 0)
                    Button { open(".") } label: {
                        Text(OfficialUISpec.Text.producedFilesShowInFolder)
                    }
                    .buttonStyle(.plain)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
                    .padding(.horizontal, OfficialUISpec.Spacing.p2)
                    .accessibilityLabel(OfficialUISpec.Text.producedFilesShowInFolder)
                }
            }
                }
                .padding(.top, OfficialUISpec.Spacing.p16)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(OfficialUISpec.Text.producedFiles)
            }
        }
    }

    private var fileLane: some View {
        HStack(spacing: OfficialUISpec.Spacing.p8) {
            ForEach(Array(shown), id: \.self) { path in
                Button { open(path) } label: {
                    fileChipLabel(path)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(OfficialUISpec.Text.producedFilesOpen(name: path))
                // RC8 keeps the full path as the duplicate-basename
                // disambiguator while rendering only the short basename.
                .help(path)
            }
            if hiddenCount > 0 {
                moreLabel(hiddenCount)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: NativeProducedFilesLaneWidthKey.self, value: proxy.size.width)
            }
        )
        .background(measurementProbes)
        .onPreferenceChange(NativeProducedFilesLaneWidthKey.self) { laneWidth = $0 }
        .onPreferenceChange(NativeProducedFilesChipWidthsKey.self) { chipWidths = $0 }
        .onPreferenceChange(NativeProducedFilesMoreWidthsKey.self) { moreWidths = $0 }
    }

    private var measurementProbes: some View {
        HStack(spacing: OfficialUISpec.Spacing.p0) {
            ForEach(candidates, id: \.self) { path in
                fileChipLabel(path)
                    .fixedSize()
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: NativeProducedFilesChipWidthsKey.self,
                                value: [path: proxy.size.width]
                            )
                        }
                    )
            }
            ForEach(measuredHiddenCounts, id: \.self) { hidden in
                moreLabel(hidden)
                    .fixedSize()
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: NativeProducedFilesMoreWidthsKey.self,
                                value: [hidden: proxy.size.width]
                            )
                        }
                    )
            }
        }
        // A background does not participate in the lane's layout. Keep these
        // probes intrinsically sized so their GeometryReader values equal the
        // visible controls, just as RC8's absolute hidden probe lane does.
        .fixedSize()
        .hidden()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func fileChipLabel(_ path: String) -> some View {
        Text(URL(fileURLWithPath: path).lastPathComponent)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: OfficialUISpec.Geometry.px320, alignment: .leading)
            .padding(.horizontal, OfficialUISpec.Spacing.p8)
            .font(OfficialUISpec.Typography.xs13)
            .foregroundStyle(OfficialUISpec.Token.secondary)
            .background(
                OfficialUISpec.Token.interactiveHover,
                in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r6, style: .continuous)
            )
    }

    private func moreLabel(_ hidden: Int) -> some View {
        Text(OfficialUISpec.Text.producedFilesMore(hidden))
            .font(OfficialUISpec.Typography.xs13)
            .foregroundStyle(OfficialUISpec.Token.caption)
    }
}
