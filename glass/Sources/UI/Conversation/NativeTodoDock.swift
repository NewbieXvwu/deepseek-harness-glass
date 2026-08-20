import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Pure RC8 TodoPanel decisions shared by the native dock and its regression
/// tests. The Host remains the only source of todo rows and checked state.
enum NativeTodoDockPresentation {
    static let startsCollapsed = true

    /// RC8 CSS uses a 1s linear in-progress spin. Reduce Motion returns nil so
    /// the glyph remains visible but statically oriented.
    static func progressSpinDuration(reduceMotion: Bool) -> Double? {
        reduceMotion ? nil : 1
    }

    static func isVisible(_ todos: [CoreTodoItem]?) -> Bool {
        !(todos?.isEmpty ?? true)
    }

    static func progressLabel(for todos: [CoreTodoItem]) -> String {
        let completed = todos.count { $0.status == .completed }
        let active = todos.count { $0.status == .inProgress }
        let pending = todos.count - completed - active
        return [
            completed > 0 ? OfficialUISpec.Text.todoProgressDone(completed) : nil,
            active > 0 ? OfficialUISpec.Text.todoProgressActive(active) : nil,
            pending > 0 ? OfficialUISpec.Text.todoProgressPending(pending) : nil
        ]
        .compactMap { $0 }
        .joined(separator: "\u{2002}·\u{2002}")
    }
}

/// Native equivalent of the RC8 `conversation.input.dock` TodoPanel. The view
/// deliberately owns only presentation collapse state; its todo values are a
/// Host replacement snapshot obtained from `SessionTodoProjectionReader`.
struct NativeTodoDock: View {
    let todos: [CoreTodoItem]
    @State private var collapsed = NativeTodoDockPresentation.startsCollapsed

    var body: some View {
        if NativeTodoDockPresentation.isVisible(todos) {
            VStack(spacing: OfficialUISpec.Layout.todoDockContentGap) {
                Button {
                    collapsed.toggle()
                } label: {
                    header
                }
                .buttonStyle(.plain)
                .accessibilityLabel(OfficialUISpec.Text.todoTitle)
                .accessibilityValue(NativeTodoDockPresentation.progressLabel(for: todos))

                if !collapsed {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: OfficialUISpec.Layout.todoDockContentGap) {
                            ForEach(todos, id: \.content) { item in
                                NativeTodoDockRow(item: item)
                            }
                        }
                    }
                    .frame(maxHeight: OfficialUISpec.Layout.todoDockListMaximumHeight)
                    .accessibilityElement(children: .contain)
                }
            }
            .padding(.horizontal, OfficialUISpec.Layout.todoDockHorizontalPadding)
            .padding(.vertical, OfficialUISpec.Layout.todoDockVerticalPadding)
            .frame(maxWidth: OfficialUISpec.Layout.composerMaximum - (OfficialUISpec.Layout.todoDockInset * 4))
            .background(OfficialUISpec.Token.specificTip, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.todoDockCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: OfficialUISpec.Layout.todoDockCornerRadius, style: .continuous)
                    .stroke(OfficialUISpec.Token.hairline, lineWidth: OfficialUISpec.Geometry.px1)
            }
        }
    }

    private var header: some View {
        HStack(spacing: OfficialUISpec.Layout.todoDockHeaderGap) {
            OfficialAssetImage(name: "icon-checklist", template: true)
                .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                .foregroundStyle(OfficialUISpec.Token.caption)
            Text(OfficialUISpec.Text.todoTitle)
                .font(OfficialUISpec.Typography.xsStrong13)
                .foregroundStyle(OfficialUISpec.Token.primary)
            Text(NativeTodoDockPresentation.progressLabel(for: todos))
                .font(OfficialUISpec.Typography.xs13)
                .foregroundStyle(OfficialUISpec.Token.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            OfficialAssetImage(name: "icon-chevron-down", template: true)
                .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                .foregroundStyle(OfficialUISpec.Token.caption)
                .rotationEffect(.degrees(collapsed ? 180 : 0))
        }
        .frame(minHeight: OfficialUISpec.Layout.todoDockCollapsedHeight)
        .contentShape(Rectangle())
    }
}

private struct NativeTodoDockRow: View {
    let item: CoreTodoItem

    var body: some View {
        HStack(spacing: OfficialUISpec.Layout.todoDockHeaderGap) {
            NativeTodoStatusGlyph(status: item.status)
                .frame(width: OfficialUISpec.Geometry.px16, height: OfficialUISpec.Geometry.px16)
            Text(item.content)
                .font(OfficialUISpec.Typography.xs13)
                .foregroundStyle(OfficialUISpec.Token.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.content)
        .accessibilityValue(item.status.accessibilityValue)
    }
}

private struct NativeTodoStatusGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: CoreTodoItem.Status
    @State private var progressDegrees = 0.0

    var body: some View {
        ZStack {
            switch status {
            case .completed:
                Circle()
                    .stroke(OfficialUISpec.Token.success, lineWidth: OfficialUISpec.Geometry.px1)
                OfficialAssetImage(name: "icon-check", template: true)
                    .frame(width: OfficialUISpec.Geometry.px12, height: OfficialUISpec.Geometry.px12)
                    .foregroundStyle(OfficialUISpec.Token.success)
            case .inProgress:
                Circle()
                    .trim(from: 0.08, to: 0.82)
                    .stroke(OfficialUISpec.Token.businessBlue, style: StrokeStyle(lineWidth: OfficialUISpec.Geometry.px1, lineCap: .round))
                    .rotationEffect(.degrees(progressDegrees))
            case .pending:
                Circle()
                    .stroke(OfficialUISpec.Token.caption, style: StrokeStyle(lineWidth: OfficialUISpec.Geometry.px1, dash: [2.4, 2.4]))
            }
        }
        .onAppear(perform: synchronizeMotion)
        .onChange(of: reduceMotion) { _, _ in
            synchronizeMotion()
        }
    }

    private func synchronizeMotion() {
        guard status == .inProgress else { return }
        guard let duration = NativeTodoDockPresentation.progressSpinDuration(reduceMotion: reduceMotion) else {
            progressDegrees = 0
            return
        }
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            progressDegrees = 360
        }
    }
}

private extension CoreTodoItem.Status {
    var accessibilityValue: String {
        switch self {
        case .completed: return OfficialUISpec.Text.todoProgressDone(1)
        case .inProgress: return OfficialUISpec.Text.todoProgressActive(1)
        case .pending: return OfficialUISpec.Text.todoProgressPending(1)
        }
    }
}
