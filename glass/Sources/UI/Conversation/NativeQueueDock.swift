import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

enum NativeQueueDockPresentation {
    static func queuedRows(_ rows: [NativeSessionStore.QueuedMessage]) -> [NativeSessionStore.QueuedMessage] {
        rows.filter { $0.placement == .queued }
    }

    static func isMutable(_ subagent: CoreSubagentIdentityProjection) -> Bool {
        // RC8 grants queue verbs only when the session snapshot explicitly says
        // `subagent === null`; missing/malformed descriptors fail closed.
        subagent == .noValidDescriptor
    }

    static func failureText(_ failure: NativeSessionStore.QueueActionFailure?, rowID: String) -> String? {
        guard let failure, failure.itemID == rowID else { return nil }
        switch failure.kind {
        case .edit: OfficialUISpec.Text.queueEditFailure
        case .remove: OfficialUISpec.Text.queueRemoveFailure
        case .steer: OfficialUISpec.Text.queueSteerFailure
        }
    }
}

/// Native RC8 `conversation.input.dock` QueueDock. Rows are complete Host
/// `session/queue` snapshots. This view owns only collapse/edit draft state.
struct NativeQueueDock: View {
    let rows: [NativeSessionStore.QueuedMessage]
    let isRunning: Bool
    let isMutable: Bool
    let busyItemID: String?
    let failure: NativeSessionStore.QueueActionFailure?
    let completion: NativeSessionStore.QueueActionCompletion?
    let update: (String, SessionQueueAction) -> Void

    @State private var collapsed = true
    @State private var editingItemID: String?
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    private var queue: [NativeSessionStore.QueuedMessage] { NativeQueueDockPresentation.queuedRows(rows) }
    private var interactionActive: Bool { isMutable && (editingItemID != nil || busyItemID != nil) }
    private var expanded: Bool { !collapsed || interactionActive }
    private var listVisible: Bool { queue.count == 1 || expanded }

