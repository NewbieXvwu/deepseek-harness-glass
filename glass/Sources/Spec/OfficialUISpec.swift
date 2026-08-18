import SwiftUI

/// 受支持的官方 WebUI 基线。所有首屏文字、三栏几何与主题色均从该基线的
/// locale、ui-layout 和 ui-theme 源码提取；核心 View 不得自行硬编码产品文本。
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
    }

    enum Text {
        // Source: packages/client/ui-sidebar/src/client/locales.ts (zh)
        static let newSession = "新会话"
        static let newSessionAccessibility = "新建会话"
        static let collapseSidebarAccessibility = "收起侧边栏"
        static let openSidebarAccessibility = "打开侧边栏"

        // Source: packages/client/ui-workspace/src/client/locales.ts (zh)
        static let workspaces = "工作区"
        static let addWorkspace = "添加工作区"

        // Source: packages/client/ui-conversation/src/client/locales.ts (zh)
        static let chat = "对话"
        static let heroHeadline = "探索未至之境"
        static let preview = "预览版"
        static let chooseWorkspace = "选择工作区"
        static let composerWorkspacePlaceholder = "选择一个工作区开始"
        static let composerDefaultPlaceholder = "给智能体发消息"
        static let sendMessageAccessibility = "发送消息"
        static let details = "详情"
        static let closeDetailsAccessibility = "关闭详情"
        static let detailsEmpty = "点击消息流中的工具行查看详情"
    }

    enum Token {
        // Source: packages/client/ui-theme/src/styles/design-platform.css
        static let baseDark = Color(red: 21 / 255, green: 21 / 255, blue: 23 / 255)
        static let layerDark = Color(red: 35 / 255, green: 35 / 255, blue: 36 / 255)
        static let sidebarDark = Color(red: 27 / 255, green: 27 / 255, blue: 28 / 255)
        static let controlDark = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
        static let labelPrimaryDark = Color(red: 249 / 255, green: 250 / 255, blue: 251 / 255)
        static let labelSecondaryDark = Color(red: 207 / 255, green: 211 / 255, blue: 214 / 255)
        static let labelTertiaryDark = Color(red: 151 / 255, green: 157 / 255, blue: 166 / 255)
        static let separatorDark = Color.white.opacity(0.12)
        static let separatorThinDark = Color.white.opacity(0.06)
        static let activeFillDark = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
        static let brandLight = Color(red: 249 / 255, green: 250 / 255, blue: 251 / 255)
    }
}

/// 与官方 `computeColumns` 相同的三栏 concession chain。
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
            return OfficialColumnLayout(
                sidebar: sidebar,
                center: viewport - sidebar - preferredDetails,
                details: preferredDetails
            )
        }

        let reducedDetails = preferredDetails == 0
            ? 0
            : max(OfficialUISpec.Layout.detailsMinimum, viewport - sidebar - OfficialUISpec.Layout.centerMinimum)
        if sidebar + reducedDetails + OfficialUISpec.Layout.centerMinimum <= viewport {
            return OfficialColumnLayout(
                sidebar: sidebar,
                center: OfficialUISpec.Layout.centerMinimum,
                details: reducedDetails
            )
        }

        return OfficialColumnLayout(sidebar: sidebar, center: max(0, viewport - sidebar), details: 0)
    }
}
