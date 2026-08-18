# DeepSeek Harness Glass：原生 Swift macOS 客户端实施 TODO

**目标分支：** `main`

**工作模式：** 用原生 SwiftUI + AppKit 重写官方 DeepSeek Harness WebUI；核心界面、官方内置设置与会话流不得使用 WebView；仅在经审计且技术上无法原生化的第三方插件页面中允许严格隔离的例外 WebView。

**目标系统：** macOS 26+、Xcode 26+、Apple Silicon。

**官方基线：** `deepseek-ai/deepseek-harness@99f6f02fecdb7dff40c3fbc9470f5907c29f74ca`。任何升级均须通过本文件定义的协议、视觉与无障碍门禁后，才可加入支持矩阵。[1] [2]

> **首要原则：** 本项目不是替换 CSS 或包装网页，而是保留 DeepSeek Harness Host、替换 Browser Client。官方布局常量、文本、字段顺序、状态机与交互语义是规格来源；Liquid Glass 只增强 macOS 的窗口、导航和必要操作控件，不能借机添加任何非官方的产品文案、页面、信息层级或装饰。

## 0. 完成定义与不可突破的边界

以下定义必须在第一行代码提交前被项目维护者接受。它决定了哪些实现可以合并，哪些“看上去更快”的 Web 方案必须拒绝。

| 编号 | 完成定义 | 可验证的事实 |
|---|---|---|
| D0 | 核心业务 UI 为原生。 | 应用中没有 `WKWebView`、网页 JavaScript、CSS 注入或 DOM 扫描用于会话、侧栏、工作区、官方设置、模型、凭据、工具或对话页面。 |
| D1 | 官方 UI 严格复刻。 | 在已锁定 DSH build 下，文案来自官方 locale；结构、间距、行序、状态和官方交互测试场景可追溯到 `OfficialUISpec`。 |
| D2 | Host 是唯一业务真源。 | 任何会话、工作区、设置、凭据、模型、命令和插件配置，均通过官方 loopback RPC/SSE 获取或写入，不建立与 Host 冲突的持久业务数据库。 |
| D3 | Liquid Glass 服从系统设计。 | 侧栏、inspector、工具栏、sheet、popover 和少数操作控件优先使用系统材质；内容层不泛滥叠加 glass effect。[9] [10] |
| D4 | 插件兼容有明确分级。 | 每个插件处于 `native-manifest`、`swift-adapter`、`web-fallback`、`host-only` 或 `unsupported` 的一种状态，状态可在诊断页面查询。 |
| D5 | 未验证的 DSH Host 不冒充兼容。 | 启动时检查支持的 Host build；不在矩阵中的版本显示“未验证”，并禁止写入可能造成协议漂移的数据。 |

- [ ] **T0.1：在 README 与贡献指南中写入 D0–D5。** 说明 `WebKit` 只能位于 `PluginWebHost` 目标中，禁止在主应用 target 或任何核心 renderer 中导入。
  - 依赖：无。
  - 验收：CI 的静态规则可阻止 `glass/Sources/Core/**`、`glass/Sources/UI/**`、`glass/Sources/Features/**` 导入 `WebKit`。

- [ ] **T0.2：确定产品支持边界。** 第一版仅支持一个固定的 DSH package/commit 与其捆绑 Node 运行时；不支持任意外部 `dsh web` 实例作为写入目标。
  - 依赖：T0.1。
  - 验收：`SupportedHostBuilds.json` 包含 package version、git commit、protocol fixture revision、Node version、最小 App version 和验证日期。

- [ ] **T0.3：确定“官方复刻”的判定层级。** 把“文本、布局、状态、交互”与“系统渲染的玻璃折射和阴影”分开。前四项严格比对；后者只验证系统 API 使用、层级、可读性和辅助功能响应，不追求逐像素模仿 CSS。
  - 依赖：T0.1。
  - 验收：测试计划中有明确的结构差异阈值、截图场景与人工审阅准则。

## 1. 仓库与模块化基础

现有项目将主要逻辑集中在 `glass/Sources/main.swift`。重写前应拆分生命周期、Host 通信、状态、界面和插件兼容层，避免将 SwiftUI、AppKit、网络、进程与业务 reducer 再次耦合在一个文件中。

- [ ] **T1.1：保留现有项目的可复用运行时资产。** 列出并迁移内嵌 Node、dsh payload、构建脚本、Info.plist、图标、签名与 release workflow；保留 `DSH_HOME`、日志目录、端口复用、自动恢复、菜单栏常驻和优雅退出的意图。
  - 依赖：T0.2。
  - 验收：迁移清单将当前 `main.swift` 的每项职责标注为 `保留`、`替换` 或 `删除`；没有未分类的隐式行为。

- [ ] **T1.2：建立目标目录结构。** 推荐结构如下，实际命名可微调，但层级职责不可混淆。

