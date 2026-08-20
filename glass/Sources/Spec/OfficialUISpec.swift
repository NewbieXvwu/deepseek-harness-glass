import SwiftUI

/// 已锁定 DeepSeek Harness WebUI 基线的原生规格。
/// 首屏文本、token 和布局值只来自该基线的 locale/CSS/组件源码，禁止由 View 自行创造产品文案。
enum OfficialUISpec {
    static let deepSeekHarnessCommit = Build.sourceCommit
    static let hostBuildID = Build.id
    /// Source: RC8 `SidebarRoot.tsx` uses `DSH_CLIENT_COMMIT_HASH` in its
    /// fallback brand slot. The native fixed-build client projects the same
    /// locked source revision rather than accepting runtime-provided copy.
    static var sidebarBuildRevision: String { String(Build.sourceCommit.prefix(7)) }

    enum Layout {
        // Source: packages/client/ui-layout/src/client/columns.ts
        static let sidebarDefault: CGFloat = 280
        static let sidebarMinimum: CGFloat = 264
        static let sidebarMaximum: CGFloat = 420
        static let sidebarCollapsed: CGFloat = 56
        static let sidebarAutoCollapse: CGFloat = 1024
        static let centerMinimum: CGFloat = 640
        static let detailsDefault: CGFloat = 360
        static let detailsMinimum: CGFloat = 300
        static let detailsMaximum: CGFloat = 520

        // Source: ConversationRoot.module.css / HeroShell.module.css / InputBar.module.css
        static let chatContentMaximum: CGFloat = 748
        static let composerMaximum: CGFloat = 780
        static let composerClearance: CGFloat = 16
        static let composerSeatTrailingGutter: CGFloat = 8
        static let composerControlHeight: CGFloat = 28
        static let composerCornerRadius: CGFloat = 22
        // Source: packages/client/ui-conversation/src/client/skeleton/TodoPanel.module.css
        static let todoDockCornerRadius: CGFloat = 12
        static let todoDockCollapsedHeight: CGFloat = 36
        static let todoDockHorizontalPadding: CGFloat = 12
        static let todoDockVerticalPadding: CGFloat = 6
        static let todoDockContentGap: CGFloat = 8
        static let todoDockHeaderGap: CGFloat = 10
        static let todoDockListMaximumHeight: CGFloat = 180
        static let todoDockInset: CGFloat = 8
        // Source: packages/client/ui-goal/src/client/GoalBar.module.css
        static let goalDockHeight: CGFloat = 36
        static let goalDockCornerRadius: CGFloat = 12
        static let goalDockLeadingPadding: CGFloat = 12
        static let goalDockTrailingPadding: CGFloat = 5
        static let goalDockVerticalPadding: CGFloat = 4
        static let goalDockContentGap: CGFloat = 10
        static let goalDockIconControl: CGFloat = 28
        static let goalDockInputHeight: CGFloat = 26
        static let goalDockInputCornerRadius: CGFloat = 6
        static let heroGap: CGFloat = 12
        // Source: ui-conversation/chat/ChatView.module.css + MessageItem.module.css
        static let chatMessageGap: CGFloat = 16
        static let chatTranscriptInset: CGFloat = 16
        static let chatTranscriptSideClearance: CGFloat = 32
        static let chatUserMessageMaximum: CGFloat = 525
        static let chatMessageCornerRadius: CGFloat = 22
        static let chatMessageActionSize: CGFloat = 28
        static let chatMessageActionGap: CGFloat = 10
        static let chatRunningStatusHeight: CGFloat = 26
        static let sidebarInlinePadding: CGFloat = 12
        // Source: packages/client/ui-primitives/src/BrandWordmark.tsx → official SVG viewBox.
        static let sidebarWordmarkWidth: CGFloat = 182
        static let sidebarWordmarkHeight: CGFloat = 24
        // Source: packages/client/ui-sidebar/src/client/SidebarRoot.module.css
        static let sidebarLogoRowHeight: CGFloat = 60
        static let sidebarBrandMarkSize: CGFloat = 24
        static let sidebarBuildBadgeHeight: CGFloat = 16
        static let sidebarNewSessionHeight: CGFloat = 38
        /// RC8 WindowServer paired measurement for NSSplitViewItem.sidebar.
        static let sidebarNativeExpandedLeadingInset: CGFloat = 5
        /// RC8 paired footer measurement: the injected Settings slot needs the
        /// same effective 12px official leading axis after its AppKit label
        /// composition, five points beyond the shell's upper-content inset.
        static let sidebarNativeExpandedFooterLeadingAdjustment: CGFloat = 5

