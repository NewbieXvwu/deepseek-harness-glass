import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Initial RC8 `subagent-catalog` header action. It is intentionally hidden
/// until a complete Host catalog supplies evidence of children or diagnostics;
/// no ordinary session summary is used to invent descendants.
struct NativeSubagentCatalogHeaderAction: View {
    @ObservedObject var sessionStore: NativeSessionStore
    @State private var open = false

    private var catalog: SubagentListResponse? { sessionStore.subagentCatalog }
    private var children: [SubagentListEntryDTO] { catalog?.entries.filter { $0.kind == "child" } ?? [] }
    private var diagnostics: [SubagentListEntryDTO] { catalog?.entries.filter { $0.kind == "diagnostic" } ?? [] }
    private var runningCount: Int { children.filter { $0.activity == "running" }.count }
    private var visible: Bool { !children.isEmpty || !diagnostics.isEmpty }

    var body: some View {
        Group {
            if visible {
                Button { open.toggle() } label: {
                    HStack(spacing: OfficialUISpec.Spacing.p4) {
                        if runningCount > 0 {
                            Circle().fill(OfficialUISpec.Token.businessBlue).frame(width: OfficialUISpec.Geometry.px8, height: OfficialUISpec.Geometry.px8)
                        }
                        Text(OfficialUISpec.Text.subagentTotalCount(children.count))
                        Image(systemName: "chevron.down")
                            .font(OfficialUISpec.Typography.xxxs11)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
                    .frame(minHeight: OfficialUISpec.Geometry.px28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(runningCount > 0 ? OfficialUISpec.Text.subagentRunningCount(runningCount) : OfficialUISpec.Text.subagentTotalCount(children.count))
                .popover(isPresented: $open, arrowEdge: .bottom) {
                    catalogPopover
                }
            }
        }
        .onAppear { sessionStore.refreshSubagentCatalog() }
    }

    private var catalogPopover: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
            Text(OfficialUISpec.Text.subagentTreeAccessibility)
                .font(OfficialUISpec.Typography.xsStrong13)
                .foregroundStyle(OfficialUISpec.Token.primary)
            ForEach(children, id: \.id) { entry in
                VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p2) {
                    HStack(spacing: OfficialUISpec.Spacing.p8) {
                        Circle().fill(entry.activity == "running" ? OfficialUISpec.Token.businessBlue : OfficialUISpec.Token.caption).frame(width: OfficialUISpec.Geometry.px6, height: OfficialUISpec.Geometry.px6)
                        Text(entry.label ?? entry.id).font(OfficialUISpec.Typography.xs13)
                        Spacer(minLength: 0)
                    }
                    Text("\(entry.mode == "one-shot" ? OfficialUISpec.Text.subagentModeOneShot : OfficialUISpec.Text.subagentModeContinuable) · \(entry.activity == "running" ? OfficialUISpec.Text.subagentRunning : OfficialUISpec.Text.subagentInactive)")
                        .font(OfficialUISpec.Typography.xxxs11)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                }
                .padding(OfficialUISpec.Spacing.p8)
            }
            ForEach(diagnostics, id: \.id) { entry in
                Text(entry.reason ?? OfficialUISpec.Text.subagentLoadError)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.errorPrimary)
                    .padding(OfficialUISpec.Spacing.p8)
            }
        }
        .padding(OfficialUISpec.Spacing.p12)
        .frame(width: 336, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(OfficialUISpec.Text.subagentTreeAccessibility)
    }
}