```text
 glass/
 ├── App/
 │   ├── DeepSeekHarnessGlassApp.swift
 │   ├── AppDelegate.swift
 │   ├── WindowCoordinator.swift
 │   └── MenuBarCoordinator.swift
 ├── Core/
 │   ├── Host/
 │   │   ├── HarnessHostController.swift
 │   │   ├── HostBuildVerifier.swift
 │   │   └── HostLifecycleState.swift
 │   ├── Transport/
 │   │   ├── DSHClientTransport.swift
 │   │   ├── RPCEnvelope.swift
 │   │   ├── SSEClient.swift
 │   │   └── GeneratedDTO/
 │   ├── Session/
 │   │   ├── NativeSessionStore.swift
 │   │   ├── SessionHistoryPager.swift
 │   │   ├── ProjectionStore.swift
 │   │   └── ConversationReducer.swift
 │   ├── Settings/
 │   │   ├── NativeSettingsStore.swift
 │   │   ├── CredentialStore.swift
 │   │   └── RevisionFence.swift
 │   └── Support/
 │       ├── Logging.swift
 │       ├── Diagnostics.swift
 │       └── FeatureFlags.swift
 ├── Spec/
 │   ├── OfficialUISpec/
 │   ├── Locales/
 │   ├── Tokens/
 │   ├── Fixtures/
 │   └── SupportedHostBuilds.json
 ├── UI/
 │   ├── Shell/
 │   ├── Sidebar/
 │   ├── Workspace/
 │   ├── Conversation/
 │   ├── Tooling/
 │   ├── Settings/
 │   ├── Primitives/
 │   └── LiquidGlass/
 ├── Plugins/
 │   ├── NativeUIManifest/
 │   ├── AdapterRegistry/
 │   └── PluginWebHost/               # 唯一允许导入 WebKit 的模块
 └── Tests/
     ├── Contract/
     ├── Reducer/
     ├── Snapshot/
     ├── Accessibility/
     └── Performance/
```

  - 依赖：T1.1。
  - 验收：每一层有独立 target 或最少独立 Swift package；UI 不能直接启动子进程；reducer 不能直接访问 `NSApplication`。

- [ ] **T1.3：删除旧 WebUI 路径的迁移分支。** 初期可临时保留 legacy build target 用于官方对照，但主应用 target 不再链接 `GlassWebView`、`WKUserScript`、CSS 注入、`evaluateJavaScript` 与页面 DOM mutation 逻辑。
  - 依赖：T1.2、T3.6。
  - 验收：`grep -R "WKWebView\|WKUserScript\|evaluateJavaScript\|MutationObserver" glass/` 只命中 `Plugins/PluginWebHost` 或 legacy 对照 target；核心功能可运行。

## 2. 锁定官方规格：文本、token、布局和行为

“不得自创界面文本、排版”必须由版本化规格和自动化工具保证。官方 Web client 的 `locales.ts`、主题 token sheet、`ui-layout` 常量、组件结构与 e2e 场景共同组成规格来源；不能将设计信息从网页截图中手工猜测。[3] [4] [5] [6]

- [ ] **T2.1：创建 `OfficialUISpec` 元数据格式。** 至少包含 `sourceCommit`、`localeRevision`、`tokenRevision`、`layoutRevision`、`fixtureRevision`、`generatedAt` 和生成器版本。
  - 依赖：T0.2。
  - 验收：所有 Swift UI 测试都读取 `OfficialUISpec` 的 build ID；当 spec 与 Host build 不匹配时测试失败。

- [ ] **T2.2：提取官方 locale。** 从官方 `packages/client/**/locales.ts` 和相关 locale package 导出字符串，保留 key、语言、插值参数、复数规则、来源路径与源 commit。
  - 依赖：T2.1。
  - 验收：核心 Swift View 不出现自行撰写的官方产品文案；字符串 lint 能发现未登记字面量；中英两种语言至少能解析。

- [ ] **T2.3：提取主题与排版 token。** 将官方 `--dsw-*` 设计 token 映射为 `OfficialColorToken`、`OfficialSpacing`、`OfficialRadius`、`OfficialTypography` 和状态 token；映射需记录原始 CSS token 名，而不是把数值散落在 View 内。
  - 依赖：T2.1。
  - 验收：所有色彩、间距、圆角和文字样式均通过语义 token 调用；不在核心 UI 新增未经规格批准的常量。

- [ ] **T2.4：固化官方三栏算法。** 按官方 constants 实现侧栏默认 280px、范围 264–420px、收缩轨 56px、窄窗口阈值 1024px、中心目标最小宽度 640px、详情默认 360px、范围 300–520px，并保留“先压缩详情、后关闭详情”的规则。[4] [5]
  - 依赖：T2.1。
  - 验收：对官方 `computeColumns` 夹具的每一个输入，Swift `LayoutSolver` 输出相同列宽；边界值使用单元测试覆盖。

- [ ] **T2.5：建立官方交互场景目录。** 每个场景包含初始 Host fixture、窗口尺寸、颜色模式、辅助功能模式、动作序列、预期可见文案、预期布局树和截图基线。
  - 依赖：T2.2–T2.4。
  - 验收：至少覆盖启动、无工作区、空会话、流式回答、工具调用、审批、队列、设置、窄窗口、详情栏关闭/重开、深色模式和错误恢复。

- [ ] **T2.6：定义视觉差异策略。** 普通布局层使用结构树断言和截图差异；系统 Glass 区域使用位置、尺寸、层级、对比度和系统状态断言，不对系统动态折射作像素级失败判定。
  - 依赖：T2.5。
  - 验收：视觉报告能够区分“官方布局偏移”与“系统材质自然差异”。

## 3. Host 生命周期、版本验证与诊断

官方 Web profile 由 Node Host 提供 API、SSE、静态页面与 plugin graph。原生客户端应只使用前两者来承载业务，前端静态资源仅在 WebView 插件 fallback POC 时出现。[1] [7]