        // Source: packages/client/ui-conversation/src/client/skeleton/ConversationRoot.module.css
        static let sessionHeaderTopPadding: CGFloat = 12
        static let sessionHeaderLeadingPadding: CGFloat = 20
        static let sessionHeaderTrailingPadding: CGFloat = 28
        static let sessionHeaderTitleRowHeight: CGFloat = 32
        static let sessionHeaderTabStripHeight: CGFloat = 35
        static let sessionHeaderTabGap: CGFloat = 36
        static let sessionHeaderTabLeadingPadding: CGFloat = 8
        static let sessionHeaderTabBottomPadding: CGFloat = 11
        static let sessionHeaderActiveBarHeight: CGFloat = 2

        // Source: packages/client/ui-workspace/src/client/WorkspaceBrowser.module.css
        static let workspaceSectionHeaderHeight: CGFloat = 36
        static let workspaceIconControl: CGFloat = 28
        static let workspaceRailControl: CGFloat = 36
        static let workspaceSearchHeight: CGFloat = 28
        static let workspaceSearchExpandedHeight: CGFloat = 30
        static let workspaceListRowGap: CGFloat = 2
        static let workspaceGroupSessionLimit = 5
        // Source: packages/host/apiproxy/src/api/session-search.ts
        static let sessionSearchResultLimit = 20

        // Source: ui-primitives/Modal.module.css + ui-workspace/WorkspaceBrowser.module.css
        static let modalCardContentWidth: CGFloat = 380
        static let modalCardBorder: CGFloat = 1
        static let modalCardOuterWidth: CGFloat = 382
        static let modalCardCornerRadius: CGFloat = 24
        static let modalCardBottomPadding: CGFloat = 24
        static let modalInterSectionGap: CGFloat = 20
        static let modalHeaderLeading: CGFloat = 24
        static let modalHeaderTop: CGFloat = 22
        static let modalHeaderTrailing: CGFloat = 14
        static let modalHeaderBottom: CGFloat = 12
        static let modalHeaderHeight: CGFloat = 58
        static let modalCloseControl: CGFloat = 28
        static let modalContentHorizontalPadding: CGFloat = 24
        static let modalBodyTopMargin: CGFloat = 20
        static let modalRenameInputHeight: CGFloat = 44
        static let modalRenameInputCornerRadius: CGFloat = 22
        static let modalFooterGap: CGFloat = 8
        static let modalDescriptionLineHeight: CGFloat = 22
        static let modalActionButtonHeight: CGFloat = 36

        // Source: ui-conversation/skeleton/ApprovalPanel.module.css
        static let approvalCardOuterWidth: CGFloat = 750
        static let approvalCardOuterHeight: CGFloat = 140
        static let approvalCardCornerRadius: CGFloat = 20
        static let approvalStripHorizontalPadding: CGFloat = 16
        static let approvalStripVerticalPadding: CGFloat = 10
        static let approvalBodyMaximumHeight: CGFloat = 336
        static let approvalActionGap: CGFloat = 8
        static let approvalSeatTop: CGFloat = 8
        static let approvalSeatBottom: CGFloat = 12
        static let approvalActionVerticalPadding: CGFloat = 14
        static let actionButtonHeight: CGFloat = 36
        static let actionButtonHorizontalPadding: CGFloat = 14
        static let actionButtonCornerRadius: CGFloat = 18

