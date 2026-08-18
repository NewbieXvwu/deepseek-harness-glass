import SwiftUI

/// 已锁定 DeepSeek Harness WebUI 基线的原生规格。
/// 首屏文本、token 和布局值只来自该基线的 locale/CSS/组件源码，禁止由 View 自行创造产品文案。
enum OfficialUISpec {
    static let deepSeekHarnessCommit = "99f6f02fecdb7dff40c3fbc9470f5907c29f74ca"

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
        static let composerCornerRadius: CGFloat = 22
        static let heroGap: CGFloat = 12
        // Source: ui-conversation/chat/MessageItem.module.css
        static let chatMessageGap: CGFloat = 6
        static let chatTranscriptInset: CGFloat = 20
        static let chatUserMessageMaximum: CGFloat = 525
        static let chatMessageCornerRadius: CGFloat = 22
        static let sidebarInlinePadding: CGFloat = 12

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
        static let newSessionAccessibility = "New session"
        static let collapseSidebarAccessibility = "Collapse sidebar"
        static let openSidebarAccessibility = "Open sidebar"

        // Source: packages/client/ui-workspace/src/client/locales.ts (en)
        static let workspaces = "Workspaces"
        static let noSessionsYet = "No sessions yet"
        static let addWorkspace = "Add workspace"
        static let sessions = "Sessions"
        static let viewOptions = "View options"
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
        static func relativeTime(_ template: String, value: Int) -> String {
            template.replacingOccurrences(of: "{n}", with: String(value))
        }

        // Source: packages/client/ui-settings-general/src/client/locales.ts (en)
        static let settings = "Settings"

        // Source: packages/client/ui-agent-preset/src/client/locales.ts (en)
        static let standardMode = "Standard mode"

        // Source: packages/client/ui-conversation/src/client/locales.ts (en)
        static let chat = "Chat"
        static let heroHeadline = "Into the Unknown"
        static let preview = "Preview"
        static let chooseWorkspace = "Choose workspace"
        static let composerWorkspacePlaceholder = "Choose a workspace to start"
        static let composerDefaultPlaceholder = "Message the agent"
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

    enum Token {
        // Source: packages/client/ui-theme/src/styles/design-platform.css
        static let base = Color.white
        static let sidebar = Color(red: 249 / 255, green: 250 / 255, blue: 251 / 255)
        static let elevated = Color.white
        static let primary = Color(red: 15 / 255, green: 17 / 255, blue: 21 / 255)
        static let secondary = Color(red: 97 / 255, green: 102 / 255, blue: 107 / 255)
        static let caption = Color(red: 151 / 255, green: 157 / 255, blue: 166 / 255)
        static let hairline = Color.black.opacity(0.04)
        static let border = Color.black.opacity(0.10)
        static let interactiveHover = Color(red: 235 / 255, green: 238 / 255, blue: 242 / 255)
        static let businessBlue = Color(red: 65 / 255, green: 118 / 255, blue: 230 / 255)
        static let businessBlueSoft = Color(red: 228 / 255, green: 237 / 255, blue: 253 / 255)
        static let businessBlueGlow = Color(red: 97 / 255, green: 135 / 255, blue: 216 / 255).opacity(0.08)
        // Source: ui-theme/src/styles/design-platform.css (`--dsw-specific-bubble`)
        static let conversationBubble = Color(red: 225 / 255, green: 235 / 255, blue: 253 / 255)
        // Source: ui-theme/src/styles/design-platform.css (`--dsw-alias-state-warn-*`)
        static let warningPrimary = Color(red: 181 / 255, green: 112 / 255, blue: 0 / 255)
        static let warningTertiary = Color(red: 255 / 255, green: 244 / 255, blue: 218 / 255)
        static let warningBorder = Color(red: 235 / 255, green: 188 / 255, blue: 97 / 255)
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