    var body: some View {
        if !queue.isEmpty {
            VStack(spacing: OfficialUISpec.Spacing.p0) {
                if queue.count > 1 { header }
                if listVisible {
                    ScrollView {
                        LazyVStack(spacing: OfficialUISpec.Spacing.p0) {
                            ForEach(queue) { row in queueRow(row) }
                        }
                    }
                    .frame(maxHeight: OfficialUISpec.Layout.todoDockListMaximumHeight)
                }
            }
            .frame(maxWidth: OfficialUISpec.Layout.composerMaximum - (OfficialUISpec.Layout.todoDockInset * 2))
            .padding(.horizontal, OfficialUISpec.Layout.todoDockInset)
            .padding(.vertical, OfficialUISpec.Geometry.px2)
            .background(OfficialUISpec.Token.specificTip, in: UnevenRoundedRectangle(topLeadingRadius: OfficialUISpec.Layout.goalDockCornerRadius, topTrailingRadius: OfficialUISpec.Layout.goalDockCornerRadius))
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: OfficialUISpec.Layout.goalDockCornerRadius, topTrailingRadius: OfficialUISpec.Layout.goalDockCornerRadius)
                    .stroke(OfficialUISpec.Token.hairline, lineWidth: OfficialUISpec.Geometry.px1)
                    .mask(Rectangle().padding(.bottom, -OfficialUISpec.Geometry.px1))
            }
            .onChange(of: queue.map(\.id)) { _, ids in
                if ids.isEmpty { collapsed = true }
                if let editingItemID, !ids.contains(editingItemID) { cancelEdit() }
            }
            .onChange(of: completion) { _, completion in
                guard let completion, completion.itemID == editingItemID else { return }
                if case .edit = completion.action { cancelEdit() }
            }
        }
    }

    private var header: some View {
        Button { collapsed.toggle() } label: {
            HStack(spacing: OfficialUISpec.Layout.goalDockContentGap) {
                OfficialAssetImage(name: "icon-queue", template: true)
                    .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                    .foregroundStyle(OfficialUISpec.Token.caption)
                Text(OfficialUISpec.Text.queueCount(queue.count))
                    .font(OfficialUISpec.Typography.xsStrong13)
                    .foregroundStyle(OfficialUISpec.Token.primary)
                Spacer(minLength: 0)
                OfficialAssetImage(name: "icon-chevron-down", template: true)
                    .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                    .rotationEffect(.degrees(expanded ? 0 : 180))
                    .foregroundStyle(OfficialUISpec.Token.caption)
            }
            .frame(height: OfficialUISpec.Layout.goalDockHeight)
            .padding(.horizontal, OfficialUISpec.Layout.todoDockHorizontalPadding)
        }
        .buttonStyle(.plain)
        .disabled(interactionActive)
        .accessibilityLabel(OfficialUISpec.Text.queueCount(queue.count))
    }

    @ViewBuilder
    private func queueRow(_ row: NativeSessionStore.QueuedMessage) -> some View {
        HStack(spacing: OfficialUISpec.Layout.goalDockContentGap) {
            if queue.count == 1 {
                OfficialAssetImage(name: "icon-queue", template: true)
                    .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            }
            if editingItemID == row.id {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(OfficialUISpec.Typography.xs13)
                    .focused($editorFocused)
                    .frame(height: OfficialUISpec.Layout.goalDockIconControl)
                    .padding(.horizontal, OfficialUISpec.Spacing.p8)
                    .background(OfficialUISpec.Token.base, in: RoundedRectangle(cornerRadius: OfficialUISpec.Layout.goalDockInputCornerRadius, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: OfficialUISpec.Layout.goalDockInputCornerRadius, style: .continuous).stroke(OfficialUISpec.Token.border, lineWidth: OfficialUISpec.Geometry.px1) }
                    .onSubmit { save(row) }
                    .onExitCommand { cancelEdit() }
                    .accessibilityLabel(OfficialUISpec.Text.queueEditAccessibility)
            } else {
                Text(row.preview)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let text = NativeQueueDockPresentation.failureText(failure, rowID: row.id) {
                Text(text).font(OfficialUISpec.Typography.xxs12).foregroundStyle(OfficialUISpec.Token.errorPrimary).lineLimit(1).truncationMode(.tail).accessibilityLabel(text)
            }
            Spacer(minLength: 0)
            if isMutable { actionControls(row) }
        }
        .frame(minHeight: OfficialUISpec.Layout.goalDockHeight)
        .padding(.leading, OfficialUISpec.Layout.goalDockLeadingPadding)
        .padding(.trailing, OfficialUISpec.Layout.goalDockTrailingPadding)
        .overlay(alignment: .top) {
            if row.id != queue.first?.id { Divider().overlay(OfficialUISpec.Token.hairline) }
        }
    }

    @ViewBuilder
    private func actionControls(_ row: NativeSessionStore.QueuedMessage) -> some View {
        if editingItemID == row.id {
            actionButton(asset: "icon-check", label: OfficialUISpec.Text.queueSaveAccessibility, enabled: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { save(row) }
            actionButton(asset: "icon-close", label: OfficialUISpec.Text.queueCancelEditAccessibility, action: cancelEdit)
        } else {
            actionButton(asset: "icon-tool-edit", label: OfficialUISpec.Text.queueEditAccessibility, enabled: row.text != nil, help: row.text == nil ? OfficialUISpec.Text.queueEditUnsupported : nil) {
                guard let text = row.text else { return }
                draft = text; editingItemID = row.id; editorFocused = true
            }
            actionButton(asset: "icon-trash", label: OfficialUISpec.Text.queueRemoveAccessibility) { update(row.id, .remove) }
            actionButton(asset: "icon-send-up", label: OfficialUISpec.Text.queueSteerAccessibility, enabled: isRunning, help: isRunning ? nil : OfficialUISpec.Text.queueSteerUnavailable) { update(row.id, .steer) }
        }
    }

    private func actionButton(asset: String, label: String, enabled: Bool = true, help: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            OfficialAssetImage(name: asset, template: true)
                .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                .frame(width: OfficialUISpec.Layout.goalDockIconControl, height: OfficialUISpec.Layout.goalDockIconControl)
        }
        .buttonStyle(NativeQueueActionButtonStyle())
        .disabled(busyItemID != nil || !enabled)
        .accessibilityLabel(label)
        .help(help ?? "")
    }

    private func save(_ row: NativeSessionStore.QueuedMessage) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, busyItemID == nil else { return }
        update(row.id, .edit(content: [.text(text: draft)]))
    }

    private func cancelEdit() {
        guard busyItemID == nil else { return }
        editingItemID = nil; draft = ""; editorFocused = false
    }
}

private struct NativeQueueActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(OfficialUISpec.Token.caption)
            .background(configuration.isPressed ? OfficialUISpec.Token.interactiveHover : .clear, in: Circle())
            .contentShape(Circle())
    }
}
