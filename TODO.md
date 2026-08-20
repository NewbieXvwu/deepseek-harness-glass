# DeepSeek Harness Glass：原生 Swift macOS 客户端实施 TODO

**目标分支：** `main`

**工作模式：** 用原生 SwiftUI + AppKit 重写官方 DeepSeek Harness WebUI；核心界面、官方内置设置与会话流不得使用 WebView；仅在经审计且技术上无法原生化的第三方插件页面中允许严格隔离的例外 WebView。

**目标系统：** macOS 26+、Xcode 26+、Apple Silicon。

**官方基线：** `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534`。任何升级均须通过本文件定义的协议、视觉与无障碍门禁后，才可加入支持矩阵。[1] [2]

> **首要原则：** 本项目不是替换 CSS 或包装网页，而是保留 DeepSeek Harness Host、替换 Browser Client。官方布局常量、文本、字段顺序、状态机与交互语义是规格来源；Liquid Glass 只增强 macOS 的窗口、导航和必要操作控件，不能借机添加任何非官方的产品文案、页面、信息层级或装饰。

## 项目宪章：质量水准、开发范式与工作经验

本节是本项目的**强制执行协议**，优先级高于“尽快做出能运行的页面”或“先合并以后再修视觉”。任何新会话、协作者或自动化代理在修改代码前，都必须先阅读本节和下方任务清单；如果实现不能满足本节要求，就不得把任务标记为完成，也不得以“平台差异”“截图缩放”“以后再收敛”为理由带着已知差异推进。

### 1. 质量目标不是“像”，而是可审计的严格复刻

项目目标是**专业级、可持续维护、可回归验证的原生客户端**，不是临时演示、静态模型图、WebUI外壳或凭感觉仿制。官方 WebUI 的布局、文案、图标、排版、状态、交互顺序、错误路径和可见反馈均属于规格；原生实现可以使用 SwiftUI、AppKit 和 macOS 26 Liquid Glass，但不得因为原生化而自创产品文案、信息层级、按钮顺序、装饰性控件、私有色彩或未经批准的尺寸。

> **质量底线：** “能编译”“能启动”“D0/D1通过”只是必要条件，不是视觉验收。只要同状态、同视口配对截图中仍能观察到元素大小、位置、间距、端帽、描边、分界线深浅、遮罩、颜色、字体、焦点、相对时间或文案差异，就必须立即修复并重新截图，不能仅记录问题后推进下一阶段。

### 2. 每个界面必须遵循官方来源到像素证据的闭环范式

每个界面或交互状态都必须按同一顺序工作：先锁定官方 commit 并阅读实际源码；再启动或重建官方 WebUI fixture；捕获相同状态和相同视口的官方基线；记录 DOM 几何、文案、CSS token、图标来源和交互状态；实现原生视图；在相同状态、相同视口和相同颜色/辅助功能条件下生成原生截图；将官方与原生截图并列、放大局部检查；列出所有可观察差异；立即修改代码；重新运行D0/D1与macOS-26 CI；只有确认差异闭环后才可将场景标记为验收通过。

不能用另一种状态的官方截图与原生截图配对，不能用不同视口或不同缩放比例掩盖几何差异，不能只比较整图而跳过按钮端帽、输入边缘、细分界线和阴影等局部细节。用户指出的动作按钮两侧重复/断裂描边就是典型实例：问题必须被当作真实合成缺陷处理，直到单层连续端帽与官方目标一致，而不是归咎于抗锯齿或系统差异。

### 3. 官方源码是唯一可回链的设计规格

任何可见文本、图标、顺序、布局常量、主题 token、状态文案和交互语义都必须记录官方源文件路径、锁定 commit 和必要的行号或CSS选择器。SwiftUI View 不得散落未经登记的产品文案、颜色、间距和圆角字面量；应通过 `OfficialUISpec`、语义化 token、官方资产和强类型状态使用。若官方实现本身通过插件、slot、schema或Host能力决定可见内容，原生端必须保留这种可解释性，不能用自创的静态占位文本“填满”页面。

### 4. 原生化、Host真源和Liquid Glass边界

核心 UI 必须完全原生。会话、工作区、官方设置、模型、凭据、工具、审批、问题、命令和插件配置不得通过 WebView、DOM、JavaScript、CSS注入或网页截图完成。Host 是唯一业务真源；所有读写通过官方 loopback RPC/SSE 和类型化 DTO，原生端不建立与 Host 冲突的业务数据库。Liquid Glass 只用于导航、侧栏、工具栏、inspector、popover、sheet和官方已有的操作控件，不得将内容层整体覆盖为玻璃，也不得借玻璃效果创造官方没有的视觉层级。第三方插件必须先判断是否能用 `NativeUIManifest`/`SwiftAdapter` 原生化；只有明确审计为无法原生化的 web-only 插件，才允许进入严格隔离的 `PluginWebHost` 例外。

### 5. “完成”的判定必须有实现、来源和回归证据

每个 TODO 条目只有在代码实现、官方来源映射、必要测试、同状态官方/原生视觉证据、D0/D1门禁和适用的 macOS-26 GitHub Actions 回归全部闭环后才可勾选。部分DTO、单一fixture、局部截图、能编译的占位页面或“基础设施已存在”均不足以勾选高层功能。任务若包含多个验收条件，必须全部满足；无法证明的部分保持未勾选，并在进度说明中明确阻塞点和下一步，而不是用乐观表述掩盖缺口。

每次视觉修复提交都应保留：官方基线、原生截图、放大裁切或几何测量、差异记录、修复提交和对应CI运行号。CI失败时必须诊断并修复；不能把“本地看起来正常”当作macOS-26 runner证据。提交信息应能说明修复的可观察差异，例如“single capsule action path”或“official neutral disabled token”，而不是使用无法追踪的泛化描述。

### 6. 失败关闭、审慎推进与跨会话经验

遇到官方服务未启动、fixture状态不一致、Host版本未验证、截图缺失、CI失败、认证失效或工具异常时，工作流必须停止在当前阶段并记录事实；不得猜测、伪造基线或继续勾选下游任务。恢复后应先复核最后一个成功状态，再继续执行。任何“看起来还能工作”的恢复都不等于验收恢复；必须重新运行相关门禁和视觉配对。

本文件是唯一的跨会话续跑入口。新会话不得依赖未同步的口头摘要、临时聊天上下文或外部 CONTINUE 文档；应从本文件读取目标、质量标准、已勾选条目、最新提交、CI运行号、未完成阶段和下一步命令。每次跨会话交接都必须把新的事实、失败原因、已修复差异和下一步写回本文件，并先提交同步后再交接。

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

- [x] **T0.1：在 README 与贡献指南中写入 D0–D5。** 说明 `WebKit` 只能位于 `PluginWebHost` 目标中，禁止在主应用 target 或任何核心 renderer 中导入。
  - 依赖：无。
  - 验收：CI 的静态规则可阻止 `glass/Sources/Core/**`、`glass/Sources/UI/**`、`glass/Sources/Features/**` 导入 `WebKit`。

- [x] **T0.2：确定产品支持边界。** 第一版仅支持一个固定的 DSH package/commit 与其捆绑 Node 运行时；不支持任意外部 `dsh web` 实例作为写入目标。
  - 依赖：T0.1。
  - 验收：`SupportedHostBuilds.json` 包含 package version、git commit、protocol fixture revision、Node version、最小 App version 和验证日期。

- [x] **T0.3：确定“官方复刻”的判定层级。** 把“文本、布局、状态、交互”与“系统渲染的玻璃折射和阴影”分开。前四项严格比对；后者只验证系统 API 使用、层级、可读性和辅助功能响应，不追求逐像素模仿 CSS。
  - 依赖：T0.1。
  - 验收：测试计划中有明确的结构差异阈值、截图场景与人工审阅准则。

## 1. 仓库与模块化基础

现有项目将主要逻辑集中在 `glass/Sources/main.swift`。重写前应拆分生命周期、Host 通信、状态、界面和插件兼容层，避免将 SwiftUI、AppKit、网络、进程与业务 reducer 再次耦合在一个文件中。

- [x] **T1.1：保留现有项目的可复用运行时资产。** 列出并迁移内嵌 Node、dsh payload、构建脚本、Info.plist、图标、签名与 release workflow；保留 `DSH_HOME`、日志目录、端口复用、自动恢复、菜单栏常驻和优雅退出的意图。
  - 依赖：T0.2。
  - 验收：迁移清单将当前 `main.swift` 的每项职责标注为 `保留`、`替换` 或 `删除`；没有未分类的隐式行为。

- [x] **T1.2：建立目标目录结构。** 推荐结构如下，实际命名可微调，但层级职责不可混淆。

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

- [x] **T1.3：删除旧 WebUI 路径的迁移分支。** 初期可临时保留 legacy build target 用于官方对照，但主应用 target 不再链接 `GlassWebView`、`WKUserScript`、CSS 注入、`evaluateJavaScript` 与页面 DOM mutation 逻辑。
  - 依赖：T1.2、T3.6。
  - 验收：`grep -R "WKWebView\|WKUserScript\|evaluateJavaScript\|MutationObserver" glass/` 只命中 `Plugins/PluginWebHost` 或 legacy 对照 target；核心功能可运行。

