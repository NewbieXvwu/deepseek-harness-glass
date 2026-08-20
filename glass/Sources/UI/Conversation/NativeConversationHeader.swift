import SwiftUI

#if DEEPSEEK_HARNESS_PACKAGE
@testable import GlassCore
@testable import GlassSpec
#endif

/// One registered native conversation view. The shape mirrors RC8
/// `contract/views.ts:ViewTab`; only renderable native entries are listed.
struct NativeConversationViewTab: Identifiable, Equatable {
    let id: String
    let label: String
}

/// Presentation-only projection of the strict RC8 session header. Its inputs
/// are the Host-authoritative session list snapshot and Core-owned session
/// state; it never reparses event payloads or owns durable session metadata.
struct NativeSessionHeaderPresentation: Equatable {
    struct Breadcrumb: Identifiable, Equatable {
        let id: String
        let title: String
    }

    let sessionID: String?
    let breadcrumbs: [Breadcrumb]
    let blank: Bool
    let composerIsBlank: Bool
    let agentPreset: String?
    let tabs: [NativeConversationViewTab]
    let activeTab: NativeConversationViewTab?

    /// RC8 `ConversationSessionHeader.hideChrome`: a truly blank session keeps
    /// the hero/composer resident but removes the header from layout.
    var hidesChrome: Bool { blank && composerIsBlank }

    init(
        snapshot: NativeWorkspaceStore.Snapshot,
        sessionID: String?,
        composerIsBlank: Bool,
        selectedViewID: String?,
        viewRegistry: NativeConversationViewRegistry
    ) {
        self.sessionID = sessionID
        self.composerIsBlank = composerIsBlank
        let sessionByID = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.sessionId, $0) })
        let selected = sessionID.flatMap { sessionByID[$0] }
        blank = selected?.blank ?? false
        agentPreset = selected?.agentPreset
        tabs = viewRegistry.registeredTabs
        activeTab = viewRegistry.resolve(selectedID: selectedViewID)
        breadcrumbs = Self.deriveAncestry(
            sessionByID: sessionByID,
            selectedSessionID: sessionID
        )
    }

    /// Source: RC8 `ConversationSession.deriveAncestry`. Only a subagent
    /// summary climbs `parentSessionId`; arbitrary parent pointers never become
    /// a user-visible hierarchy on their own.
    private static func deriveAncestry(
        sessionByID: [String: SessionSummaryDTO],
        selectedSessionID: String?
    ) -> [Breadcrumb] {
        guard var cursor = selectedSessionID else { return [] }
        var chain: [Breadcrumb] = []
        var seen = Set<String>()

        while seen.insert(cursor).inserted, let summary = sessionByID[cursor] {
            chain.insert(
                Breadcrumb(id: summary.sessionId, title: summary.displayTitle ?? summary.sessionId),
                at: 0
            )
            guard summary.origin == "subagent", let parent = summary.parentSessionId else { break }
            cursor = parent
        }
        return chain
    }
}

/// Strict native counterpart of RC8 `ConversationSessionHeader`. It owns
/// breadcrumb/title/tabs and composes additive actions independently; the
/// resident root remains responsible for the scroll body and composer seat.
struct NativeConversationHeader: View {
    let presentation: NativeSessionHeaderPresentation
    let jobs: [NativeSessionStore.BackgroundJob]
    let jobsPopoverInitiallyOpen: Bool
    let jobsLanguageCode: String?
    let contributionContext: NativeConversationContributionContext
    @ObservedObject var headerContributions: NativeConversationHeaderContributionRegistry
    let openSession: (String) -> Void
    let selectView: (String) -> Void