- [ ] **T3.1：拆出 `HarnessHostController`。** 从现有 `BackendController` 迁移 Node 定位、payload 定位、`DSH_HOME`、`dsh web --port 0` 启动、stdout URL 解析、端口检测、日志写入、一次自动重启和退出清理。
  - 依赖：T1.2。
  - 验收：无任何 UI target 的命令行测试可启动、复用、停止 Host；退出后无孤儿 Node/dsh 进程。

- [ ] **T3.2：实现 Host build 验证。** 通过捆绑 manifest、package metadata 或 Host 可用的描述信息确认当前 payload 属于 `SupportedHostBuilds.json`；不要根据 URL 或端口猜测兼容性。
  - 依赖：T0.2、T3.1。
  - 验收：已验证 build 进入 `ready`；未知 build 进入 `unverified`，并关闭写操作或要求开发者开关。

- [ ] **T3.3：定义显式生命周期状态。** 使用 `idle`、`probingExternal`、`startingOwned`、`verifying`、`ready`、`recovering`、`failed`、`stopping`，而非由 URL 是否为 `nil` 推断状态。
  - 依赖：T3.1。
  - 验收：状态转换有日志和单元测试；UI 可展示来自官方规格的启动、失败和重试文案。

- [ ] **T3.4：重做诊断与日志。** 提供可复制的 Host build、端口、DSH_HOME、进程所有权、最后 SSE 时间、最后 RPC 错误、协议 fixture revision 和插件兼容状态；敏感凭据永不写入日志。
  - 依赖：T3.2、T3.3。
  - 验收：错误报告包含足够的信息重现问题，不包含 API key、Cookie、原始 secret 或未红脱敏的 settings。

- [ ] **T3.5：实现下载与导出替代路径。** 对 session log export 和其他 Host 下载使用 `URLSessionDownloadTask`，在原生下载目录策略中保留同名冲突处理。
  - 依赖：T3.1、T4.4。
  - 验收：不需要 WebKit delegate 即可下载和打开导出文件。

- [ ] **T3.6：Host + transport 冒烟门。** 第一个可演示里程碑应只显示原生诊断页，但能够启动 Host、创建/选择 session、执行只读 RPC、订阅 SSE 并重新连接。
  - 依赖：T3.1–T3.4、T4.1–T4.5。
  - 验收：断网、Host 重启、SSE 断开和 5xx 都有明确状态，且不会使 App 崩溃。

## 4. HTTP RPC、SSE 与强类型契约

官方 API 的请求/响应通过 `rpcId` 关联，并将 ClientRequest、ServerResponse、ServerRequest、ClientResponse 映射在 HTTP POST 与 SSE 上。会话、工作区、设置、凭据、模型、命令和远程事件都应经过同一个可测试传输层。[7]

- [ ] **T4.1：定义 `RPCEnvelope` 与通用错误模型。** 覆盖 request/response envelope、`rpcId`、成功/错误分支、HTTP transport error、业务 error、超时与取消。
  - 依赖：T3.1。
  - 验收：每种错误可被上层区分为“可重试”“需刷新”“需用户修正”“不支持”“程序错误”。

- [ ] **T4.2：生成或维护 Swift DTO。** 从官方 TypeScript/Zod schema 建立受控生成步骤；若第一版手工建模，也必须记录 schema source path 与 fixture revision。
  - 依赖：T4.1、T0.2。
  - 验收：每个已支持 RPC method 既有 Codable round-trip test，又有来自真实 Host 的 fixture test。

- [ ] **T4.3：实现 `DSHClientTransport`。** 使用 `URLSession` 实现 JSON POST、Content-Type、请求取消、统一超时、`rpcId` 去重和调用 tracing。
  - 依赖：T4.1、T4.2。
  - 验收：并发 100 个 mock RPC 不串线；response 必须匹配 request 的 `rpcId` 才能交付调用者。

- [ ] **T4.4：实现 `SSEClient`。** 支持 ServerRequest 帧、断线检测、指数退避、Host restart 后重订阅、最终取消与网络路径变化。
  - 依赖：T4.1。
  - 验收：可重放录制 SSE stream；在重连后不会重复应用低序号事件。

- [ ] **T4.5：建立 API 域 facade。** 至少提供 `SessionsAPI`、`WorkspacesAPI`、`SettingsAPI`、`CredentialsAPI`、`LLMAPI`、`CommandsAPI`、`SkillsAPI`、`AgentPresetsAPI`、`DownloadsAPI` 与 `HostAPI`。
  - 依赖：T4.3、T4.4。
  - 验收：Feature 层只能依赖 facade，不直接构造 URL 或字典 JSON。

- [ ] **T4.6：建立 transport 契约回归。** 用官方接口测试 fixture 覆盖 `session.history`、`session.prompt`、`session.cancel`、`settings.describe`、`settings.mutate`、`credentials.set`、`llm.providers`、`session.models`、SSE event/projection、RPC error 与 revision conflict。
  - 依赖：T4.5。
  - 验收：升级 Host build 时，契约 diff 以新增/修改/删除方法、字段和 enum 分类显示；未审阅 diff 直接阻止发布。

## 5. 原生窗口、三栏骨架与 Liquid Glass

Apple 建议使用系统导航与标准控件以自动获得 Liquid Glass；在 macOS 上，`NSSplitViewController` 的 sidebar 和 inspector 行为能提供相应的系统材质。Liquid Glass 属于导航/控制层，不应用于整个内容层。[9] [10] [11]