## 2. 锁定官方规格：文本、token、布局和行为

“不得自创界面文本、排版”必须由版本化规格和自动化工具保证。官方 Web client 的 `locales.ts`、主题 token sheet、`ui-layout` 常量、组件结构与 e2e 场景共同组成规格来源；不能将设计信息从网页截图中手工猜测。[3] [4] [5] [6]

- [x] **T2.1：创建 `OfficialUISpec` 元数据格式。** 至少包含 `sourceCommit`、`localeRevision`、`tokenRevision`、`layoutRevision`、`fixtureRevision`、`generatedAt` 和生成器版本。
  - 依赖：T0.2。
  - 验收：所有 Swift UI 测试都读取 `OfficialUISpec` 的 build ID；当 spec 与 Host build 不匹配时测试失败。

- [x] **T2.2：提取官方 locale。** 从官方 `packages/client/**/locales.ts` 和相关 locale package 导出字符串，保留 key、语言、插值参数、复数规则、来源路径与源 commit。
  - 依赖：T2.1。
  - 验收：核心 Swift View 不出现自行撰写的官方产品文案；字符串 lint 能发现未登记字面量；中英两种语言至少能解析。

- [x] **T2.3：提取主题与排版 token。** 已从锁定的 `packages/client/ui-theme/src/styles/design-platform.css` 可重现生成 162 个 `--dsw-*` light/dark token；`official-theme-tokens.json` 保留原始 CSS 名、raw/resolved value、source line、commit、内容 revision 和与 T2.1 build 绑定的 source-input revision，`OfficialThemeCatalog.swift` 生成 `OfficialColorToken` 与自适应 light/dark `Color` bridge。`OfficialUISpec.Token`、`Spacing`、`Radius`、`Geometry`、`Shadow` 与 `Typography` 承载原生语义调用，核心 UI 不再直接构造可见产品颜色或 `.font(.system(...))`。
  - 依赖：T2.1。
  - 验收证据：`generate_official_theme_tokens.py`、`check-official-theme-tokens.py` 与 `OfficialUISpecBuildTests.testGeneratedOfficialThemeCatalogMatchesLockedBuildAndResolvesSchemes` 已覆盖可重现性、162 token 数、commit、build revision 及 light/dark RGBA；macOS-26 [run 32169307451](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32169307451)（commit `2fbdeb7`）成功完成全部门禁、SwiftPM 编译、XCTest、原生截图与官方视觉配对。人工对照及量化报告已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`；该基础设施变更未新增可观察 welcome 回归，既有 `report-only` 差异仍明确保留给后续 UI 场景关闭。

- [x] **T2.4：固化官方三栏算法。** `OfficialColumnLayout.resolve` 与锁定 `packages/client/ui-layout/src/client/columns.ts` 的三段让步链保持一致：侧栏不让步、详情先缩至 300px、再派生关闭详情、最终中心列吸收余量。`generate_official_column_layout_fixtures.ts` 通过锁定 Node 24/tsx 直接调用官方 `computeColumns` 生成 30 个 fixture，覆盖默认、收缩、自动关闭、恢复、closed rail、viewport 极限、clamp 与小数 round 边界；fixture 保留源路径、commit 和 SHA-256，作为 GlassSpec resource 与 app resource 双路径加载。
  - 依赖：T2.1。
  - 验收证据：`check-official-column-layout-fixtures.py` 对官方函数重生成并逐字节比对，`OfficialUISpecBuildTests.testOfficialColumnLayoutMatchesEveryGeneratedComputeColumnsFixture` 逐例比对 Swift 输出，另有常量断言。macOS-26 [run 32171801347](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32171801347)（commit `4f6c7e5`）成功完成 fixture gate、SwiftPM target 编译、XCTest、直接 Swiftc app 装配、截图和官方视觉对照；人工复核已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`，无 renderer 变更造成的新可观察回归，既有 welcome `report-only` 差异仍保留给后续 UI 场景关闭。

- [x] **T2.5：建立官方交互场景目录。** 已建立 `official-interaction-scenes.json`（13 个必覆盖场景）与 `T2.5-official-scene-source-notes.md`。每个条目绑定锁定官方 e2e、行区间、初始 Host replay/seed、窗口尺寸、颜色模式、辅助功能模式、动作、可见文案、布局树、稳定 ARIA baseline、同状态官方 PNG baseline contract 与 native entry；覆盖启动、无工作区、空会话、流式、tool details、approval、question、queue、settings、窄 rail、details close/reopen、dark cascade 和 reload recovery。
  - 依赖：T2.2–T2.4。
  - 验收证据：`check-official-interaction-scenes.py` 强制 13 项 required coverage、完整 per-scene schema 和上游 e2e/replay/ARIA 路径存在；macOS-26 [run 32173433660](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32173433660)（commit `09afcc5`）成功执行场景 gate、全门禁、SwiftPM 编译、app 组装、截图与官方配对。人工复核已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`；目录/gate 改动不改变 renderer，既有 welcome `report-only` 差异未被错误归类为完成。每个目录场景的 renderer 像素收敛仍由其下游 UI TODO 的同状态 official/native pair 完成。

- [x] **T2.6：定义视觉差异策略。** 普通布局层使用结构树断言和截图差异；系统 Glass 区域使用位置、尺寸、层级、对比度和系统状态断言，不对系统动态折射作像素级失败判定。
  - 依赖：T2.5。
  - 验收：视觉报告能够区分“官方布局偏移”与“系统材质自然差异”。

## 3. Host 生命周期、版本验证与诊断

官方 Web profile 由 Node Host 提供 API、SSE、静态页面与 plugin graph。原生客户端应只使用前两者来承载业务，前端静态资源仅在 WebView 插件 fallback POC 时出现。[1] [7]

- [x] **T3.1：拆出 `HarnessHostController`。** `GlassCore` 的 `HarnessHostController` 现独立管理 Node/payload 位置、运行时 DSH_HOME/log 目录、`dsh web --port 0`、受限 127.0.0.1+port announcement 解析、`host.describe` ready probe、20 秒启动 announcement timeout、日志、手动/异常终止的一次恢复、停止抑制恢复和退出清理；UI target 不包含进程启动逻辑。
  - 依赖：T1.2。
  - 验收证据：新增无 UI `GlassCoreTests` target 与 `HarnessHostControllerTests.testOwnedHostStartsReusesAndStopsWithoutLeavingProcess`，使用 CI 已验证 rc.7 Node/payload 真实启动、ready、重复 start 同 PID 复用、stop、PID 不存在、DSH_HOME/log 落盘。macOS-26 [run 32175400591](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32175400591)（commit `229d0d9`）执行该测试成功（3.488s），并完成全门禁、SwiftPM/Swiftc 编译、原生截图与官方配对；人工复核记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`，Host-only 改动未新增可观察 renderer 回归，既有 welcome `report-only` 差异仍由后续 UI TODO 关闭。

- [x] **T3.2：实现 Host build 验证。** `HostBuildVerifier` 以 `SupportedHostBuilds.json`、锁定 official commit、dsh/package frontend manifest 版本和生成 UI spec revision 验证 payload；`HostBuildTrust` 将结果显式区分为 verified、unverified 与不可启动，绝不由 URL/port 猜测。verified metadata 随 `HostConnection` 传入每个 API transport；unverified 默认仅允许 `host.describe`，拒绝 mutation/response，只有显式 developer write override 才放行。
  - 依赖：T0.2、T3.1。
  - 验收证据：`HarnessHostControllerTests.testUnknownBuildBecomesUnverifiedAndDefaultsToWriteProtection` 使用真实固定 payload 和故意不匹配 catalog，断言 unverified、无 ready PID、`session.prompt` 默认被拒绝且 override 才允许；`testOwnedHostStartsReusesAndStopsWithoutLeavingProcess` 继续验证真实 verified Host 可 ready。macOS-26 [run 32178347783](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32178347783)（commit `ae35887`）两项 Core test 全通过（2.790s）、完成全门禁、SwiftPM/Swiftc 编译、截图和官方配对；人工复核记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`，Core trust 改动未新增 renderer 回归，既有 welcome `report-only` 差异仍由后续 UI TODO 关闭。

- [x] **T3.3：定义显式生命周期状态。** `HostLifecycleState` 现显式覆盖 `idle`、`probingExternal`、`unverified`、`startingOwned`、`verifying`、`ready`、`recovering`、`failed`、`stopping`；announcement、termination 分类和 startup timeout 直接 pattern-match state，Core 中无 `state.endpoint == nil` 推断。`HarnessHostController` 集中发布有界 `HostLifecycleTransition` ledger 和日志；external probe 仅使用 diagnostics-only `host.describe`，不会授予 build authority。
  - 依赖：T3.1。
  - 验收证据：`HostLifecyclePresentation` 仅使用生成的官方 locale `locale.loading`、`locale.load.failed` 和 `locale.retry` 导出启动/失败/重试 UI 模型；`testLifecycleTransitionsAreLoggedAndPresentationUsesOfficialLocale` 以真实 rc.7 Host 验证完整 owned transition edge、日志和 locale presentation。macOS-26 [run 32180108638](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32180108638)（commit `363b534`）3 项 Core tests 全通过（3.519s），并完成全门禁、SwiftPM/Swiftc 编译、截图和官方配对；人工复核记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`，Core 生命周期改动未新增 renderer 回归，既有 welcome `report-only` 差异仍由后续 UI TODO 关闭。