        // Source: ui-user-questions/QuestionComposer.module.css
        static let questionSeatTop: CGFloat = 6
        static let questionSeatBottom: CGFloat = 10
        static let questionCardMaximumHeight: CGFloat = 520
        static let questionCardCornerRadius: CGFloat = 20
        static let questionHeaderLeading: CGFloat = 24
        static let questionHeaderTrailing: CGFloat = 16
        static let questionHeaderTop: CGFloat = 20
        static let questionHeaderActionGap: CGFloat = 4
        static let questionIconControl: CGFloat = 24
        static let questionOptionsTopMargin: CGFloat = 8
        static let questionOptionsHorizontalPadding: CGFloat = 12
        static let questionOptionsVerticalPadding: CGFloat = 4
        static let questionOptionGap: CGFloat = 8
        static let questionOptionMinimumHeight: CGFloat = 40
        static let questionOptionOuterHeight: CGFloat = 42
        static let questionOptionCornerRadius: CGFloat = 12
        static let questionOptionIndicator: CGFloat = 20
        static let questionFooterTopMargin: CGFloat = 12
        static let questionFooterLeading: CGFloat = 18
        static let questionFooterTrailing: CGFloat = 10
        static let questionFooterActionGap: CGFloat = 12
        static let questionFooterFeedbackMinimumHeight: CGFloat = 16
        static let questionCardBottomPadding: CGFloat = 10
    }

    enum Text {
        // Source: packages/client/ui-sidebar/src/client/locales.ts (en)
        static let newSession = "New Session"
        // Source: packages/client/ui-sidebar/src/client/SidebarRoot.tsx:fallbackBrandName
        static let sidebarFallbackBrand = "DSH Local Build"
        static let newSessionAccessibility = "New session"
        static let collapseSidebarAccessibility = "Collapse sidebar"
        static let openSidebarAccessibility = "Open sidebar"

        // Source: packages/client/ui-workspace/src/client/locales.ts (en)
        static let workspaces = "Workspaces"
        static let noSessionsYet = "No sessions yet"
        static let addWorkspace = "Add workspace"
        static let sessions = "Sessions"
        static let viewOptions = "View options"
        // Source: packages/client/ui-workspace/src/client/locales.ts (en)
        static let groupBy = "Group by"
        static let groupByWorkspace = "WorkSpace"
        static let groupByFlat = "In one list"
        static let orderBy = "Order by"
        static let orderByManual = "Manual"
        static let orderByUpdated = "Last updated"
        static let searchSessionsAccessibility = "Search sessions"
        static let searchSessionsPlaceholder = "Search sessions..."
        static let clearSearch = "Clear search"
        static let noMatchingSessions = "No matching sessions"
        static let ungrouped = "Ungrouped"
        static let running = "Running"
        static let idle = "Idle"
        static let workspaceActionsAccessibilityPrefix = "Workspace actions for "
        static let sessionActionsAccessibilityPrefix = "Session actions for "
        static let rename = "Rename"
        static let deleteWorkspace = "Delete workspace"
        static let forkSession = "Fork session"
        static let archiveSession = "Archive session"
        static let waitingForAnswer = "Waiting for answer"
        static let waitingForApproval = "Waiting for approval"
        static let planAwaitingReview = "Plan awaiting review"
        static let searchingSessionHistory = "Searching session history…"
        static let contentSearchUnavailable = "Content search is temporarily unavailable. Showing name matches."
        static let searchHasMoreTemplate = "Showing the first {n} results. Narrow your search."
        static func searchHasMore(_ value: Int) -> String {
            searchHasMoreTemplate.replacingOccurrences(of: "{n}", with: String(value))
        }
        static let renameWorkspaceTitle = "Rename workspace"
        static let renameSessionTitle = "Rename session"
        static let workspaceName = "Workspace name"
        static let sessionName = "Session name"
        static let workspaceNameConflictTemplate = "A workspace named “{name}” already exists."
        static func workspaceNameConflict(_ name: String) -> String {
            workspaceNameConflictTemplate.replacingOccurrences(of: "{name}", with: name)
        }
        static let deleteWorkspaceDescriptionTemplate = "This removes “{name}” from the workspace list. The folder and session logs will be kept. Its sessions will appear under Ungrouped."
        static func deleteWorkspaceDescription(name: String) -> String {
            deleteWorkspaceDescriptionTemplate.replacingOccurrences(of: "{name}", with: name)
        }
        static let deletingWorkspace = "Deleting workspace…"
        // Source: packages/client/locale/src/locales/en.ts
        static let cancel = "Cancel"
        static let close = "Close"
        static let relativeTimeNow = "now"
        static let relativeTimeMinutesTemplate = "{n}min"
        static let relativeTimeHoursTemplate = "{n}h"
        static let relativeTimeDaysTemplate = "{n}d"
        static let relativeTimeMonthsTemplate = "{n}mo"
        static let relativeTimeYearsTemplate = "{n}y"
        // Source: packages/client/connection/src/client/fixture.ts (fx-alpha fixture history)
        static let fixtureSearchSnippet = "[fixture] 上下文注入（turn 4）"
        static func relativeTime(_ template: String, value: Int) -> String {
            template.replacingOccurrences(of: "{n}", with: String(value))
        }