- [ ] **T5.1：实现 `WindowCoordinator`。** 保留最小窗口尺寸、全尺寸内容、标题栏策略、窗口恢复和菜单栏重开逻辑；删除“网页透明化”作为窗口玻璃实现的前提。
  - 依赖：T1.2。
  - 验收：窗口可正常 resize、minimize、close-to-menu-bar 和 reopen；内容不会撞到 macOS 26 圆角或窗口控制。

- [ ] **T5.2：实现 AppKit 三栏容器。** 使用 `NSSplitViewController` 或等价 AppKit 层，分别配置 sidebar、content、inspector；SwiftUI 只作为各列内部 View。
  - 依赖：T2.4、T5.1。
  - 验收：官方列宽算法、拖动 divider、折叠详情栏、56px sidebar rail 和窄窗口策略均通过单元与 UI 测试。

- [ ] **T5.3：让系统负责 sidebar/inspector 材质。** 禁止在这两个结构区域再加旧的 `NSVisualEffectView` 或一层全窗自定义模糊来“模拟”玻璃。
  - 依赖：T5.2。
  - 验收：在 Light/Dark、Reduce Transparency、Increase Contrast 下，系统外观自然适配，无手工壁纸亮度采样逻辑。

- [ ] **T5.4：建立 `GlassPolicy`。** 对每类 UI 明确 `content`、`systemNavigation`、`regularGlassCustomControl`、`clearGlassMediaOverlay` 等策略，并限制同屏 custom glass 的数量。
  - 依赖：T5.2。
  - 验收：代码审查规则要求每个 `glassEffect` 指定 policy；没有理由的 custom glass 不可合并。

- [ ] **T5.5：实现有限的自定义 glass controls。** 仅用于官方已有的悬浮操作、模型选择或关键确认控制；使用 `GlassEffectContainer` 管理相邻形变元素，并应用官方间距和形状。
  - 依赖：T2.3、T5.4。
  - 验收：使用 `prefersReducedMotion`、Reduce Transparency、Increase Contrast 时可读且无令人不适的强制动画。[10]

- [ ] **T5.6：建立无障碍验收基线。** 检查 VoiceOver label、键盘焦点、动态字体/放大、减少动态效果、降低透明度、高对比度和颜色模式。
  - 依赖：T5.3–T5.5。
  - 验收：每个核心路径有辅助功能 UI test；任何 icon-only 官方控件均保有可访问名称。

## 6. 会话状态机与事件投影

官方 Web client 将 session history、实时 `session/event` 和 `session/projection` 组合为 incremental conversation snapshots，并用 `ConversationNodeDefinition` 为不同业务节点分派 renderer。原生端必须复现该“事件→节点→视图”结构，而非只做消息数组。[7] [8]

- [ ] **T6.1：实现 `NativeSessionStore`。** 用 Session ID 作为隔离边界，维护 current session、历史分页窗口、加载状态、running 状态、pending interaction、queue、jobs 和 selection。
  - 依赖：T4.5。
  - 验收：切换 workspace/session 不丢失已加载历史；cold session 与 live session 均能被表示。

- [ ] **T6.2：实现 `SessionHistoryPager`。** 支持 tail history、向前分页、连续 raw event range、loading/error/retry 和 session export。
  - 依赖：T6.1。
  - 验收：重复分页不会产生重复或乱序 event；compaction summary 等位于边界的 event 与官方夹具一致。

- [ ] **T6.3：实现 `ProjectionStore`。** 以 `(sessionId, key)` 维护 projection value 和 seq，高序号覆盖低序号；支持 history tail baseline 和 live `session/projection` 更新。
  - 依赖：T4.4、T6.1。
  - 验收：乱序帧、重复帧和 reconnect baseline 不会回滚新值。

- [ ] **T6.4：定义 `ConversationNode` 协议。** 建立 `match`、`start`、`update`、`publication`、`buildViewNode` 的 Swift 等价物，并包含 turn/step location、visibility、stable key 和 target。
  - 依赖：T6.1、T6.2。
  - 验收：节点生命周期只有 reducer 改写；SwiftUI renderer 无业务事件解析代码。

- [ ] **T6.5：实现初始核心 nodes。** 依次支持 user message、assistant chunk/message、turn/step、tool call/result、error/retry、thinking、context injection 与 compaction。
  - 依赖：T6.4。
  - 验收：同一官方事件 fixture 在每一次 append 后均生成预期 node snapshot；流式 assistant tail 不重复渲染。

- [ ] **T6.6：实现扩展 nodes。** 支持 todo、goal、queue/steering、approval、user question、workflow、subagent、trajectory、deliverables、feedback、model/permission 状态和 jobs。
  - 依赖：T6.5。
  - 验收：每个 node type 有 fixture、renderer snapshot、错误/取消场景和缺失插件时的安全降级。

- [ ] **T6.7：实现 reconnect/replay 算法。** 在 transport 断开、Host 重启或 session 从 cold 到 live 时，重新拉取 authority baseline，并以 raw history + projection + current session status 恢复。
  - 依赖：T6.1–T6.6。
  - 验收：在任一 event 序列点断开、重连后，状态与连续运行参考结果一致。

## 7. 侧栏、工作区与会话浏览器

官方 sidebar 提供 wordmark、新会话、折叠控制、工作区/会话浏览器和固定的设置入口；折叠动画最终落入 56px rail。工作区和会话分组由独立 UI 模块承担。[12]

- [ ] **T7.1：实现 sidebar 的静态结构。** 复刻 wordmark、New Session、workspace seat、settings seat、滚动区与底部固定区域；所有文字引用 `OfficialUISpec`。
  - 依赖：T2.2、T5.2。
  - 验收：无 workspace 与有 workspace 两种状态使用官方文案和结构，不出现自创欢迎页。