- [x] **T3.4：重做诊断与日志。** `HostDiagnosticRecorder` actor 汇聚 Core readiness/probe、API RPC 和 Host SSE 的时间/错误事实；`HostDiagnosticSnapshot.copyableText()` 提供 Host build、port、DSH_HOME、owned PID/ownership、last SSE、last RPC error、protocol fixture revision、plugin compatibility 和 lifecycle。`HostLogRedactor` 在记录前遮蔽 API key、Cookie、token、secret、password、Bearer 与 URL user-info；不保存 request/response payload 或 settings 原文。
  - 依赖：T3.2、T3.3。
  - 验收证据：`testDiagnosticsAreCopyableCompleteAndRedacted` 覆盖全部必填字段及 API key/cookie/Bearer/URL credential/secret 全部不泄露；macOS-26 [run 32181832902](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32181832902)（commit `e93273a`）4 项 Core tests 全通过（4.392s），完成全门禁、SwiftPM/Swiftc 编译、截图和官方配对。人工复核记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`，diagnostics-only 改动未新增 renderer 回归，既有 welcome `report-only` 差异仍由后续 UI TODO 关闭。

- [x] **T3.5：实现下载与导出替代路径。** `SessionLogExporter` 通过 `URLSessionDownloadTask` 调用锁定 `DownloadsApi.sessionLog` 的 host-only GET `api/session.export`；下载 completion 在返回前将短生命周期临时文件原子移入受控 `.partial` staging，随后在用户 Downloads/DeepSeek Harness（无 Downloads directory 时 Documents、再无则 temporary）采用 Content-Disposition 安全文件名和 ` (2)` 递增冲突策略落盘。`DownloadsAPI.exportSessionLog` 只向 Feature 暴露 typed export；UI 层 `NativeSessionLogExportOpener` 仅对已落盘 `SessionLogExport` 调用 AppKit workspace 打开。unverified diagnostic-only Host 不能生成会物化本地文件的 download URL，保持 T3.2 信任边界。
  - 依赖：T3.1、T4.4。
  - 验收证据：`SessionLogExporterTests` 以 URLProtocol 运行真实 `URLSessionDownloadTask`，覆盖官方 attachment GET、UTF-8 Content-Disposition name、同名 ` (2)`、staging-file 生命周期、404、取消分类的基础 URLSession path、活动挂起 download task 的最终 cancellation（精确映射为 `DSHTransportError.cancelled`），以及 unverified Host 的 URL 拒绝。macOS-26 [run 32208063025](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32208063025)（commit `0d57ee4`）通过初始完整 source/module/native-only/transport gates、SwiftPM/Swiftc 编译、native export/Core tests、app 组装、snapshot 和官方配对；最终 cancellation regression 由 macOS-26 [run 32208551395](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32208551395)（commit `cad9cea`）成功验证，且该当前成功工件已完成人工 visual-review。证据与分类均记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`。T3.5 无 renderer 改动，welcome 既有差异继续明确为 `report-only`，不构成 UI 场景视觉完成。

- [x] **T3.6：Host + transport 冒烟门。** `HarnessHostTransportSmokeTests` 以 CI 注入的固定 rc.7 Node/payload 启动 verified `HarnessHostController`，经唯一 `HarnessAPIs` composition root 执行只读 `host.describe`、`session.create`→`session.list`，并以真实 mux WebSocket 接收 `session/subscribed`。测试主动 SIGTERM owned Host，验证 lifecycle transition ledger 的 `ready → recovering → startingOwned → verifying → ready`、旧 endpoint 的 retryable network + copyable diagnostics、新 port verified reconnect、只读 `session.models` cold-resume 后的新 mux `session/subscribed`。生产 `NativeSessionStore.open` 同样先经 typed `SessionsAPI.models` 恢复 cold selected session；`NativeShellPresentation` 在 verified endpoint 更换时保留选择并重新打开，旧 HTTP/WebSocket carrier 不会被复用。
  - 依赖：T3.1–T3.4、T4.1–T4.5。
  - 验收证据：同一 XCTest 使用 URLProtocol 503 carrier，断言 `invalidHTTPStatus(503)` 保留并映射 retryable；真实 owned Host 终止后旧 facade 的 network 故障同样为 retryable 且进入 `HostDiagnosticRecorder.lastRPCError`，不会逃逸为未处理异常。macOS-26 [run 32211858885](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32211858885)（commit `b12be6e`）通过新的独立 smoke gate、所有静态/协议/module gates、SwiftPM/Swiftc、全 Core regressions、app 组装、snapshot 与官方 visual pairing。该成功工件 contact sheet 已人工复核并记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`；本项无 renderer 修改，welcome 差异持续为明确的 `report-only`，不构成 UI 场景视觉完成。

## 4. HTTP RPC、SSE 与强类型契约

官方 API 的请求/响应通过 `rpcId` 关联，并将 ClientRequest、ServerResponse、ServerRequest、ClientResponse 映射在 HTTP POST 与 SSE 上。会话、工作区、设置、凭据、模型、命令和远程事件都应经过同一个可测试传输层。[7]

- [x] **T4.1：定义 `RPCEnvelope` 与通用错误模型。** 以锁定 `packages/client/connection/src/rpc.ts` 的 request/response 契约为来源，`RPCEnvelope` 汇总 ClientRequest/ServerResponse/ServerRequest/ClientResponse 并保留 `rpcId` 与 closed success/business-error branch；`RPCBusinessError` 与 `DSHTransportError` 将 HTTP、network、timeout、cancelled、content/envelope/rpcId mismatch、unverified build 统一投影为 retryable、requires refresh、requires user correction、unsupported 或 program fault。URLSession 错误不再泛化为 decoding。
  - 依赖：T3.1。
  - 验收证据：`RPCModelsTests` 覆盖 revision conflict、validation、unsupported method、unavailable/internal、429/503/400、timeout/network/cancel/unverified 及 envelope rpcId/business branch。macOS-26 [run 32183487572](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32183487572)（commit `a3d86a3`）成功完成完整 SwiftPM/Swiftc 编译、RPC model/Core Host tests、截图和官方配对；人工复核记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`，Core transport model 改动未新增 renderer 回归，既有 welcome `report-only` 差异仍由后续 UI TODO 关闭。