        // Source: packages/client/ui-settings-general/src/client/locales.ts (en)
        static let settings = "Settings"

        // Source: packages/client/ui-agent-preset/src/client/locales.ts (en)
        static let standardMode = "Standard mode"

        // Source: packages/client/ui-conversation/src/client/locales.ts (en)
        static let chat = "Chat"
        // Source: packages/client/ui-conversation/src/client/locales.ts (en)
        static let todoTitle = "To-dos"
        static let todoProgressDoneTemplate = "{done} completed"
        static let todoProgressActiveTemplate = "{active} in progress"
        static let todoProgressPendingTemplate = "{pending} pending"
        static func todoProgressDone(_ value: Int) -> String {
            todoProgressDoneTemplate.replacingOccurrences(of: "{done}", with: String(value))
        }
        static func todoProgressActive(_ value: Int) -> String {
            todoProgressActiveTemplate.replacingOccurrences(of: "{active}", with: String(value))
        }
        static func todoProgressPending(_ value: Int) -> String {
            todoProgressPendingTemplate.replacingOccurrences(of: "{pending}", with: String(value))
        }
        // Source: packages/client/ui-goal/src/client/locales.ts (en) and GoalBar.tsx.
        static let goalPhaseActive = "Ongoing Goal"
        static let goalPhasePaused = "Paused Goal"
        static let goalPhaseBlocked = "Blocked Goal"
        static let goalObjectiveAccessibility = "Goal objective"
        static let goalSaveAccessibility = "Save goal"
        static let goalCancelAccessibility = "Cancel edit"
        static let goalEditAccessibility = "Edit goal"
        static let goalPauseAccessibility = "Pause goal"
        static let goalResumeAccessibility = "Resume goal"
        static let goalClearAccessibility = "Clear goal"
        static let goalActionFailureTemplate = "{message} ({code})"
        static func goalActionFailure(message: String, code: String) -> String {
            goalActionFailureTemplate
                .replacingOccurrences(of: "{message}", with: message)
                .replacingOccurrences(of: "{code}", with: code)
        }
        // Source: packages/client/ui-conversation/src/client/locales.ts (en), QueueDock.
        static let queueCountTemplate = "{n} queued messages"
        static func queueCount(_ value: Int) -> String {
            queueCountTemplate.replacingOccurrences(of: "{n}", with: String(value))
        }
        static let queueEditAccessibility = "Edit queued message"
        static let queueEditUnsupported = "Contains non-text content; editing is not supported yet"
        static let queueEditFailure = "Edit failed: this message may have already started sending."
        static let queueRemoveAccessibility = "Remove queued message"
        static let queueRemoveFailure = "Removal failed: this message may have already started sending."
        static let queueSaveAccessibility = "Save queued message"
        static let queueCancelEditAccessibility = "Cancel editing"
        static let queueSteerAccessibility = "Steer queued message"
        static let queueSteerUnavailable = "Steering is available only while the agent is running"
        static let queueSteerFailure = "Steering failed. Try again."
        // Source: packages/client/locale/src/locales/en.ts
        static let copy = "Copy"
        static let copied = "Copied"
        // Source: packages/client/ui-conversation/src/client/chat/ChatView.tsx:144
        static let deepDiving = "Deep diving..."
        /// Source: RC8 locked jobs capture session summary/title projection.
        static let fixtureJobsSessionTitle = "Reply with the single word"
        static let sessionHierarchy = "Session hierarchy"
        static let sessionHierarchySeparator = "/"
        static let heroHeadline = "Into the Unknown"
        static let preview = "Preview"
        static let chooseWorkspace = "Choose workspace"
        static let composerWorkspacePlaceholder = "Choose a workspace to start"
        static let composerDefaultPlaceholder = "Message the agent"
        static let composerHeroPlaceholder = "Describe what you want to build"
        // Source: packages/client/connection/src/client/fixture.ts / ui-conversation PermissionSelect
        static let fixtureWorkspaceWrite = "Workspace Write"
        static let fixtureModelName = "DeepSeek-V4-Flash"
        static let fixtureReasoningEffort = "High"
        static let sendMessageAccessibility = "Send message"
        static let stopGeneratingAccessibility = "Stop generating"
        static let commandsAccessibility = "Commands"
        static let pendingImages = "Pending images"
        static let removeImageTemplate = "Remove image {name}"
        static func removePendingImage(name: String) -> String {
            removeImageTemplate.replacingOccurrences(of: "{name}", with: name)
        }
        static let details = "Details"
        static let closeDetailsAccessibility = "Close details"
        static let detailsEmpty = "Click a tool row in the message flow to view its details"
        static let chatLoadingHistory = "Loading history…"
        static let chatLoadOlder = "Load earlier"
        static let chatToBottom = "Back to bottom"
        static let toolSearch = "Search"
        static let toolRead = "Read"
        static let toolBash = "Bash"
        static let toolWrite = "Write"
        static let toolEdit = "Edit"
        static let toolCode = "Code"
        static let toolCall = "Tool call"
        static let toolRunning = "Running"
        static let toolFailed = "Failed"
        static let toolStopped = "Stopped"
        static let toolDetailsRunning = "Running…"
        static let toolSummarySeparator = "·"
        static let approvalWaiting = "Waiting for approval"
        static let approvalDetailsAccessibility = "Approval details"
        static let approvalEscalationTemplate = "Tool {toolName} requests privileged execution"
        static func approvalEscalation(toolName: String) -> String {
            approvalEscalationTemplate.replacingOccurrences(of: "{toolName}", with: toolName)
        }
        static let approvalReject = "Reject"
        static let approvalAllowOnce = "Allow once"
        static let questionPreviousAccessibility = "Previous question"
        static let questionNextAccessibility = "Next question"
        static let questionMinimizeAccessibility = "Collapse the question card"
        static let questionMaximizeAccessibility = "Expand the question card"
        static let questionCancelAccessibility = "Dismiss all questions"
        static let questionRecommended = "Recommended"
        static let questionCustomPlaceholder = "Type your answer"
        static let questionSkip = "Skip this question"
        static let questionNext = "Next"
        static let questionSubmit = "Submit"
        static let questionSubmitting = "Submitting…"
        static let questionIncomplete = "Please complete this question first."
        static let questionUnanswered = "Please select an option or enter a custom answer."
        static let questionProgressTemplate = "{current} / {total}"
        static func questionProgress(current: Int, total: Int) -> String {
            questionProgressTemplate
                .replacingOccurrences(of: "{current}", with: String(current))
                .replacingOccurrences(of: "{total}", with: String(total))
        }
    }

