import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// Native RC8 `subagent-catalog` header action. It is hidden until a complete
/// Host catalog supplies child/diagnostic evidence; ordinary session summaries
/// never manufacture a catalog row or recursive descendant.
struct NativeSubagentCatalogHeaderAction: View {
    @ObservedObject var sessionStore: NativeSessionStore
    let openSession: (String) -> Void
    @State private var open = false
    @State private var expandedParentIDs: Set<String> = []

    private var rootID: String? { sessionStore.selectedSessionID }
    private var rootCatalog: SubagentListResponse? { sessionStore.subagentCatalog }
    private var rootChildren: [SubagentListEntryDTO] { rootCatalog?.entries.filter { $0.kind == "child" } ?? [] }
    private var rootDiagnostics: [SubagentListEntryDTO] { rootCatalog?.entries.filter { $0.kind == "diagnostic" } ?? [] }
    private var runningCount: Int { rootChildren.filter { $0.activity == "running" }.count }
    private var visible: Bool {
        !rootChildren.isEmpty || !rootDiagnostics.isEmpty || (rootID.map(sessionStore.failedSubagentCatalogIDs.contains) ?? false)
    }

    var body: some View {
        Group {
            if visible {
                Button { open.toggle() } label: {
                    HStack(spacing: OfficialUISpec.Spacing.p4) {
                        if runningCount > 0 {
                            Circle().fill(OfficialUISpec.Token.businessBlue).frame(width: OfficialUISpec.Geometry.px8, height: OfficialUISpec.Geometry.px8)
                        }
                        Text(OfficialUISpec.Text.subagentTotalCount(rootChildren.count))
                        Image(systemName: "chevron.down")
                            .font(OfficialUISpec.Typography.xxxs11)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
                    .frame(minHeight: OfficialUISpec.Geometry.px28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(runningCount > 0 ? OfficialUISpec.Text.subagentRunningCount(runningCount) : OfficialUISpec.Text.subagentTotalCount(rootChildren.count))
                .popover(isPresented: $open, arrowEdge: .bottom) { catalogPopover }
            }
        }
        .onAppear { sessionStore.refreshSubagentCatalog() }
        .onChange(of: open) { _, isOpen in
            if !isOpen { expandedParentIDs = [] }
        }
    }

    private var catalogPopover: some View {
        VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p4) {
            Text(OfficialUISpec.Text.subagentTreeAccessibility)
                .font(OfficialUISpec.Typography.xsStrong13)
                .foregroundStyle(OfficialUISpec.Token.primary)
            if let rootID {
                catalogRows(parentID: rootID, entries: rootCatalog?.entries ?? [], depth: 0)
                catalogStateRow(parentID: rootID, depth: 0)
            }
        }
        .padding(OfficialUISpec.Spacing.p12)
        .frame(width: 336, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(OfficialUISpec.Text.subagentTreeAccessibility)
    }

    /// SwiftUI cannot infer a recursive opaque result on current macOS SDKs.
    /// Erasure is limited to the branch boundary; rows remain typed Host DTOs.
    private func catalogRows(parentID: String, entries: [SubagentListEntryDTO], depth: Int) -> AnyView {
        AnyView(ForEach(entries, id: \.id) { entry in
            if entry.kind == "child" {
                AnyView(VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p0) {
                    childRow(entry, parentID: parentID, depth: depth)
                    if entry.hasChildren == true, expandedParentIDs.contains(entry.id) {
                        let childEntries = sessionStore.subagentCatalogs[entry.id]?.entries ?? []
                        catalogRows(parentID: entry.id, entries: childEntries, depth: depth + 1)
                        catalogStateRow(parentID: entry.id, depth: depth + 1)
                    }
                })
            } else {
                AnyView(Text(entry.reason ?? OfficialUISpec.Text.subagentLoadError)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.errorPrimary)
                    .padding(.leading, OfficialUISpec.Spacing.p8 * CGFloat(depth))
                    .padding(OfficialUISpec.Spacing.p8))
            }
        })
    }

    @ViewBuilder
    private func catalogStateRow(parentID: String, depth: Int) -> some View {
        if sessionStore.loadingSubagentCatalogIDs.contains(parentID) {
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                ProgressView().controlSize(.small)
                Text(OfficialUISpec.Text.subagentLoading)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.caption)
            }
            .padding(.leading, OfficialUISpec.Spacing.p8 * CGFloat(depth))
            .padding(OfficialUISpec.Spacing.p8)
            .accessibilityLabel(OfficialUISpec.Text.subagentLoadingAccessibility)
        } else if sessionStore.failedSubagentCatalogIDs.contains(parentID) {
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                Text(OfficialUISpec.Text.subagentLoadError)
                    .font(OfficialUISpec.Typography.xs13)
                    .foregroundStyle(OfficialUISpec.Token.errorPrimary)
                Spacer(minLength: 0)
                Button {
                    sessionStore.refreshSubagentCatalog(parentSessionID: parentID)
                } label: {
                    HStack(spacing: OfficialUISpec.Spacing.p4) {
                        Image(systemName: "arrow.clockwise")
                        Text(OfficialUISpec.Text.subagentRetry)
                    }
                    .font(OfficialUISpec.Typography.xs13)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(OfficialUISpec.Text.subagentRetry)
            }
            .padding(.leading, OfficialUISpec.Spacing.p8 * CGFloat(depth))
            .padding(OfficialUISpec.Spacing.p8)
        }
    }

    @ViewBuilder
    private func childRow(_ entry: SubagentListEntryDTO, parentID: String, depth: Int) -> some View {
        HStack(spacing: OfficialUISpec.Spacing.p4) {
            if entry.hasChildren == true {
                Button {
                    toggleBranch(entry.id)
                } label: {
                    Image(systemName: expandedParentIDs.contains(entry.id) ? "chevron.down" : "chevron.right")
                        .font(OfficialUISpec.Typography.xxxs11)
                        .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
            }
            Button {
                let parentAvailable = sessionStore.subagentCatalogs[parentID]?.parentAvailable ?? false
                sessionStore.setSubagentRoute(parentSessionID: parentID, entry: entry, parentAvailable: parentAvailable)
                open = false
                openSession(entry.id)
            } label: {
                VStack(alignment: .leading, spacing: OfficialUISpec.Spacing.p2) {
                    HStack(spacing: OfficialUISpec.Spacing.p8) {
                        Circle().fill(entry.activity == "running" ? OfficialUISpec.Token.businessBlue : OfficialUISpec.Token.caption).frame(width: OfficialUISpec.Geometry.px6, height: OfficialUISpec.Geometry.px6)
                        Text(entry.label ?? entry.id).font(OfficialUISpec.Typography.xs13)
                        Spacer(minLength: 0)
                    }
                    Text(OfficialUISpec.Text.subagentDetail(mode: entry.mode, activity: entry.activity))
                        .font(OfficialUISpec.Typography.xxxs11)
                        .foregroundStyle(OfficialUISpec.Token.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OfficialUISpec.Spacing.p8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.label ?? entry.id)
        }
        .padding(.leading, OfficialUISpec.Spacing.p8 * CGFloat(depth))
    }

    private func toggleBranch(_ parentID: String) {
        if expandedParentIDs.contains(parentID) {
            expandedParentIDs.remove(parentID)
        } else {
            expandedParentIDs.insert(parentID)
            sessionStore.refreshSubagentCatalog(parentSessionID: parentID)
        }
    }
}
