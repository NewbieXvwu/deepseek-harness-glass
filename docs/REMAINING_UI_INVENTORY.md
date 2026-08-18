# 剩余官方 WebUI 原生 SwiftUI 迁移库存

## 基线

| 项目 | 固定值 |
| --- | --- |
| 官方规格仓库 | `deepseek-ai/deepseek-harness` |
| 锁定提交 | `99f6f02fecdb7dff40c3fbc9470f5907c29f74ca` |
| 固定 Host | `dsh 0.1.0-rc.6`，由 `SupportedHostBuilds.json` 验证 |
| 目标客户端 | macOS 26+、Apple Silicon、Swift 6、SwiftUI + AppKit |
| 当前原生基线 | `main@f3b07d1`：Host/RPC/SSE、三栏容器、工作区浏览器、欢迎 composer、详情列、Host 生命周期与截图管线 |

> 此库存是迁移顺序与来源范围的控制文件。未列出并不表示可以自由设计；任何后来发现的官方表面都必须先补入此文件和 `official-ui-catalog.json`，再实施原生视图。

## 已迁移或已建立基础

| 域 | 原生状态 | 规格来源/责任边界 |
| --- | --- | --- |
| 应用框架 | 已完成 | `ui-layout`、`columns.ts`；真实 `NSSplitViewController` 管理侧栏/中心/详情列。 |
| 工作区浏览器 | 基础完成 | `ui-workspace` 的 locale、`WorkspaceBrowser.tsx`、rows/tree/CSS；Host `workspace.list`/`session.list` 与 SSE。 |
| 欢迎态 | 视觉基线完成 | `HeroShell`、`InputBar`、官方 locale/CSS 与受控 SVG。 |
| Host 生命周期 | 已完成 | Host `host.describe` 验证后才创建 `DSHAPIClient` 并加载/订阅工作区。 |
| 详情列骨架 | 已完成 | 后续由工具、交付物、轨迹与设置的原生详情适配填充。 |

## 剩余功能域与官方入口

| 优先级 | 原生迁移域 | 锁定官方源码包/关键入口 | 主要 Host/API 合同 | 计划阶段 |
| --- | --- | --- | --- | --- |
| P0 | 会话根、聊天历史、消息树、流式增量、推理与分支尾部 | `ui-conversation/src/client`：`ConversationRoot`、chat stores、input machine、消息/推理/队列相关组件及 locale | `session.history`、订阅、发送、取消、session events/projections | A |
| P0 | 完整 composer、模型/agent/plan 入口与提交策略 | `ui-conversation` 的 `InputBar`/submission/input matrix；`ui-input-trigger`、`ui-model-selection`、`ui-agent-preset`、`ui-plan` | session create/send、model/preset/plan 相关 settings/projections | B |
| P0 | 附件、拖放、粘贴和文件上限 | `ui-attachment` 与 conversation attachment surfaces | attachment RPC、image limits、上传/删除事件 | B |
| P0 | 工具调用卡、批准、结果、详情联动 | `ui-tool`、`ui-conversation` tool/trajectory surfaces | tool event view、批准/拒绝/取消、session events | C |
| P1 | 交付物、轨迹、目标、技能、subagent、workflow run | `ui-deliverables`、`ui-trajectory`、`ui-goal`、`ui-skill`、`ui-subagent`、`ui-workflow-run` | 各插件/Host projection、tool/session event views | C |
| P1 | 用户问题、计划审阅、消息反馈与权限预设 | `ui-user-questions`、`ui-message-feedback`、`ui-permission-presets` | questions/plan/feedback/permission RPC 与事件 | C |
| P1 | 工作区/会话完整管理 | `ui-workspace` rows/tree/locales/CSS | `workspace.create/rename/delete/insertBefore/archiveSession`、`session.rename/fork` | D |
| P1 | 原生目录浏览与打开路径 | `ui-directory-picker-browse`、`ui-directory-picker-native` | directory picker/open path Host capability | D/F |
| P1 | 设置根、通用设置、模型、插件、插件库存 | `ui-settings`、`ui-settings-general`、`ui-settings-models`、`ui-settings-plugins`、`ui-settings-plugin-inventory` | `settings.describe`、settings update/validate、plugin manifest | E |
| P2 | 命令弹窗和全局命令 | `ui-commands/PopupSelectView` | command registry 与官方 action 路由 | F |
| P2 | 窗口偏好、键盘、主题与恢复 | `ui-layout`、`ui-sidebar`、`ui-theme`、`ui-commands` | 本地 UI 偏好与 Host session 选择 | F |

## 迁移不可变规则

1. **文本和图标来源。** 可见文本只能通过官方 locale 常量；图标只能通过受控官方 SVG。每个新增键、图标、尺寸与状态均登记到 `official-ui-catalog.json`。
2. **业务状态来源。** SwiftUI Store 只处理瞬态显示/选择状态。所有 durable 状态和服务端操作必须由 `DSHAPIClient`、官方 RPC schema 与 SSE event schema 支撑。
3. **WebView 例外。** 主界面和设置界面不得使用 WebView。仅 manifest 明确、功能不能等价原生化的插件可进入 `PluginWebHost`，且必须独立审查、隔离权限并建立替代计划。
4. **视觉验证。** 每个域都需以官方同尺寸截图对照原生 macOS 26 snapshot；默认覆盖 1280×840、1024px 临界宽度、rail、light/dark、空态、选中、运行和失败状态。
5. **无障碍与控制层。** 所有图标按钮有官方可访问性键；键盘焦点顺序必须可测。Liquid Glass 仅在导航/控制层，不得覆盖会话、工具输出、表单或代码内容。

## 完成定义

一个功能域只有同时满足以下条件才标记为完成：官方来源映射完成；RPC/SSE DTO 和 reducer 有行为测试；所有可见状态有原生 UI；D0/D1 和 macOS 26 CI 通过；截图和无障碍证据归档；任何 WebView 使用都有获批例外记录。