    /// Backward-compatible native aliases. Every value resolves through the generated,
    /// provenance-carrying `Theme` catalog instead of a hand-authored RGB literal.
    enum Token {
        static let base = Theme.aliasBgBase.adaptiveColor
        static let sidebar = Theme.specificSidebarFill.adaptiveColor
        static let elevated = Theme.aliasBgLayer1.adaptiveColor
        /// Source: `--dsw-specific-tip`, used by RC8 Todo/Goal composer strips.
        static let specificTip = Theme.specificTip.adaptiveColor
        static let primary = Theme.aliasLabelPrimary.adaptiveColor
        static let primaryForeground = Theme.aliasLabelPrimaryForeground.adaptiveColor
        static let primaryInverted = Theme.aliasLabelPrimaryInverted.adaptiveColor
        static let secondary = Theme.aliasLabelSecondary.adaptiveColor
        static let caption = Theme.aliasLabelCaption.adaptiveColor
        static let hairline = Theme.aliasBorderL1.adaptiveColor
        static let border = Theme.aliasBorderL2.adaptiveColor
        static let interactiveHover = Theme.aliasInteractiveBgHover.adaptiveColor
        static let floatingButtonFill = Theme.aliasButtonFloatingFill.adaptiveColor
        static let businessBlue = Theme.aliasStateBusinessPrimary.adaptiveColor
        static let businessBlueSoft = Theme.aliasStateBusinessTertiary.adaptiveColor
        static let conversationBubble = Theme.specificBubble.adaptiveColor
        static let warningPrimary = Theme.aliasStateWarnPrimary.adaptiveColor
        static let warningTertiary = Theme.aliasStateWarnTertiary.adaptiveColor
        static let warningBorder = Theme.aliasStateWarnSecondary.adaptiveColor
        static let modalMask = Theme.aliasBgMask1.adaptiveColor
        static let modalMask2 = Theme.aliasBgMask2.adaptiveColor
        static let modalMask3 = Theme.aliasBgMask3.adaptiveColor
        /// Official `StateDot(done)` foreground: `--dsw-alias-state-success-primary`.
        static let success = Theme.aliasStateSuccessPrimary.adaptiveColor
        static let errorPrimary = Theme.aliasStateErrorPrimary.adaptiveColor
    }