- [ ] **T7.2：实现 workspace/session browser。** 支持 workspace list、create、reorder、archive、ungrouped、session list、selected/running/blank 状态和空会话复用。
  - 依赖：T4.5、T6.1、T7.1。
  - 验收：Host workspace/session change 帧到达后列表更新正确，不依赖页面刷新。

- [ ] **T7.3：实现 sidebar 搜索与行操作。** 行为、可见性、快捷键、空状态、结果排序和文案必须以锁定官方 UI 为准。
  - 依赖：T7.2、T2.5。
  - 验收：每个官方测试场景可复现，搜索不创建未记录的原生私有索引。

- [ ] **T7.4：实现收缩 rail。** 用官方尺寸和 motion sequence 完成 wide ↔ rail 切换；减弱动态效果时使用静态/简化过渡。
  - 依赖：T2.4、T5.2、T5.6。
  - 验收：1024px 阈值前后和手动展开逻辑与官方 fixture 相符；焦点不会落入隐藏的控制。

## 8. Conversation 主界面与输入闭环

这一阶段要先实现高频的完整会话闭环，再扩展所有低频节点。必须保持官方无 workspace、blank session、running session、busy composer、approval takeover 与 queue 的不同状态语义。[13]

- [ ] **T8.1：实现 session header 和 view tabs。** 支持 title、chat view、扩展 view registry、header actions、utilities 和空 session 过渡。
  - 依赖：T6.1、T6.4、T2.2。
  - 验收：切换 session 不闪烁、不重新创建不必要的输入控件；标题与官方 DocumentTitle 行为相符。

- [ ] **T8.2：实现 ChatView 与基础消息 renderer。** 支持用户气泡、assistant Markdown、流式尾部、copy、时间、turn status 与官方可见性规则。
  - 依赖：T6.5、T8.1。
  - 验收：streaming chunk 不造成整页重排；历史与实时尾部在同一 node tree 中衔接。

- [ ] **T8.3：实现 Markdown、代码与链接策略。** 支持官方允许的 Markdown、代码块、语法高亮、copy、路径链接和外部 URL 打开策略；不得把 HTML 当作不受限原生富文本执行。
  - 依赖：T8.2。
  - 验收：恶意 Markdown/URL fixture 不可执行脚本或打开任意 file URL；官方常规代码块视觉匹配规格。

- [ ] **T8.4：实现 Composer。** 支持 draft、textarea、send、stop、Shift+Enter、Enter/Cmd+Enter 的官方队列/steer 逻辑、blocked placeholder、命令入口、附件入口和 keyboard focus。
  - 依赖：T4.5、T6.1、T2.5。
  - 验收：idle、busy、no-workspace、blocked、addressed-subagent 等状态均匹配官方场景；不会在未选择 workspace 时发送消息。

- [ ] **T8.5：实现 prompt/cancel/queue RPC 流程。** 发送先进入正确的 Host API，再按 SSE authority 更新；不可乐观制造与 Host 无关的永久消息。
  - 依赖：T8.4、T6.7。
  - 验收：发送、取消、排队编辑/删除、steer race 和 Host 拒绝均有准确可恢复状态。

- [ ] **T8.6：实现模型与权限控制。** 在 composer 固定官方位置渲染 model selector、reasoning effort、context meter、permission preset 和高风险确认。
  - 依赖：T4.5、T6.3、T8.4。
  - 验收：无可用 model 时 composer 被官方原因文案阻止；选择模型后 unblock；高风险权限必须经确认。

- [ ] **T8.7：实现队列、todo、goal、stats dock。** 使用 projection 或官方 API 真源展示，支持折叠、计数、状态和溢出行为。
  - 依赖：T6.3、T6.6、T8.4。
  - 验收：多个 dock 的顺序、隐藏规则、滚动与无障碍标签符合规格。

## 9. 工具、审批、问题、轨迹与详情

官方工具和复杂会话节点是完全复刻中的高风险区域。应按 node type 分批交付，并确保未实现的 renderer 不会静默丢失模型行为或原始数据。

- [ ] **T9.1：实现 generic tool renderer。** 显示 tool call、参数摘要、执行状态、结果、错误、折叠和原始 fallback。
  - 依赖：T6.5、T8.2。
  - 验收：所有未知 tool type 以安全、可复制、不过度解释的通用视图呈现；不丢弃 raw result。

- [ ] **T9.2：实现官方常用 tool renderer。** 分别完成 bash/terminal、read、search、file mutation/diff、todo、web、ask-question、workflow 和图像/附件类 renderer。
  - 依赖：T9.1、T2.5。
  - 验收：每类 renderer 有官方 fixture、加载/失败/取消/超长输出测试和性能基线。

- [ ] **T9.3：实现审批与用户问题 takeover。** 用官方 composer takeover 语义替代普通弹窗，支持 allow-once、reject、选择项、多选与自定义文本。
  - 依赖：T6.6、T8.4。
  - 验收：回答只能对 pending request 提交一次；断线/重连不重复授权。

- [ ] **T9.4：实现 thinking、retry、compaction。** 复刻默认收缩、流式摘要、retry 倒计时、错误可见性、checkpoint disclosure 和 summary 边界。
  - 依赖：T6.5、T8.2。
  - 验收：没有 chain-of-thought 泄露；compaction 不错误移除历史；retry 完成/取消状态准确。