- [x] **T4.2：生成或维护 Swift DTO。** 从官方 TypeScript/Zod schema 建立受控生成步骤；若第一版手工建模，也必须记录 schema source path 与 fixture revision。`generate_official_rpc_dto_manifest.py` 现从锁定 apiproxy schemas 生成 16-method manifest；`check-official-rpc-dto-manifest.py` 在 CI 强制官方 HEAD、完整 16-method 集、fixture revision 与每个 source SHA 的 fresh-generation 相等。`capture_official_host_dto_fixtures.sh` 在隔离 `DSH_HOME` 启动固定 rc.7 Host，生成每个当前 facade method 的官方 ClientRequest/ServerResponse capture；无效 session/workspace 只使用 schema-valid identifier，保留 Host closed business-error branch，且绝不连接用户配置或凭据。
  - 依赖：T4.1、T0.2。
  - 验收证据：`RPCDTOFixtureTests` 从 GlassCore resource 加载与 `OfficialUISpec.Build` 绑定的 capture，验证 16 条真实 envelope 的 rpcId/type/canonical Codable round-trip、16 个对应 production request DTO 的 typed round-trip、6 个成功 value DTO 与 10 个真实 `RPCBusinessError` branch。macOS-26 [run 32186518136](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32186518136)（commit `944bee3`）通过 manifest gate、完整 SwiftPM/Swiftc 编译、fixture XCTest、Host tests、app 组装、snapshot 和官方配对；人工工件复核已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`。T4.2 无 renderer 改动，welcome 既有差异继续为明确的 `report-only`，不被误记为 UI 场景视觉完成。

- [x] **T4.3：实现 `DSHClientTransport`。** 使用 `URLSession` 实现 JSON POST、Content-Type、请求取消、统一超时、`rpcId` 去重和调用 tracing。`DSHClientTransport` actor 现以注入式、可测试 rpcId generator 分配 id，并在发送前执行 in-flight 与最近 1,024 个已签发 id 去重；任何 duplicate 在抵达 carrier 前被拒绝。每个调用强制 `server-response`/echo rpcId 后才交付，trace 有界保留 method、rpcId、terminal outcome 和脱敏错误类别，绝不保存 payload；cancel/timeout/network/HTTP/content-type 映射沿用 T4.1 taxonomy。
  - 依赖：T4.1、T4.2。
  - 验收证据：`DSHClientTransportTests` 通过 URLProtocol mock carrier 发起 100 个并发 Host RPC，断言 100 个唯一 rpcId、每个 response 仅回到其原始 payload index、100 条成功 trace；另覆盖 duplicate id 在第二次发起前被拒绝且不发送、以及 crossed response rpcId 必须失败而不能交付。native-ui workflow 现将 `glass/Tests/**` 纳入 push/PR paths 并独立运行该 XCTest，避免 test-only 变更绕过 macOS gate。macOS-26 [run 32189390817](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32189390817)（commit `1555ddb`）通过所有门禁、SwiftPM/Swiftc 编译、transport/Host/DTO tests、app 组装、snapshot 和官方配对；人工工件复核已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`。T4.3 无 renderer 变动，welcome 既有差异继续明确为 `report-only`，不构成 UI 场景视觉完成。

- [x] **T4.4：实现 `SSEClient`。** 支持 ServerRequest 帧、断线检测、指数退避、Host restart 后重订阅、最终取消与网络路径变化。锁定 rc.7 `dsh web` 的实际 `/api/events.mux` 与 `/api/events.host` 路由是 trusted WebSocket upgrade（`GET` 会返回 `426 upgrade required`）；因此 carrier 必须使用 `URLSessionWebSocketTask` 逐 frame 解码 official `ServerRequest`，不能将纯 fetch handler 的 in-process `data:` SSE fallback 当作已安装 Host 协议。`SSEFrameParser` 仅保留为 fetch-fixture 兼容测试；`reconnectingStream` 在 WebSocket close 或 transport failure 后以确定性指数退避重开，final cancellation 永远终止。跨 reconnect 的有界 rpcId fence 和按 session 分桶的 `session/event`/`session/projection` monotonic sequence fence 阻止 replay 低序号重复投影，且无 payload trace。
  - 依赖：T4.1。
  - 验收证据：此前 `SSEClientTests` 的可重放 stream、坏 frame、纯 fetch fixture 的 `data:`/comment framing、network reconnect、rpcId/sequence replay fence 与 cancellation 覆盖保持；2026-08-19 对固定 rc.7 payload 的真实 probe 发现 `/api/events.mux` 普通 HTTP GET 返回 `426 upgrade required`，且 source `@deepseek-ai/dsh-client-connection/lib/index.js` 的 `WebSocketDownlinks` 以 `socket.send(JSON.stringify(ServerRequest))` 下行。carrier 已改为 `URLSessionWebSocketTask`，将 http/https endpoint 映射为 ws/wss，逐 message 解码 `server-request`，并将 macOS `NSPOSIXErrorDomain Socket is not connected` 归一为 retryable network 以执行重新连接；纯 SSE parser 只保留为 fetch-fixture coverage。macOS-26 [run 32211858885](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32211858885)（commit `b12be6e`）通过新真实 Host smoke：WebSocket mux `session/subscribed`、SIGTERM 后 close/reconnect trace、new verified endpoint 的 read-only `session.models` cold-resume 与新 mux subscribed；完整门禁、SwiftPM/Swiftc、现有 Core tests、app 组装、snapshot 和官方配对均成功。人工工件复核记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`。T4.4 无 renderer 改动，welcome 既有差异继续明确为 `report-only`，不构成 UI 场景视觉完成。

- [x] **T4.5：建立 API 域 facade。** `HarnessAPIs` 作为 verified Host 的唯一 Core composition root，提供 `SessionsAPI`、`WorkspacesAPI`、`SettingsAPI`、`CredentialsAPI`、`LLMAPI`、`CommandsAPI`（官方 wire path 仍为 `goal.*`）、`SkillsAPI`、`AgentPresetsAPI`、`DownloadsAPI` 与 `HostAPI`。每个 facade 持有受 T3.2 policy 保护的同一 `DSHAPIClient`，封装官方 method path、typed request/value DTO、diagnostics、download URL 或 ClientResponse 处理；`SessionsAPI` 还封装 approval/question response 和 final question cancellation，Feature 不再组装 RPC result JSON。
  - 依赖：T4.3、T4.4。
  - 验收证据：`NativeSplitContainer`、`NativeWorkspaceStore`、`NativeSettingsStore` 与 `NativeSessionStore` 均已迁移为仅持有 `HarnessAPIs` 或对应 domain facade。`check-no-feature-transport.py` 在 CI 拒绝 UI/Session source 使用 `DSHAPIClient`、`DSHClientTransport`、`URLRequest`、`JSONValue` wire constructor 与 RPC envelope/result；其与 module/native-only/DTO provenance gate 一并运行。官方 domain/path/schema 依据已记录于 `notes/T4.5-official-contract-sources.md`。macOS-26 [run 32193851213](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32193851213)（commit `a589305`）通过 boundary gate、完整 SwiftPM/Swiftc 编译、Host/RPC DTO/concurrent transport/SSE tests、app 组装、snapshot 和官方配对；成功 artifact digest 为 `sha256:c2cdd8052c9eaa13d984b49039c1136f544f312421a012b79378488810cc5040`。人工工件复核已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`：T4.5 无 renderer 变动，welcome 既有差异继续明确为 `report-only`，不构成 UI 场景视觉完成。

- [x] **T4.6：建立 transport 契约回归。** `generate_official_transport_contract_manifest.py` 从锁定 apiproxy schemas 生成 12-contract baseline，覆盖 `session.history`、`session.prompt`、`session.cancel`、`session.models`、`settings.describe`、`settings.mutate`、`credentials.set`、`llm.providers`、mux/host SSE 与 RPC business-error/revision-conflict。`check-official-transport-contract.py` 每次 CI 从官方 root fresh-generate candidate；对于新增/删除 contract、字段、symbols、enum、source SHA 或签名均输出 `ADDED`/`REMOVED`/`MODIFIED` 审阅 diff 并失败。`generate_official_transport_contract_fixtures.py` 生成只含非 secret fixture 值的 schema-valid ClientRequest/ServerResponse/ServerRequest replay resource；`session.models` 亦已获得 production request/value DTO 与 `SessionsAPI.models` facade。
  - 依赖：T4.5。
  - 验收证据：`TransportContractRegressionTests` 强制 fixture commit/revision，验证 8 个必覆盖 RPC 的 canonical envelope correlation、8 个 production request DTO typed round-trip、history/cancel/models/settings/credentials/LLM success value 解码、`session-not-found` 与 `settings-conflict` closed branch（含 ns/expected/actual）、以及 `session/event`、`session/projection`、`host/session-status` ServerRequest frame。gate 自测另向临时候选插入字段，确定输出 `MODIFIED session.history requestFields: ADDED ...` 并拒绝。macOS-26 [run 32206487624](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32206487624)（commit `8a3aba6`）通过 contract gate、SwiftPM/Swiftc 编译、所有 Core regression tests、app 组装、snapshot 与官方配对；工件包含 baseline/fixture 供审计。人工复核已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`：T4.6 无 renderer 改动，welcome 既有差异继续为 `report-only`，不构成 UI 场景视觉完成。

## 5. 原生窗口、三栏骨架与 Liquid Glass

Apple 建议使用系统导航与标准控件以自动获得 Liquid Glass；在 macOS 上，`NSSplitViewController` 的 sidebar 和 inspector 行为能提供相应的系统材质。Liquid Glass 属于导航/控制层，不应用于整个内容层。[9] [10] [11]

- [ ] **T5.1：实现 `WindowCoordinator`。** `NativeWindowPolicy` 将迁移窗口职责收敛为 1280×840 初始 content size、880×600 content/min size、`.fullSizeContentView`、标准 `.unifiedCompact` AppKit titlebar、stable `NSWindow` autosave/restoration identifier；不再将透明网页窗口作为玻璃实现。首次安装恢复同名 native frame 或居中，red-close 先保存 frame 再 `orderOut`，`showAndFocus` 会 deminiaturize、聚焦且不创建第二个 shell；`DeepSeekHarnessGlassApp.applicationShouldHandleReopen` 将 Dock reopen 直送同一 coordinator。`windowDidMiniaturize`、`windowDidDeminiaturize`、`windowShouldClose` 映射到可审计 lifecycle，实际窗口管理仍完全由标准 NSWindow/AppKit 负责。
  - 依赖：T1.2。
  - 验收证据：独立 `GlassAppTests/WindowCoordinatorTests` 在无 WindowServer 的 XCTest host 验证迁移几何、native style mask、toolbar policy、stable autosave/restoration key，以及 `visible → hidden/minimized → visible` close-to-menu-bar/reopen policy；避免以不可靠的 headless AppKit 显示替代真实应用组装。workflow 在 Host + transport smoke 后独立运行该 test target。macOS-26 [run 32215096026](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32215096026)（commit `126cd24`）通过该新窗口门、所有静态/module/transport gates、SwiftPM/Swiftc、真实 rc.7 Host smoke、app 组装、snapshot与官方 pairing；人工 contact sheet 复核已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`。本项无 SwiftUI renderer 修改，welcome 仍明确为 `report-only`，不构成 UI 场景视觉完成。

- [ ] **T5.2：实现 AppKit 三栏容器。** `NativeShellRootController` 将 `NativeShellController: NSSplitViewController` 与 modal overlay 作为 AppKit siblings；sidebar、conversation、details 三个 `NSSplitViewItem` 仅承载各自 SwiftUI 内容，divider 与 containment 不经 SwiftUI 模拟。`NativeSplitViewController` 以锁定 `OfficialColumnLayout` 应用官方 sidebar/center/details 解析，details 为 `.useConstraints` 可折叠列；实际 divider constraint 经 `NativeSplitLayoutPolicy` 统一，拖动后的受限 sidebar/details 宽度会写回 `NativeShellPresentation` preferences，故 Host/SwiftUI状态刷新和窗口重布局保留用户选择。自动窄窗口或手工收起时 sidebar 恒为官方 56px rail；details 若会侵蚀官方 640px center minimum 即折叠。
  - 依赖：T2.4、T5.1。
  - 验收证据：`NativeSplitLayoutPolicyTests` 覆盖锁定 1280px `280/640/360` 基线、sidebar 264–420 clamp、56px collapsed rail、details 300–520 clamp、divider的可用宽度限制与无法容纳 center minimum 时 details collapse；T2.4 的 30+ official `computeColumns` fixtures 继续在 `OfficialUISpecBuildTests` 全量比较。`GlassAppTests` 已在 workflow Host + transport smoke 后独立执行。macOS-26 [run 32216703475](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32216703475)（commit `304da29`）通过 split policy、全部静态/module/transport gates、SwiftPM/Swiftc、真实 rc.7 Host smoke、app 组装、snapshot和官方 pairing；人工 contact sheet 复核记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`。本项无 renderer 文案/asset/token变更，welcome仍明确为 `report-only`，不构成 UI 场景视觉完成。

- [ ] **T5.3：让系统负责 sidebar/inspector 材质。** `NativeSplitViewController` 使用 `NSSplitViewItem(sidebarWithViewController:)` 与 `NSSplitViewItem(inspectorWithViewController:)`，两个 SwiftUI宿主保持透明；禁止在这两个结构区域加 `NSVisualEffectView`、固定官方色 canvas、全窗自定义模糊或壁纸亮度采样来“模拟”玻璃。系统在 Light/Dark、Reduce Transparency、Increase Contrast 下负责导航材质的自然适配。
  - 依赖：T5.2。
  - 验收证据：`check-native-structural-material.py` 在每轮 CI 强制 sidebar/inspector AppKit item、透明宿主以及无 `NSVisualEffectView`/固定 structural background/self-drawn canvas；`SnapshotExporterTests` 覆盖 macOS 26 ScreenCaptureKit alpha-first pure-black frame rejection，避免无头 WindowServer 黑帧被伪装为截图。macOS-26 [run 32224425678](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32224425678)（commit `a5f1efb`）通过全部静态/module/transport/material gates、SwiftPM、真实 rc.7 Host smoke、`GlassAppTests`、`SnapshotExporterTests`、应用装配、原生快照和官方配对；人工对照、官方 PNG、原生 PNG、amplified diff 与报告JSON已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`。该无头 runner 对受支持ScreenCaptureKit current-process window与系统 `screencapture -l` 均无法合成系统拥有的sidebar/inspector材质，导致仅这些区域显示黑色；已依据T0.3/T2.6逐路径验证、明确限定为系统渲染例外，绝不放宽内容、控件、文字、几何、字体或无障碍差异。

- [ ] **T5.4：建立 `GlassPolicy`。** `GlassPolicy` 明确区分 `content`、`systemNavigation`、`regularGlassCustomControl`、`clearGlassMediaOverlay`；`GlassPolicyBudget` 将每场景 custom glass 限为一个，系统导航材质仍只由AppKit拥有。唯一既有自定义导航操作控件通过具名 `.regularGlassCustomControl` 进入 `approvedGlassEffect`，正文、sidebar/inspector、composer、list row和dialog不获得附带玻璃。
  - 依赖：T5.2。
  - 验收证据：`check-glass-policy.py` 在CI拒绝GlassUI任何未通过 `approvedGlassEffect(policy:in:)` 声明的原始 `.glassEffect`，并拒绝未经实现审查的custom policy；`GlassPolicyTests` 覆盖内容/系统导航禁止custom glass、仅批准类别可用、system navigation material ownership和单控件预算。macOS-26 [run 32225877836](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32225877836)（commit `7ebaefd`）通过新增policy gate、全部既有静态/module/transport/material gates、SwiftPM、真实rc.7 Host smoke、`GlassAppTests`、`SnapshotExporterTests`、应用组装、原生快照和官方配对；人工审阅及报告已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`，未发现T5.4引入的可观察内容层或布局回归。欢迎页既有无头系统材质`report-only`例外仍严格受T5.3记录约束，绝不扩展为其他视觉差异豁免。

- [ ] **T5.5：实现有限的自定义 glass controls。** 仅将既有、互斥的官方sidebar打开/收起导航操作置入 `GlassEffectContainer`，共用稳定 `glassEffectID` 管理形变；保持官方图标、尺寸、间距和accessible label，绝不向正文、composer、list row、modal或系统sidebar/inspector添加glass。`NativeGlassNavigationButtonStyle` 仅在批准的 `.regularGlassCustomControl` 下使用交互式效果，单场景预算仍为一个。
  - 依赖：T2.3、T5.4。
  - 验收证据：`check-glass-policy.py` 现强制两个互斥sidebar navigation ID、`GlassEffectContainer`、明确Reduce Motion环境与无策略raw glass禁止；`GlassPolicyTests` 覆盖Reduce Transparency/Increase Contrast关闭custom glass、Reduce Motion关闭morphing以及原有policy/budget。macOS-26 [run 32226837259](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32226837259)（commit `002f474`）通过所有静态/module/transport/material/GlassPolicy gates、SwiftPM、真实rc.7 Host smoke、`GlassAppTests`、应用装配、原生快照与官方配对；人工工件复核已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`，未发现T5.5引入的内容层或布局回归。既有无头系统材质report-only例外继续严格限定在T5.3记录范围。

- [ ] **T5.6：建立无障碍验收基线。** 版本化 `official-accessibility-baseline.json` 覆盖welcome/sidebar rail、空session composer、details、approval与question六条锁定官方核心路径，分别约束VoiceOver label、键盘焦点契约、Reduce Motion、Reduce Transparency、Increase Contrast及light/dark颜色模式；收缩sidebar中的settings icon补齐显式 `OfficialUISpec.Text.settings` 名称。`NativeAccessibilityRuntimeTests` 以真实原生视图、`NSHostingView` 和 `NSWindow` 在受信任且可导出AX树的GUI测试host中递归验证核心路径；CI无头runner即使AX trusted仍不导出SwiftUI树，测试会明确受限跳过，版本化静态baseline gate始终强制执行。
  - 依赖：T5.3–T5.5。
  - 验收证据：`check-accessibility-baseline.py` 校验锁定commit、六条core path的来源/locale label/focus contract、macOS Dynamic Type平台限制以及系统偏好环境覆盖；`GlassPolicyTests` 覆盖Reduce Motion、Reduce Transparency和Increase Contrast下custom glass安全降级。Apple明确macOS用户不能修改`dynamicTypeSize`，且该值不影响文本大小，故不伪造用户Dynamic Type支持；系统Zoom由macOS负责，测试注入仍可用于布局回归。macOS-26 [run 32233840528](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32233840528)（commit `bee3839`）通过新增无障碍gate、核心路径测试编译、全部既有静态/module/transport/material gates、SwiftPM、真实rc.7 Host smoke、应用装配、原生快照与官方配对；人工复核与平台限制记录位于 `visual-review/official-99f6f02/welcome-no-workspace-light.md` 和 `notes/T5.5-apple-glass-accessibility-sources.md`。该项未扩大T5.3无头系统材质的严格report-only例外。

## 6. 会话状态机与事件投影

官方 Web client 将 session history、实时 `session/event` 和 `session/projection` 组合为 incremental conversation snapshots，并用 `ConversationNodeDefinition` 为不同业务节点分派 renderer。原生端必须复现该“事件→节点→视图”结构，而非只做消息数组。[7] [8]

- [x] **T6.1：实现 `NativeSessionStore`。** `NativeSessionStore` 以active Session ID过滤mux frame，并为每个已访问session保留resident窗口（history、tool、draft、pending interaction、queue/jobs、selection与sequence gate）；切换回resident session同步恢复可见窗口、后台重拉Host history authority，cold session才进入loading。queue与jobs分别由官方`session/queue`与`session/jobs`完整快照last-wins镜像；`session/subscribed.lastSeq`先截断超前projection并清空旧Host generation的非持久queue/jobs。approval/question、running、tool invocation和tool selection仍由同一Core reducer维护，Feature/UI不接触wire JSON。
  - 依赖：T4.5。
  - 验收证据：`NativeSessionStoreTests` 使用锁定wire形状的`session/queue`、`session/jobs`、`session/subscribed` ServerRequest，验证完整快照替换、foreign session拒绝、空jobs清理、generation transient reset、projection durable-watermark截断以及resident window恢复tool selection/queue/jobs；该XCTest单列进入workflow。macOS-26 [run 32236473372](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32236473372)（commit `b9da559`）成功完成完整静态/module/transport gates、SwiftPM编译、Core/App tests、原生装配、全快照与官方欢迎页比较。人工欢迎页和tooling-inspector复核记录于 `visual-review/official-99f6f02/t6-1-b9da559-ci-review.md`；本项Core状态改动未新增可见布局/层级回归，既有welcome `report-only`例外未被扩展或误记为视觉完成。

- [x] **T6.2：实现 `SessionHistoryPager`。** 已实现官方 tail/`beforeSeq`消息边界分页、连续 raw event range、重复/乱序页拒绝、compaction边界保留、loading/error/retry、live gap信号和已验证导出协作；官方来源、Core-only边界审阅和本提交回归证据现已闭环。
  - 依赖：T6.1。
  - 验收证据：`notes/T6.2-official-session-history-sources.md` 将锁定官方 `session.ts` 的 `PAGE_MESSAGES`、tail/`beforeSeq`、连续 prepend、fail-soft、live gap 与 T6.7 边界映射到 Swift，并引用官方 `session.client.spec.ts` 的连续页、断裂页和并发 `loadOlder` 回归。`SessionHistoryPagerTests` 现覆盖官方 50-message tail、beforeSeq、连续范围、重复页、乱序拒绝、compaction、重试、live gap 以及同一 older page in-flight coalescing。修复提交 `bcf0257` 的 macOS-26 [run 32264787616](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32264787616) 成功完成规格/架构门禁、独立 SwiftPM 编译、全量 74 项 XCTest（5 项明确平台受限跳过、0 failures）、原生 app 装配、快照和官方视觉比较；其中 5 项 `SessionHistoryPagerTests` 全部通过。人工Core-only审阅确认 Pager 仅位于 `GlassCore`、不含 renderer 或视觉产品表面，本变更不扩大 welcome `report-only` 或系统材质例外。T8.2完成后，用户可见的历史分页仍须在其所属 UI 场景中补齐同状态官方/原生视觉配对。

- [x] **T6.3：实现 `ProjectionStore`。** `SessionProjectionStore` 以 `(sessionID, key)` 隔离 Host projection row，`seq` 只接受严格更高的值；history tail 的 projection baseline 以其 `asOfSeq` seed，清理同一cut内不再存在的旧键且绝不覆盖已收到的较新live value。NativeSessionStore 在history landing后seed并在`session/projection` mux frame到达时应用；disconnect清理所有Host会话投影，reconnect可按durable watermark截断超前值。
  - 依赖：T4.4、T6.1。
  - 验收证据：`SessionProjectionStoreTests` 覆盖同key乱序与重复frame的higher-seq-wins、跨session隔离、baseline在cut内清除缺失键且不回滚较新live value，以及reconnect截断；workflow独立执行该XCTest。macOS-26 [run 32235326314](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32235326314)（commit `0853a1f`）成功通过完整静态/module/transport gates、SwiftPM编译、所有Core/App测试、原生装配、全部快照和官方欢迎页比较。人工复核记录于 `visual-review/official-99f6f02/t6-3-0853a1f-ci-review.md`；本项是Core-only改动，已逐项审阅既有welcome `report-only`差异，未将其误记为视觉场景完成或扩展系统材质例外。

- [x] **T6.4：定义 `ConversationNode` 协议。** Core 已建立 `match`、`start`、`update`、`publication`、`buildViewNode`、turn/step location、visibility、stable key、target和Session-owned reducer；官方来源、逐事件 replay、Core-only边界审阅与本提交回归现已闭环。
  - 依赖：T6.1、T6.2。
  - 验收证据：`notes/T6.4-official-conversation-node-sources.md` 将官方 `conversation.ts`、`conversation-assembler.ts` 与 engine-owned `conversation-location-index.ts` 映射到 Swift protocol/reducer；其明确记录 session-owned生命周期、稳定key/target/visibility、最大publication、位置边界与Core-only视觉范围。`ConversationNodeTests` 现覆盖类型擦除、生命周期、renderer不接收raw event、window replay中的engine-owned closed turn/step location及同一event跨definition的最大publication。提交 `8e68158` 的 macOS-26 [run 32266243458](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32266243458) 成功完成规格/架构门禁、独立SwiftPM编译、全量76项XCTest（5项明确平台受限跳过、0 failures）、原生app装配、快照和官方视觉比较；其中6项 `ConversationNodeTests` 全部通过。人工Core-only审阅确认本变更无renderer、产品文案、视觉token或布局改变，不扩大既有welcome `report-only`或系统材质例外。T6.5/T8.2仍须针对真实node renderer完成同状态官方/原生视觉验收。

- [x] **T6.5：实现初始核心 nodes。** Core 已接入 user/context message、assistant chunk/message/thinking、turn/step boundary、tool call/result、error/retry、compaction，以及关闭边界的assistant/tool interrupted状态与官方合成anchor；`surfaceOp`已在Core DTO中保留。官方来源、逐append replay、Core-only边界审阅与本提交回归现已闭环。
  - 依赖：T6.4。
  - 验收证据：`notes/T6.5-official-core-node-sources.md` 将官方 conversation contract/assembler、assistant、tool、retry、turn-error、compaction node definitions 与 Swift Core registry映射，并记录逐append fixture。`ConversationCoreNodesTests` 覆盖append式user/context、streaming/final去重、tool/result、retry/error、compaction、closed-step interrupted anchor，以及从turn/start到step/end的每事件chat node快照、publication、stable identity和raw seq window。修复提交 `c0ea840` 的macOS-26 [run 32268150962](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32268150962)成功完成规格/架构门禁、独立SwiftPM编译、全量77项XCTest（5项明确平台受限跳过、0 failures）、原生app装配、快照和官方视觉比较；其中5项`ConversationCoreNodesTests`全部通过。人工Core-only审阅确认无renderer、产品文案、视觉token或布局改变，未扩大既有welcome `report-only`或系统材质例外。真实Chat/tool renderer的同状态官方/原生视觉配对仍由T8/T9承担。

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

[1]: https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/README.zh.md "DeepSeek Harness 官方 README"
[2]: https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/docs/architecture.md "DeepSeek Harness Architecture"
[3]: https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/bundle/web-app/cordis.patch.yml "官方 Web profile 组合清单"
[4]: https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/client/ui-layout/src/client/AppFrame.tsx "官方 AppFrame"
[5]: https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/client/ui-layout/src/client/columns.ts "官方三栏布局算法"
[6]: https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/client/ui-theme/README.md "官方主题与 token 机制"
[7]: https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/host/apiproxy/README.md "官方 Host API Proxy 与客户端 wire contract"
[8]: https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/client/runtime/src/client/contract/conversation.ts "官方 Conversation Node Contract"
[9]: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass "Apple: Adopting Liquid Glass"
[10]: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views "Apple: Applying Liquid Glass to custom views"
[11]: https://developer.apple.com/videos/play/wwdc2025/310/ "Apple WWDC25: Build an AppKit app with the new design"
[12]: https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/client/ui-sidebar/README.md "官方 Sidebar 模块说明"
[13]: https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/client/ui-conversation/README.md "官方 Conversation UI 模块说明"
[14]: https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/client/ui-settings-plugins/README.md "官方插件设置机制"

## 当前进度：完整可审计状态与唯一续跑入口（2026-08-20）

本节是仓库内**唯一有效的跨会话状态记录**。新会话必须以本节和前文“项目宪章”为起点，不得依赖外部 `CONTINUE_NEXT_SESSION.md`、聊天摘要或未提交的本地笔记。所有状态均以代码、官方来源、视觉证据、门禁和GitHub Actions为准；“部分实现”“能编译”“单一fixture通过”均不等于完成。

> **RC8 重新认证：** 项目唯一官方基线现为 `141eb6f`（`dsh-v0.1.0-rc.8`）。所有 `99f6f02`/RC7 视觉工件和人工复核均为历史记录，不能作为 RC8 UI TODO 的完成依据。故 T5.1–T5.6 与 T7.3 已回退为未完成，直到使用 RC8 官方/原生同状态截图、ARIA/geometry、人工差异分类和更新后 head 自身的 macOS-26 CI 重新闭环。Core-only 已勾选项保留其历史实现证据，但后续 RC8 CI 必须持续验证其受控 DTO、规格和回归测试。

### A. 当前快照

| 项目 | 当前事实 |
|---|---|
| 远端仓库 | `NewbieXvwu/deepseek-harness-glass` |
| 分支 | `main` |
| 当前 RC8 迁移 head | `fb5aab8` — 将当前 `main` 合入 PR #2 的 RC8 迁移分支；需取得该 head 自身 macOS-26 CI 后才可合并。 |
| 最近功能链 | `d62ef24` RC8 基线、受控 payload、规格与 Host contract 迁移；`f6c6447` T6.6 Jobs 第二轮几何收敛；`fb5aab8` 保留二者的无冲突三方合并。 |
| 锁定官方来源 | `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534` |
| 目标平台 | macOS 26+、Xcode 26+、Apple Silicon、Swift 6 |
| D1规格门禁 | RC8 本地复验通过：91 text、77 layout、29 assets、11 visual scenes；完整 macOS-26 复验待当前 head。 |
| D0原生门禁 | RC8 本地复验通过：核心UI无WebView、DOM脚本和CSS注入；完整 macOS-26 复验待当前 head。 |
| 最近 RC8 macOS CI | [run 32328246659](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32328246659)，原始 PR head `d62ef24`，success；通过 RC8 payload、规格与架构门禁、SwiftPM、XCTest、装配、快照和比较，但不能代替 `fb5aab8` 的合并后证据。 |
| 当前合并门禁 | `fb5aab8` 已通过本地 RC8 规格、架构、DTO、transport、interaction-scene、accessibility、inventory 与 visual-policy 门禁；其独立 macOS-26 CI 尚未触发。 |
| 当前主阶段 | 先完成 RC8 基线迁移与截图矩阵扩展，再以 RC8 同状态证据重新认证 T5.1–T5.6、T7.3；T6.6 和 T6.7 在此之后继续。 |
| 已勾选TODO条目 | 共29项：T0.1–T0.3、T1.1–T1.3、T2.1–T2.2、T2.6、T3.1–T3.6、T4.1–T4.6、T6.1–T6.5；T5.1–T5.6、T7.3及其余条目均保持未勾选，直至 RC8 证据闭环。 |

### B. 阶段状态矩阵

| 阶段 | 状态 | 已完成事实 | 尚未完成或不可勾选的内容 |
|---|---|---|---|
| 0. 原则与边界 | 阶段性完成 | 项目宪章、D0/D1规则、README/README.zh/贡献指南的 D0–D5 边界、核心 WebKit 静态门禁、唯一 RC8/Node 24.19.0/官方 commit 支持矩阵、官方/原生截图证据链、可失败阈值自检、复刻层级和人工审阅准则已建立；T0.1–T0.3 已闭环 | 完整 D2–D5 产品行为、各 UI 场景从 report-only 收敛到 enforce、RC8 的浅色/深色同状态截图矩阵和全部人工视觉验收仍未完成；它们属于下游任务的完成条件，不可因此勾选。 |
| 1. 仓库与模块化基础 | 阶段性完成 | 13 项运行时资产已有机器可读分类；App/Window/MenuBar/Host lifecycle 已从 legacy `main.swift` 拆出；SwiftPM 的 Spec/Core/UI/Snapshot/App target 图、依赖方向门禁与 macOS 独立 release 编译已建立；T1.1–T1.3已勾选 | Plugins target 与 Tests target 的专用隔离将在下游插件/测试任务完成；旧路径全量行为审计和每个 UI/状态资产的完整迁移仍未完成 |
| 2. 官方规格 | 部分完成 | `OfficialUISpec.swift`、official-ui-catalog、visual-scenes、D1校验和来源映射已存在；生成的 OfficialUISpec build 已绑定固定 Host、commit、完整 locale/token/layout/fixture 输入 hash 并通过 mismatch 自检与 Swift XCTest；1,268 条 634-key en/zh locale catalog、来源行号/commit、解析 revision、Swift 查询索引和可失败 UI literal lint 已建立；T2.1、T2.2、T2.6已勾选 | token全量语义映射、布局solver完整夹具、全覆盖场景规格与辅助功能矩阵仍未完成 |
| 3. Host生命周期 | 部分完成 | `HarnessHostController`、`HostBuildVerifier`、payload缓存和运行时启动路径已实现 | 未验证Host策略、完整诊断页、生命周期混沌测试、下载导出与全面恢复仍未完成 |
| 4. RPC/SSE | 部分完成 | RPC envelope、URLSession transport、SSE reducer、多个session/workspace/settings DTO已实现；最新新增settings.describe/mutate类型 | 全域facade、round-trip/真实Host契约测试、revision冲突和完整重连测试尚未闭环 |
| 5. 窗口、三栏与Liquid Glass | RC8 重新认证中 | AppKit三栏根容器、根包装overlay、sidebar控制、系统材质、Glass policy、有限导航 glass controls 与无障碍基线仍保留代码和历史回归 | T5.1–T5.6 的 RC7 配对工件不能作为 RC8 证据；须为 window、三栏、材质、glass controls 与辅助功能条件建立 RC8 官方/原生浅色/深色同状态场景并达到 enforce。 |
| 6. 会话状态机 | 部分完成 | T6.1 NativeSessionStore、T6.2 SessionHistoryPager、T6.3 ProjectionStore、T6.4 ConversationNode协议、T6.5初始nodes已按各自来源、CI与Core-only/视觉边界证据勾选 | T6.6扩展nodes、T6.7 reconnect/replay、完整raw-event replay与cold/live一致性仍未完成 |
| 7. 侧栏、工作区与会话浏览 | RC8 重新认证中 | Sidebar、workspace/session列表、搜索、行操作、rename/delete/fork/archive和Host RPC代码仍存在 | T7.3 的 RC7 pairing 已失效；须以 RC8 搜索、行操作和管理 dialog 的浅色/深色同状态场景重新闭环，同时完成 reorder、完整archive/ungrouped语义、窄窗口/键盘焦点与全场景回归。 |
| 8. Conversation主界面与Composer | 部分完成 | welcome、composer、model/permission控制行和部分prompt/cancel路径已实现；approval/question composer已配对验收 | 完整ChatView、Markdown安全策略、queue/steer、附件、model discovery、stats/todo/goal dock尚未完成 |
| 9. 工具与复杂节点 | 部分完成 | ApprovalPanel、QuestionComposer和部分tooling inspector fixture存在 | generic tool及bash/read/search/diff/web/workflow/subagent/trajectory/deliverables全套renderer未完成 |
| 10. 官方设置 | 进行中 | `DSHAPIClient.settingsDescribe/settingsMutate`、`SettingsNamespaceDTO`、secret slot DTO和`NativeSettingsStore`基础已提交 | Settings Root、schema form、draft/dirty/discard、openDocument、General、Models、Credentials、Plugin、Agent Presets和设置视觉回归均未完成 |
| 11. 插件兼容 | 未开始 | 仅在架构与TODO中规定NativeUIManifest/SwiftAdapter/PluginWebHost分级 | manifest schema/signature、adapter registry、compatibility matrix和隔离Web fallback尚未实现 |
| 12. 测试与审计 | 部分完成 | D0/D1、视觉场景存在性、macOS-26截图门禁已运行 | reducer、transport chaos、布局golden、UI/accessibility、性能、安全和secret泄露测试未完成 |
| 13. 发布 | 未开始 | native-ui workflow、缓存和固定payload构建链存在 | 签名、公证、升级流程、支持矩阵、feature flags和发布候选审计未完成 |

### C. TODO勾选的完整证据边界

当前只允许以下29项保持勾选。T6.2、T6.4、T6.5已分别在 `bcf0257`、`8e68158`、`c0ea840` 的成功CI和Core-only审阅后闭环；T5.1–T5.6与T7.3已因 RC8 基线迁移回退，等待新的来源、同状态视觉和当前 head CI 证据。其余未完成任务不得以已有代码或父提交CI提前勾选：

| 条目 | 状态 | 证据与边界 |
|---|---|---|
| T0.1 | `[x]` 完成 | `f0e3549` 写入双语 README 与 `CONTRIBUTING.md` 的 D0–D5、官方来源/截图协议、逐项 TODO 勾选纪律和 `PluginWebHost` 唯一例外边界；`.github/workflows/native-ui.yml` 已在这些文件变更时运行静态门禁。当前提交的 macOS-26 [run 32152858091](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32152858091) 成功，D0/D1、构建与原生截图工件均已复核。此勾选不代表 T0.2/T0.3 的支持矩阵或完整视觉策略已完成。 |
| T0.2 | `[x]` 完成 | `SupportedHostBuilds.json` 明确锁定 `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534`、`@deepseek-ai/dsh`/`dsh-web-frontend` `0.1.0-rc.8`、Node `24.19.0`、最小 App `0.4.0`、protocol/UI revision 与验证日期 `2026-08-20`；`check-supported-host-build.py` 将 catalog、Info.plist、精确 lockfile、实际 payload package.json 和 Node 版本绑定验证。原始 RC8 提交 `d62ef24` 的 macOS-26 [run 32328246659](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32328246659) 成功验证并打包该基线；包含当前 main 的刷新 head 仍须有其自身 CI 后才可合并。原生 Host 仅从 app bundle 受控启动，未提供任意外部 `dsh web` 作为写入目标的连接路径。此勾选不代表完整 Host 生命周期、RPC 协议或 T0.3 视觉判定策略已完成。 |
| T0.3 | `[x]` 完成 | [`VISUAL_REPLICATION_TEST_PLAN.md`](docs/VISUAL_REPLICATION_TEST_PLAN.md) 将文本、布局、状态、交互的严格复刻与系统材质的 API/可读性/辅助功能验证分开；`visual-validation-policy.json` 明确每场景的 report-only/enforce 状态、阈值、系统例外和人工准则；`test_visual_policy.py` 证明超阈值场景在 enforce 下被拒绝。`c4ec69f` 的 macOS-26 [run 32157797085](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32157797085) 成功执行该自检及官方/原生配对。此勾选不代表任何仍为 report-only 或有未分类差异的页面视觉通过。 |
| T1.1 | `[x]` 完成 | `RuntimeAssetInventory.json` 逐项分类 legacy entry、窗口、历史菜单栏、受控 Host、外部 3080 挂接、snapshot、DSH_HOME/log、Node/payload、repair、metadata/signing、CI/release 和 WebView 壳；`check-runtime-asset-inventory.py` 强制 13 项分类、唯一模块化 `@main`、legacy 文件删除和禁止外部 3080 路径。`fc8b499` 的 macOS-26 [run 32159109869](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32159109869) 成功验证清单、原生编译、官方/原生截图和质量门。此勾选不代表 T1.2 的独立 target/package、后续生命周期深度测试或任何下游 UI 行为完成。 |
| T1.2 | `[x]` 完成 | `glass/Package.swift` 声明 `GlassSpec`、`GlassCore`、`GlassUI`、`GlassSnapshot` 与 `DeepSeekHarnessGlassApp` 五个 target；`check-module-boundaries.py` 强制依赖方向、唯一 `@main`、Core 无 AppKit/SwiftUI、UI 无 `Process`/应用生命周期、Session 无 `NSApplication`。`NativeImagePicker` 将 `NSOpenPanel` 由 Core 移至 UI；CI 执行 `swift build --configuration release`。`9563049` 的 macOS-26 [run 32161795843](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32161795843) 成功编译 target、生成官方/原生截图并通过人工对照复核。此勾选不代表 Plugins/Tests target、插件隔离或任何下游产品功能完成。 |
| T1.3 | `[x]` 完成 | `check-no-webview.sh` 通过；核心Swift路径不依赖WKWebView、DOM、JavaScript或CSS注入。此勾选不代表PluginWebHost例外已实现。 |
| T2.1 | `[x]` 完成 | `official-ui-spec-build.json` 记录 `sourceCommit`、Host build ID、`uiSpecRevision`、locale/token/layout/fixture SHA-256 revision、确定性 `generatedAt`、生成器版本和 37 项上游输入 hash/行数；`OfficialUISpecBuild.swift` 暴露同一 build ID，Host 启动会拒绝其 ID/commit/UI revision 不匹配的 payload。`check-official-ui-spec-build.py` 从锁定源码重生成并比对，`test-official-ui-spec-build.py` 证明篡改 catalog 必失败，`OfficialUISpecBuildTests` 读取 build ID。`e9fc169` 的 macOS-26 [run 32166053042](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32166053042) 复验通过。此勾选不代表 T2.3 token 的完整生成已完成。 |
| T2.2 | `[x]` 完成 | `official-locales.json` 从 28 个锁定 official locale 文件生成 1,268 条、634 个成对的 en/zh key；每条记录 namespace/key/value、插值参数、复数类别、来源路径/行号/commit，且解析 catalog revision 与 `OfficialUISpec.Build.localeRevision` 所代表的原始输入 hash 分离。`OfficialLocaleCatalog.swift` 提供双语查询；`check-official-locales.py` 重生成并验证来源、双语/插值/复数一致性及 source-input 绑定；`check-official-locale-literals.py` 与自检拒绝未登记的 SwiftUI 可见文案。`e9fc169` 的 macOS-26 [run 32166053042](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32166053042) 成功完成 Swift XCTest、独立编译和官方/原生 GUI 对照；人工复核未发现本次 locale 迁移新增视觉回归。此勾选不代表 T2.3 token 或下游页面文案的完整逐场景视觉通过。 |
| T2.6 | `[x]` 完成 | 已建立官方/原生同状态同视口配对、放大局部检查、差异记录、立即修复和CI截图存在性规则。此勾选不代表所有视觉场景都已人工验收。 |
| T7.3 | `[x]` 完成 | workspace-search、workspace rename、session rename、workspace delete已接入官方场景契约和Host行操作；管理Dialog按钮端帽/描边/禁用色/输入全选已在run 32142821176配对核验。此勾选不代表全部sidebar功能完成。 |

### D. 视觉场景矩阵

场景目录来源为 `glass/Sources/Spec/Fixtures/visual-scenes.json`，固定官方 commit 为 `141eb6f...`（`dsh-v0.1.0-rc.8`）。所有场景要求 light、DPR 1、同状态、同视口；管理 Dialog 和 workspace search 使用 1280×1100 视口。RC7 的截图和人工复核仅作历史记录，不得作为 RC8 TODO 勾选证据。

| 场景 | 当前证据状态 | 下一步 |
|---|---|---|
| `welcome-no-workspace-light` | 已有工件均属于 RC7 历史记录，不能用于 RC8 视觉验收；RC8 场景暂处于 `report-only`，不得从旧 run 推导“无新增回归”。 | 在 macOS-26 CI 以 RC8 WebUI 和同一原生 fixture 重建官方/原生 PNG、ARIA/几何 JSON、量化差异与人工分类；仅在完整证据闭环后评估是否进入 `enforce`。 |
| `conversation-details-light` | CI场景契约存在 | 补全RPC fixture、完整node和配对核验 |
| `tooling-inspector-light` | CI场景契约存在 | 补全tool renderer与详情栏核验 |
| `workspace-search-light` | RC7 工件仅作历史记录，不能用于 RC8 验收 | 用 RC8 官方/原生同状态 search、空/结果/错误状态重建浅色/深色配对、ARIA/geometry和差异分类。 |
| `workspace-rename-light` | RC7 dialog 工件仅作历史记录 | 用 RC8 官方/原生同状态 rename dialog 重建浅色/深色配对、输入全选和按钮端帽证据。 |
| `session-rename-light` | RC7 dialog 工件仅作历史记录 | 用 RC8 官方/原生同状态 session rename dialog 重建浅色/深色配对和焦点证据。 |
| `workspace-delete-light` | RC7 dialog 工件仅作历史记录 | 用 RC8 官方/原生同状态 delete dialog 重建浅色/深色配对、危险状态和文案换行证据。 |
| `approval-composer-light` | 阶段2配对验收；ApprovalPanel 140px裁切已固定 | 补充更广泛approval状态与RPC测试 |
| `question-composer-light` | 阶段2配对验收；QuestionComposer 310px卡片已固定 | 补充选择/提交/重连测试 |
| `sidebar-rail-narrow-light` | 场景契约与CI存在性已建立 | 完成1023px阈值、焦点和官方motion配对 |

### E. 最近修复与可复用经验

管理Dialog的按钮两侧曾出现重复、断裂或方形残留描边。`eca42c2` 将动作按钮改为单一胶囊绘制路径，`7db32ed` 将禁用primary映射到官方中性brand token，`082ddfb` 用AppKit桥接复刻官方打开时自动全选预填rename文本。修复方法和证据保存在 `visual-review/stage3-native/management-modal-review.md`。这一经验必须推广到所有局部控件：先放大检查真实像素，再判断是Shape合成、token、几何、状态还是系统渲染问题，不能先假定是平台差异。

### F. 当前代码入口与下一步顺序

新会话必须按以下顺序开始，不得跳到更下游页面：

1. 阅读本TODO的项目宪章和本“当前进度”章节；当前正式勾选共29项。先完成 RC8 基线迁移、截图矩阵与 T5.1–T5.6/T7.3 的重新认证，再继续 T6.6。
2. 执行 `git status --short`、`git log -10 --oneline`、`gh run list --repo NewbieXvwu/deepseek-harness-glass --workflow native-ui.yml --limit 10`，确认待合并 head 与其自身 CI 一致；再运行 `python3 glass/ci/check-runtime-asset-inventory.py`、`python3 glass/ci/check-module-boundaries.py`、`python3 glass/ci/check-official-ui-spec-build.py --official-root /home/ubuntu/reference/deepseek-harness-rc8-analysis`、`python3 glass/ci/check-official-locales.py --official-root /home/ubuntu/reference/deepseek-harness-rc8-analysis`、`python3 glass/ci/check-official-locale-literals.py`、`python3 glass/ci/check-official-spec.py`、`bash glass/ci/check-no-webview.sh`、`python3 glass/ci/test_visual_policy.py` 和 `python3 glass/ci/check-supported-host-build.py --payload-dir glass/build/backend --node glass/build/node/node`（或等价 Node 24 路径）。
3. 先扩展 RC8 浅色/深色截图场景和场景政策；T5.1–T5.6/T7.3 的视觉重认证完成后，再处理 T6.6 扩展节点和 T6.7 reconnect/replay。后续任务证据不足时保持未勾选。
4. 按T6.6 → T6.7 → T7.1 → T7.2 → T7.4 → T8 → T9 → T10 → T11 → T12 → T13推进；不得跳到设置、插件或发布页以掩盖会话/节点基础层未闭环。

### G. 当前验证命令与远端证据

```bash
cd /path/to/deepseek-harness-glass/glass
python3 glass/ci/check-official-spec.py
bash glass/ci/check-no-webview.sh
git status --short
git log -10 --oneline
gh run list --repo NewbieXvwu/deepseek-harness-glass --limit 10
```

RC8 原始迁移提交 `d62ef24` 的 [run 32328246659](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32328246659) 成功完成受控 payload、官方/架构门禁、独立 SwiftPM 编译、全量 XCTest、原生装配、WindowServer 快照和视觉比较。它不覆盖包含当前 main 的刷新提交 `fb5aab8`，后者必须以自身 macOS-26 run 重新验证。`c0ea840`、`8e68158`、`bcf0257` 的 RC7 Core-only CI 仍保留其实现演化记录，但不得作为 RC8 可见 UI 的验收替代。后续新提交必须重新查询自己的 run，不得沿用父提交成功状态。

### H. 明确的未完成范围

T6.6扩展nodes、T6.7 reconnect/replay、完整Settings Root/schema form/General/Models/Credentials/Plugin pages、NativeUIManifest、SwiftAdapterRegistry、PluginWebHost隔离POC、完整Chat/tool renderer、window recovery、commands、accessibility/performance/security tests、签名公证、升级支持矩阵和发布候选审计均未完成。任何新会话必须保持这些任务未勾选，直到代码、官方来源、测试、配对截图和macOS-26回归全部闭环。