    /// Source: packages/client/ui-theme/src/styles/gradient-shadow-text.css:7
    enum Shadow {
        /// `--dsw-shadow-lv2`: 0 4px 12px rgba(0,0,0,.02), 0 2px 8px rgba(0,0,0,.04).
        static let level2OuterColor = Theme.aliasBgMask2.adaptiveColor
        static let level2OuterRadius: CGFloat = 6
        static let level2OuterY: CGFloat = 4
        static let level2InnerColor = Theme.aliasBorderL1.adaptiveColor
        static let level2InnerRadius: CGFloat = 4
        static let level2InnerY: CGFloat = 2
    }

    /// Official CSS repeatedly uses this 2px-based rhythm across InputBar, Modal,
    /// SidebarRoot, WorkspaceBrowser, and conversation components. Source values are
    /// verified in their corresponding locked `*.module.css` declarations.
    enum Spacing {
        static let p0: CGFloat = 0
        static let p1: CGFloat = 1
        static let p2: CGFloat = 2
        static let p4: CGFloat = 4
        static let p5: CGFloat = 5
        static let p6: CGFloat = 6
        static let p7: CGFloat = 7
        static let p8: CGFloat = 8
        static let p10: CGFloat = 10
        static let p12: CGFloat = 12
        static let p14: CGFloat = 14
        static let p16: CGFloat = 16
        static let p18: CGFloat = 18
        static let p20: CGFloat = 20
        static let p22: CGFloat = 22
        static let p24: CGFloat = 24
        static let p28: CGFloat = 28
        static let p32: CGFloat = 32
        static let p34: CGFloat = 34
        static let p36: CGFloat = 36
        static let p56: CGFloat = 56
        static let p60: CGFloat = 60
    }

    /// Official radii from the locked component CSS; names preserve their px roles.
    enum Radius {
        static let r1: CGFloat = 1
        static let r2: CGFloat = 2
        static let r3: CGFloat = 3
        static let r4: CGFloat = 4
        static let r6: CGFloat = 6
        static let r8: CGFloat = 8
        static let r12: CGFloat = 12
        static let r14: CGFloat = 14
        static let r18: CGFloat = 18
        static let r20: CGFloat = 20
        static let r22: CGFloat = 22
        static let r24: CGFloat = 24
        static let pill: CGFloat = 999
    }