- [ ] **T9.5：实现 trajectory、subagent、workflow 与 deliverables。** 先识别官方 chat node/独立 view 的最小数据契约，再建立 renderer；不要为了填界面而自创 summary 文案。
  - 依赖：T6.6、T8.1、T9.1。
  - 验收：每种复杂节点在相关官方插件未加载时安全隐藏或显示官方原始 fallback，而非崩溃。

- [ ] **T9.6：实现详情栏。** 展示官方可达的 tool detail、input/output/metadata 和选择态；详情列关闭时 subtree 持久化策略应与官方语义一致。
  - 依赖：T5.2、T9.1。
  - 验收：开关详情栏不丢失当前 tool selection；窄窗口自动关闭时不破坏中心会话。

## 10. 官方设置、凭据、模型与主题

官方 settings API 提供 namespace、schema、resolved/base/user redacted values、secrets、revision 与写入接口；必须实现 expected revision fencing，避免覆盖并发配置。[7] 官方主题 token 和 light/dark/system 选择也是规格的一部分。[6]

- [ ] **T10.1：实现 Settings Root。** 复刻官方 settings 导航、section 顺序、选中态、返回逻辑、窗口/面板行为与空状态；不设计额外“原生设置”分类。
  - 依赖：T2.2、T5.2。
  - 验收：所有内置 section 文案与官方 locale 对应，排列由 `OfficialUISpec` 驱动。

- [ ] **T10.2：实现 `NativeSettingsStore`。** 包含 describe cache、draft、dirty/invalid、readback、discard、revision conflict、remote invalidation 与 reconnect refresh。
  - 依赖：T4.5。
  - 验收：两个客户端并发修改同一 namespace 时，旧 revision 的写入被拒绝且本地草稿仍可修正。

- [ ] **T10.3：实现官方 General 页面。** 覆盖官方公开的通用偏好、主题、行为项和 agent preset 行；字段可见性遵循 Host 能力。
  - 依赖：T10.1、T10.2、T2.2。
  - 验收：切换 `light`/`dark`/`system` 立即影响 app，同时持久化逻辑符合 Host 返回结果。

- [ ] **T10.4：实现 Models 与 Credentials 页面。** 支持 provider、endpoint、protocol、model discovery、reasoning effort、secret configured 状态、credential 写入/清除和模型目录刷新。
  - 依赖：T10.2、T4.5。
  - 验收：secret 不出现在 UI state dump、log、screenshot、错误提示或 readback；模型发现失败只显示 Host 可安全暴露的错误。

- [ ] **T10.5：实现官方 Plugin configuration 页面。** 先完成官方内置的 bash、agent-loop 和 web-search 的原生专用卡片，以官方字段、copy、draft、reset 和 save 语义为准。[14]
  - 依赖：T10.2、T11.1。
  - 验收：三个官方卡片不使用 WebView，save/discard/reset/revision conflict 与 Host fixture 一致。

- [ ] **T10.6：实现 Agent Presets 与 Plugin Inventory。** 支持读取、选择、复制、删除、打开文档、trust/broken/read-only 状态和 inventory 查看；危险 action 须遵循原生确认策略而非凭借新文案改变语义。
  - 依赖：T4.5、T10.1。
  - 验收：Host 只读或无能力时按钮/文案和官方一致；无法写入时没有误导性的成功状态。

## 11. 第三方插件：Native UI Manifest、Adapter Registry 与极少数 Web fallback

官方浏览器插件依靠 React/Cordis card 注册，并不存在可以自动映射到 Swift UI 的通用描述模型。[14] 因此第三方兼容必须被产品化，不可作为后期临时例外。

- [ ] **T11.1：定义 `NativeUIManifest` v1。** 至少声明：`pluginId`、`hostBuildRange`、`manifestVersion`、`kind`、`localeResources`、`sections`、`fields`、`groups`、`order`、`secretRoles`、`validation`、`actions`、`requiredCapabilities`、`webFallbackAllowed`、`integrity`。
  - 依赖：T0.2、T10.2。
  - 验收：manifest 有 JSON Schema、签名/哈希校验、版本升级规则和负面 fixture；未通过完整性检查的 manifest 不加载。

- [ ] **T11.2：实现 `NativeSchemaForm`。** 支持官方可描述的 text、number、toggle、select、secret、path、group、help、reset、save/discard 和 read-only 字段；字段排列严格由 manifest 指定。
  - 依赖：T11.1、T10.2。
  - 验收：任意 manifest field 不会导致代码执行；schema 不支持的字段明确标记为 unsupported，而不是自行猜测界面。

- [ ] **T11.3：实现 `SwiftAdapterRegistry`。** 用插件 ID 和 manifest adapter ID 映射经审查的 native renderer；允许复杂插件以一段 Swift feature 复刻官方 UI。
  - 依赖：T11.1。
  - 验收：adapter 的可用性、最低 Host build、测试 fixture 和 fallback 原因均可枚举。

- [ ] **T11.4：实现插件兼容矩阵。** 列出每个检测到的插件的分类、UI 表面、支持等级、Host version、native manifest/adapter、fallback 许可和原因。
  - 依赖：T11.1、T11.3。
  - 验收：用户和开发者均可查看“为什么这个插件没有原生设置页”；不会把 silent absence 误导为无配置。