    var body: some View {
        if !presentation.hidesChrome {
            VStack(spacing: OfficialUISpec.Spacing.p0) {
                HStack(spacing: OfficialUISpec.Spacing.p0) {
                    HStack(spacing: OfficialUISpec.Spacing.p10) {
                        breadcrumbRow
                        headerActions
                    }
                    Spacer(minLength: OfficialUISpec.Spacing.p0)
                    headerUtilities
                }
                .frame(minHeight: OfficialUISpec.Layout.sessionHeaderTitleRowHeight)

                if presentation.tabs.count > 1 {
                    tabRow
                }
            }
            .padding(.top, OfficialUISpec.Layout.sessionHeaderTopPadding)
            .padding(.leading, OfficialUISpec.Layout.sessionHeaderLeadingPadding)
            .padding(.trailing, OfficialUISpec.Layout.sessionHeaderTrailingPadding)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(OfficialUISpec.Token.hairline)
                    .frame(height: OfficialUISpec.Geometry.px1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(OfficialUISpec.Text.sessionHierarchy)
        }
    }

    private var breadcrumbRow: some View {
        HStack(spacing: OfficialUISpec.Spacing.p4) {
            if presentation.breadcrumbs.isEmpty, let sessionID = presentation.sessionID {
                Text(sessionID)
                    .font(OfficialUISpec.Typography.sStrong14)
                    .foregroundStyle(OfficialUISpec.Token.primary)
            } else {
                ForEach(Array(presentation.breadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                    if index > 0 {
                        Text(OfficialUISpec.Text.sessionHierarchySeparator)
                            .font(OfficialUISpec.Typography.s14)
                            .foregroundStyle(OfficialUISpec.Token.caption)
                    }
                    Button(action: { openSession(crumb.id) }) {
                        Text(crumb.title)
                            .font(OfficialUISpec.Typography.s14)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, OfficialUISpec.Spacing.p8)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == presentation.breadcrumbs.count - 1)
                    .foregroundStyle(
                        index == presentation.breadcrumbs.count - 1
                            ? OfficialUISpec.Token.primary
                            : OfficialUISpec.Token.secondary
                    )
                    .accessibilityLabel(crumb.title)
                }
            }
        }
        .frame(maxWidth: 220, alignment: .leading)
    }

    @ViewBuilder
    private var headerActions: some View {
        HStack(spacing: OfficialUISpec.Spacing.p8) {
            if let preset = presentation.agentPreset {
                NativeSessionAgentPresetLabel(presetID: preset)
            }
            NativeJobsHeaderAction(
                jobs: jobs,
                initiallyOpen: jobsPopoverInitiallyOpen,
                languageCode: jobsLanguageCode
            )
            ForEach(Array(headerContributions.render(slot: .actions, context: contributionContext).enumerated()), id: \.offset) { _, view in
                view
            }
        }
    }

    @ViewBuilder
    private var headerUtilities: some View {
        let utilities = headerContributions.render(slot: .utilities, context: contributionContext)
        if !utilities.isEmpty {
            HStack(spacing: OfficialUISpec.Spacing.p8) {
                ForEach(Array(utilities.enumerated()), id: \.offset) { _, view in
                    view
                }
            }
            .padding(.leading, OfficialUISpec.Spacing.p20)
        }
    }

    private var tabRow: some View {
        HStack(spacing: OfficialUISpec.Layout.sessionHeaderTabGap) {
            ForEach(presentation.tabs) { tab in
                let active = tab.id == presentation.activeTab?.id
                Button(action: { selectView(tab.id) }) {
                    Text(tab.label)
                        .font(OfficialUISpec.Typography.xsStrong13)
                        .foregroundStyle(active ? OfficialUISpec.Token.businessBlue : OfficialUISpec.Token.secondary)
                        .padding(.bottom, OfficialUISpec.Layout.sessionHeaderTabBottomPadding)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(active ? OfficialUISpec.Token.businessBlue : Color.clear)
                                .frame(height: OfficialUISpec.Layout.sessionHeaderActiveBarHeight)
                                .clipShape(RoundedRectangle(cornerRadius: OfficialUISpec.Radius.r2, style: .continuous))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .frame(height: OfficialUISpec.Layout.sessionHeaderTabStripHeight, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, OfficialUISpec.Layout.sessionHeaderTabLeadingPadding)
        .accessibilityElement(children: .contain)
    }
}

/// RC8 `AgentPresetLabel` display fallback. The stable built-in `standard`
/// maps through the generated agent-preset locale. Unknown Host ids remain
/// addressing strings, matching upstream when roster metadata is unavailable.
private struct NativeSessionAgentPresetLabel: View {
    let presetID: String

    private var displayName: String {
        presetID == "standard" ? OfficialUISpec.Text.standardMode : presetID
    }

    var body: some View {
        HStack(spacing: OfficialUISpec.Spacing.p4) {
            OfficialAssetImage(name: "icon-agent-preset", template: true)
                .frame(width: OfficialUISpec.Geometry.px14, height: OfficialUISpec.Geometry.px14)
            Text(displayName)
                .font(OfficialUISpec.Typography.s14)
                .lineLimit(1)
        }
        .foregroundStyle(OfficialUISpec.Token.secondary)
        .accessibilityLabel(displayName)
    }
}