    /// Non-spacing geometric values with explicit upstream CSS or asset sources.
    enum Geometry {
        static let px0: CGFloat = 0
        static let px1: CGFloat = 1
        static let px2: CGFloat = 2
        static let px6: CGFloat = 6
        static let px8: CGFloat = 8
        static let px10: CGFloat = 10
        static let px12: CGFloat = 12
        static let px14: CGFloat = 14
        static let px16: CGFloat = 16
        static let px17: CGFloat = 17
        static let px18: CGFloat = 18
        static let px20: CGFloat = 20
        static let px22: CGFloat = 22
        static let px24: CGFloat = 24
        static let px25: CGFloat = 25
        static let px26: CGFloat = 26
        static let px28: CGFloat = 28
        static let px32: CGFloat = 32
        static let px34: CGFloat = 34
        static let px36: CGFloat = 36
        static let px40: CGFloat = 40
        static let px42: CGFloat = 42
        static let px44: CGFloat = 44
        static let px48: CGFloat = 48
        static let px52: CGFloat = 52
        static let px56: CGFloat = 56
        static let px60: CGFloat = 60
        static let px66: CGFloat = 66
        static let px112: CGFloat = 112
        static let px140: CGFloat = 140
        static let px220: CGFloat = 220
        static let px224: CGFloat = 224
        static let px260: CGFloat = 260
        static let px336: CGFloat = 336
        static let px360: CGFloat = 360
        static let px400: CGFloat = 400
    }

    /// Locked typography projection. The standard roles are generated from the
    /// `--dsw-font-*` declarations in gradient-shadow-text.css:142–231; `heroTitle`
    /// is the explicit HeroShell component declaration at lines 35–37.
    enum Typography {
        static let xxxs11 = Font.system(size: 11, weight: .regular)
        static let xxxsStrong11 = Font.system(size: 11, weight: .medium)
        static let xxs12 = Font.system(size: 12, weight: .regular)
        static let xxsStrong12 = Font.system(size: 12, weight: .medium)
        static let xs13 = Font.system(size: 13, weight: .regular)
        static let xsStrong13 = Font.system(size: 13, weight: .medium)
        static let s14 = Font.system(size: 14, weight: .regular)
        static let sStrong14 = Font.system(size: 14, weight: .medium)
        static let markdownTableHead15 = Font.system(size: 15, weight: .medium)
        static let base16 = Font.system(size: 16, weight: .regular)
        static let baseStrong16 = Font.system(size: 16, weight: .medium)
        static let codeSmall12 = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let codeSmallStrong12 = Font.system(size: 12, weight: .medium, design: .monospaced)
        static let codeBlock13 = Font.system(size: 13, weight: .regular, design: .monospaced)
        // Source: packages/client/ui-sidebar/src/client/SidebarRoot.module.css
        static let sidebarBrand17 = Font.system(size: 17, weight: .semibold)
        static let sidebarBuildBadge8 = Font.system(size: 8, weight: .medium, design: .monospaced)
        static let heroTitle = Font.system(size: 26, weight: .medium)
    }
}

/// 与官方 `computeColumns` 保持相同让步顺序：先压缩详情列、再关闭详情列，侧栏不让步。
struct OfficialColumnLayout: Equatable {
    let sidebar: CGFloat
    let center: CGFloat
    let details: CGFloat

    static func resolve(viewport: CGFloat, sidebarPreference: CGFloat, detailsPreference: CGFloat) -> OfficialColumnLayout {
        let sidebar = sidebarPreference == 0
            ? OfficialUISpec.Layout.sidebarCollapsed
            : min(max(sidebarPreference.rounded(), OfficialUISpec.Layout.sidebarMinimum), OfficialUISpec.Layout.sidebarMaximum)
        let preferredDetails = detailsPreference == 0
            ? 0
            : min(max(detailsPreference.rounded(), OfficialUISpec.Layout.detailsMinimum), OfficialUISpec.Layout.detailsMaximum)

        if sidebar + preferredDetails + OfficialUISpec.Layout.centerMinimum <= viewport {
            return OfficialColumnLayout(sidebar: sidebar, center: viewport - sidebar - preferredDetails, details: preferredDetails)
        }

        let reducedDetails = preferredDetails == 0
            ? 0
            : max(OfficialUISpec.Layout.detailsMinimum, viewport - sidebar - OfficialUISpec.Layout.centerMinimum)
        if sidebar + reducedDetails + OfficialUISpec.Layout.centerMinimum <= viewport {
            return OfficialColumnLayout(sidebar: sidebar, center: OfficialUISpec.Layout.centerMinimum, details: reducedDetails)
        }

        return OfficialColumnLayout(sidebar: sidebar, center: max(0, viewport - sidebar), details: 0)
    }
}