- [ ] **T11.5：实施 `PluginWebHost` POC。** 只有在目标插件被标注 `web-only` 且经过明确审计后，才创建 isolated WebView。限制为 loopback same-origin、禁止远程导航、禁止注入脚本、禁止全局 session UI、禁止读取不属于插件的本地资源。
  - 依赖：T11.4。
  - 验收：网络 policy test 阻断外站、file URL、未知 scheme 与 popup；默认安装零 WebView；启用 fallback 有可见的插件名与原因。

- [ ] **T11.6：验证单卡片可嵌入性。** 先验证官方 React card 能否在不加载完整 Web plugin tree 的情况下运行；若不能，明确记录它需完整 settings surface，并重新评估 fallback 的内存、隔离和用户体验成本。
  - 依赖：T11.5。
  - 验收：POC 得出 `single-card` 或 `full-settings-surface` 的实测结论；未通过隔离门时不发布 fallback。

- [ ] **T11.7：禁止 fallback 侵入核心 UI。** 会话、侧栏、官方设置、模型、凭据和工具页面绝不能借“插件兼容”恢复为 WebUI。
  - 依赖：T11.5。
  - 验收：运行时 diagnostics 报告核心 WebView 数量始终为 0；CI UI test 覆盖该不变量。

## 12. 测试、视觉回归、性能与安全

原生重写必须由协议与状态机正确性驱动，而不是依赖人工肉眼检查。视觉、无障碍和性能测试同等重要，尤其是流式 Markdown、长历史、工具输出和高频 SSE。

- [ ] **T12.1：建立 raw-event fixture 管线。** 从官方 e2e/test fixtures 或经审计的录制会话导出 anonymized JSON，覆盖 happy path、错误、重连、并发、长会话和未知节点。
  - 依赖：T4.6、T6.4。
  - 验收：fixture 可离线复放；不含用户 secret、私人路径、API key 或未经许可的对话内容。

- [ ] **T12.2：建立 reducer snapshot tests。** 对每个 raw event append 后的 node snapshot、turn/step boundary、projection value、queue 和 pending interaction 做断言。
  - 依赖：T6.5、T6.6。
  - 验收：已支持 node 类型的状态覆盖率和负面 fixture 清单可追踪；未知 event 不导致崩溃。

- [ ] **T12.3：建立 transport chaos tests。** 注入迟到 response、重复 SSE frame、frame 乱序、SSE 中断、Host restart、HTTP timeout、settings conflict、cancel race。
  - 依赖：T4.6、T6.7。
  - 验收：状态最终收敛，且没有重复消息、重复授权、错误回滚或无限 reconnect。

- [ ] **T12.4：建立官方布局 golden tests。** 按 T2.5 场景在 1280×840、1024×720、窄窗口、light/dark/system、Reduce Transparency、Increase Contrast、Reduce Motion 下捕获 Swift UI。
  - 依赖：T2.6、T5–T10。
  - 验收：报告同时提供布局树差异、token 差异、截图差异和 Glass 例外说明。

- [ ] **T12.5：建立 macOS 自动化 UI tests。** 覆盖键盘导航、VoiceOver labels、焦点、拖动 divider、composer、approval、settings save/discard、plugin status 和 fallback policy。
  - 依赖：T5.6、T8–T11。
  - 验收：主要路径无鼠标可完成；每个 icon-only action 有 accessibility label。

- [ ] **T12.6：性能基准。** 至少测量启动到 ready、首个 history tail、流式 10k chunks、1,000 条历史、长工具输出、窗口 resize、侧栏折叠和多个 custom glass controls。
  - 依赖：T8–T10。
  - 验收：建立目标上限和 Instruments trace；任何 benchmark 回退需标注原因并评审。

- [ ] **T12.7：安全审查。** 审查 loopback trust、RPC 内容类型、open path、下载、Markdown URL、附件、插件 manifest、credential 内存生命周期、日志红脱敏和 PluginWebHost navigation policy。
  - 依赖：T3–T4、T8.3、T10.4、T11。
  - 验收：安全 checklist 全部通过；发现的风险不以“仅本地运行”为理由跳过。

## 13. 构建、签名、发布与升级治理

- [ ] **T13.1：迁移构建脚本。** 更新 `assemble.sh`、`repair-backend.sh` 与 release workflow，使其组装原生 app、固定 Host payload、生成 `SupportedHostBuilds.json`、打包 spec assets 并执行 smoke tests。
  - 依赖：T3.6、T12.1。
  - 验收：clean environment 可从零构建；构建产物清单可追溯到 Node、dsh、spec、App 源提交。

- [ ] **T13.2：实行代码签名与公证。** 从当前 ad-hoc 签名路径迁移为 Developer ID 签名、Hardened Runtime、公证和 stapling；若暂不具备凭证，应将其显式设为 release blocker。
  - 依赖：T13.1。
  - 验收：安装后不需要绕过 Gatekeeper；签名验证与 notarization status 在 CI 中被检查。

- [ ] **T13.3：建立升级流程。** 更新 DSH Host 必须经过“拉取官方 commit → 生成/审核 OfficialUISpec → 更新 DTO → 契约回归 → reducer 回归 → golden test → accessibility/performance → 支持矩阵提交”的顺序。
  - 依赖：T2、T4.6、T12。
  - 验收：任何 Host payload 升级 PR 都必须关联 spec revision、fixture revision 和测试报告。

- [ ] **T13.4：建立发布前禁用开关。** 对高风险未完成表面用 feature flag 保持隐藏或只读，绝不以半完成的“自创占位页面”替代官方 UI。
  - 依赖：T1.2、T2.2。
  - 验收：未实现功能不会显示虚假的成功 UI；feature flag 有 owner、到期条件和删除计划。

