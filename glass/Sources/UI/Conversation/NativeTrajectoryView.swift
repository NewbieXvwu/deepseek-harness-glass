import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native base of RC8's separately registered `trajectory` target. The full web
/// view owns richer timing and details panes; this native stage keeps the same
/// toolbar vocabulary while consuming only target-owned typed input nodes and
/// already-materialized typed tool invocations.
struct NativeTrajectoryView: View {
    private enum LedgerMode: Hashable { case turns, calls }

    fileprivate struct TurnRecord: Identifiable {
        let node: CoreUserMessageNode
        var id: String { "turn-\(node.seq)" }
        var text: String { node.content.compactMap(\.text).joined(separator: "\n") }
    }

    @ObservedObject var sessionStore: NativeSessionStore
    @State private var mode: LedgerMode = .turns
    @State private var searchText = ""

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("") == .orderedSame
            ? ""
            : searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var turns: [TurnRecord] {
        sessionStore.trajectoryNodes.compactMap { node in
            guard node.visibility != .hidden,
                  let input = node.data as? CoreUserMessageNode
            else { return nil }
            let record = TurnRecord(node: input)
            guard !record.text.isEmpty else { return nil }
            return matches(record.text) ? record : nil
        }
    }

    private var calls: [NativeSessionStore.ToolInvocation] {
        sessionStore.toolInvocations.filter { invocation in
            matches(invocation.name) || matches(invocation.arguments)
        }
    }

    var body: some View {
        VStack(spacing: OfficialUISpec.Spacing.p0) {
            toolbar
            Divider().overlay(OfficialUISpec.Token.hairline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
                    switch mode {
                    case .turns:
                        ForEach(turns) { record in
                            NativeTrajectoryTurnRow(record: record)
                        }
                    case .calls:
                        ForEach(calls) { invocation in
                            NativeTrajectoryCallRow(invocation: invocation)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OfficialUISpec.Spacing.p16)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(OfficialUISpec.Text.trajectory)
    }

    private var toolbar: some View {
        HStack(spacing: OfficialUISpec.Spacing.p8) {
            Picker(OfficialUISpec.Text.trajectoryToolbar, selection: $mode) {
                Text(OfficialUISpec.Text.trajectoryTurns).tag(LedgerMode.turns)
                Text(OfficialUISpec.Text.trajectoryCalls).tag(LedgerMode.calls)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)

            TextField(OfficialUISpec.Text.trajectorySearchPlaceholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(OfficialUISpec.Text.trajectorySearch)
        }
        .padding(.horizontal, OfficialUISpec.Spacing.p16)
        .padding(.vertical, OfficialUISpec.Spacing.p8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(OfficialUISpec.Text.trajectoryToolbar)
    }

    private func matches(_ value: String) -> Bool {
        normalizedQuery.isEmpty || value.localizedCaseInsensitiveContains(normalizedQuery)
    }
}

private struct NativeTrajectoryTurnRow: View {
    let record: NativeTrajectoryView.TurnRecord

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
            Text(String(record.node.seq))
                .font(OfficialUISpec.Typography.xxxs11.monospaced())
                .foregroundStyle(OfficialUISpec.Token.caption)
            Text(record.text)
                .font(OfficialUISpec.Typography.s14)
                .foregroundStyle(OfficialUISpec.Token.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OfficialUISpec.Spacing.p12)
        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous)
                .stroke(OfficialUISpec.Token.hairline, lineWidth: OfficialUISpec.Geometry.px1)
        }
    }
}

private struct NativeTrajectoryCallRow: View {
    let invocation: NativeSessionStore.ToolInvocation

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                Text(String(invocation.sequence))
                    .font(OfficialUISpec.Typography.xxxs11.monospaced())
                    .foregroundStyle(OfficialUISpec.Token.caption)
                Text(invocation.name)
                    .font(OfficialUISpec.Typography.xsStrong13)
                    .foregroundStyle(OfficialUISpec.Token.primary)
                Spacer(minLength: 0)
            }
            Text(invocation.arguments)
                .font(OfficialUISpec.Typography.xs13.monospaced())
                .foregroundStyle(OfficialUISpec.Token.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OfficialUISpec.Spacing.p12)
        .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous)
                .stroke(OfficialUISpec.Token.hairline, lineWidth: OfficialUISpec.Geometry.px1)
        }
    }
}
