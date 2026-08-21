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
    @State private var selectedCallID: String?

    private var normalizedQuery: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
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

    private var selectedCall: NativeSessionStore.ToolInvocation? {
        calls.first(where: { $0.id == selectedCallID })
    }

    var body: some View {
        VStack(spacing: OfficialUISpec.Spacing.p0) {
            toolbar
            Divider().overlay(OfficialUISpec.Token.hairline)
            HStack(spacing: OfficialUISpec.Spacing.p0) {
                ledger
                if mode == .calls, let selectedCall {
                    Divider().overlay(OfficialUISpec.Token.hairline)
                    NativeTrajectoryCallDetail(invocation: selectedCall)
                        .frame(minWidth: 240, idealWidth: 320, maxWidth: 380)
                }
            }
        }
        .onChange(of: mode) { _, newMode in
            if newMode != .calls { selectedCallID = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(OfficialUISpec.Text.trajectory)
    }

    private var ledger: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
                switch mode {
                case .turns:
                    ForEach(turns) { record in
                        NativeTrajectoryTurnRow(record: record)
                    }
                case .calls:
                    ForEach(calls) { invocation in
                        NativeTrajectoryCallRow(
                            invocation: invocation,
                            selected: selectedCallID == invocation.id,
                            select: { selectedCallID = invocation.id }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OfficialUISpec.Spacing.p16)
        }
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
    let selected: Bool
    let select: () -> Void

    private var stateLabel: String {
        switch invocation.state {
        case .running:
            OfficialUISpec.Text.trajectoryPending
        case .completed:
            OfficialUISpec.Text.trajectoryCompleted
        case .failed:
            OfficialUISpec.Text.trajectoryFailed
        case .stopped:
            OfficialUISpec.Text.toolStopped
        }
    }

    private var stateColor: Color {
        switch invocation.state {
        case .running:
            OfficialUISpec.Token.warningPrimary
        case .completed:
            OfficialUISpec.Token.success
        case .failed, .stopped:
            OfficialUISpec.Token.errorPrimary
        }
    }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
                HStack(spacing: OfficialUISpec.Spacing.p8) {
                    Text(String(invocation.sequence))
                        .font(OfficialUISpec.Typography.xxxs11.monospaced())
                        .foregroundStyle(OfficialUISpec.Token.caption)
                    Text(invocation.name)
                        .font(OfficialUISpec.Typography.xsStrong13)
                        .foregroundStyle(OfficialUISpec.Token.primary)
                    Spacer(minLength: 0)
                    Text(stateLabel)
                        .font(OfficialUISpec.Typography.xxxs11)
                        .foregroundStyle(stateColor)
                }
                Text(invocation.arguments)
                    .font(OfficialUISpec.Typography.xs13.monospaced())
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OfficialUISpec.Spacing.p12)
        }
        .buttonStyle(.plain)
        .background(selected ? OfficialUISpec.Token.businessBlueSoft : OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous)
                .stroke(selected ? OfficialUISpec.Token.businessBlue : OfficialUISpec.Token.hairline, lineWidth: OfficialUISpec.Geometry.px1)
        }
        .accessibilityLabel("\(invocation.name) \(stateLabel)")
    }
}

private struct NativeTrajectoryCallDetail: View {
    private enum DetailTab: Hashable { case payload, result }

    let invocation: NativeSessionStore.ToolInvocation
    @State private var tab: DetailTab = .payload

    private var hasResult: Bool { invocation.output?.isEmpty == false }

    var body: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p8) {
            Text(OfficialUISpec.Text.trajectoryEventDetails)
                .font(OfficialUISpec.Typography.xsStrong13)
                .foregroundStyle(OfficialUISpec.Token.primary)
            Picker(OfficialUISpec.Text.trajectoryEventDetails, selection: $tab) {
                Text(OfficialUISpec.Text.trajectoryPayload).tag(DetailTab.payload)
                if hasResult {
                    Text(OfficialUISpec.Text.trajectoryResult).tag(DetailTab.result)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                Text(tab == .payload ? invocation.arguments : (invocation.output ?? ""))
                    .font(OfficialUISpec.Typography.xs13.monospaced())
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OfficialUISpec.Spacing.p12)
                    .background(OfficialUISpec.Token.elevated, in: RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r8, style: .continuous))
            }
        }
        .padding(OfficialUISpec.Spacing.p16)
        .onChange(of: invocation.id) { _, _ in
            tab = .payload
        }
        .onChange(of: invocation.output) { _, newOutput in
            if newOutput?.isEmpty != false { tab = .payload }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(OfficialUISpec.Text.trajectoryEventDetails)
    }
}