## 14. 推荐的合并顺序与里程碑门

以下顺序用于避免在没有 Host 契约和状态机正确性的情况下提前堆叠 SwiftUI 页面。

| 门 | 必须完成的任务 | 可以开始的后续工作 | 禁止提前开始的工作 |
|---|---|---|---|
| M0：边界锁定 | T0、T1.1–T1.2。 | Spec 提取、Host 拆分。 | 大规模 SwiftUI 重画、任何 CSS 注入优化。 |
| M1：Host 可控 | T2.1、T3.1–T3.4、T4.1–T4.5。 | 原生 shell、session store。 | 用 UI 假数据伪造已连接状态。 |
| M2：协议可信 | T2.2–T2.5、T4.6、T6.1–T6.4。 | 侧栏、基础聊天 renderer。 | 复杂工具/插件页面。 |
| M3：核心零 WebView 闭环 | T5、T7、T8.1–T8.6、T12.1–T12.3。 | 扩展 nodes、设置页。 | 将主聊天或官方设置退回 WKWebView。 |
| M4：官方 UI 覆盖 | T8.7、T9、T10、T12.4–T12.6。 | 第三方插件与发布准备。 | 宣称“完整复刻”而不覆盖官方测试场景。 |
| M5：插件受控兼容 | T11、T12.7。 | 公测与签名发布。 | 将任意第三方 React card 无审计地载入。 |
| M6：可发布 | T13、所有 D0–D5。 | 正式 Release。 | 未签名/未公证、未知 Host build 写入、未通过无障碍门禁。 |

## 15. 每次 PR 的检查清单

- [ ] PR 指向一个已编号的本 TODO 任务，并声明影响的 Host build/spec revision。
- [ ] 若修改 UI，提交 OfficialUISpec 来源、locales/token/layout 变更和对应 golden 场景。
- [ ] 若修改 RPC/SSE，提交 DTO diff、contract fixtures、取消与错误路径测试。
- [ ] 若修改 reducer，提交 event replay snapshot 与未知 event 安全处理测试。
- [ ] 若使用 `glassEffect`，说明其属于导航/控制层的理由、容器策略和辅助功能行为。
- [ ] 若触及插件，更新 compatibility matrix；如果使用 fallback，附上 manifest、隔离测试与明确原因。
- [ ] 不含自创核心 UI 文案、私有色彩/间距常量、Web CSS 注入或主应用 WebKit 依赖。
- [ ] 日志、fixture、截图和 error message 不泄露 secret、用户内容或私有文件路径。
- [ ] 在支持的 macOS 26 配置下通过单元、契约、UI、视觉、无障碍与性能门禁。

## References

[1]: https://github.com/deepseek-ai/deepseek-harness/blob/99f6f02fecdb7dff40c3fbc9470f5907c29f74ca/README.zh.md "DeepSeek Harness 官方 README"
[2]: https://github.com/deepseek-ai/deepseek-harness/blob/99f6f02fecdb7dff40c3fbc9470f5907c29f74ca/docs/architecture.md "DeepSeek Harness Architecture"
[3]: https://github.com/deepseek-ai/deepseek-harness/blob/99f6f02fecdb7dff40c3fbc9470f5907c29f74ca/packages/bundle/web-app/cordis.patch.yml "官方 Web profile 组合清单"
[4]: https://github.com/deepseek-ai/deepseek-harness/blob/99f6f02fecdb7dff40c3fbc9470f5907c29f74ca/packages/client/ui-layout/src/client/AppFrame.tsx "官方 AppFrame"
[5]: https://github.com/deepseek-ai/deepseek-harness/blob/99f6f02fecdb7dff40c3fbc9470f5907c29f74ca/packages/client/ui-layout/src/client/columns.ts "官方三栏布局算法"
[6]: https://github.com/deepseek-ai/deepseek-harness/blob/99f6f02fecdb7dff40c3fbc9470f5907c29f74ca/packages/client/ui-theme/README.md "官方主题与 token 机制"
[7]: https://github.com/deepseek-ai/deepseek-harness/blob/99f6f02fecdb7dff40c3fbc9470f5907c29f74ca/packages/host/apiproxy/README.md "官方 Host API Proxy 与客户端 wire contract"
[8]: https://github.com/deepseek-ai/deepseek-harness/blob/99f6f02fecdb7dff40c3fbc9470f5907c29f74ca/packages/client/runtime/src/client/contract/conversation.ts "官方 Conversation Node Contract"
[9]: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass "Apple: Adopting Liquid Glass"
[10]: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views "Apple: Applying Liquid Glass to custom views"
[11]: https://developer.apple.com/videos/play/wwdc2025/310/ "Apple WWDC25: Build an AppKit app with the new design"
[12]: https://github.com/deepseek-ai/deepseek-harness/blob/99f6f02fecdb7dff40c3fbc9470f5907c29f74ca/packages/client/ui-sidebar/README.md "官方 Sidebar 模块说明"
[13]: https://github.com/deepseek-ai/deepseek-harness/blob/99f6f02fecdb7dff40c3fbc9470f5907c29f74ca/packages/client/ui-conversation/README.md "官方 Conversation UI 模块说明"
[14]: https://github.com/deepseek-ai/deepseek-harness/blob/99f6f02fecdb7dff40c3fbc9470f5907c29f74ca/packages/client/ui-settings-plugins/README.md "官方插件设置机制"
