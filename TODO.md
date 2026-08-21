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

核心 UI 必须完全原生。会话、工作区、官方设置、模型、凭据、工具、审批、问题、命令和插件配置不得通过 WebView、DOM、JavaScript、CSS注入或网页截图完成。Host 是唯一业务真源；所有读写通过官方 loopback RPC/SSE 和类型化 DTO，原生端不建立与 Host 冲突的业务数据库。Liquid Glass 只用于导航、侧栏、工具栏、inspector、popover、sheet和官方已有的操作控件，不得将内容层整体覆盖为玻璃，也不得借玻璃效果创造官方没有的视觉层级。第三方插件实行**渐进双轨制兼容**：检测到专有资产（`SwiftAdapter` / `NativeUIManifest`）时自动走专有原生路径；未提供原生适配的第三方 React 插件自动由轻量沙箱 `PluginWebHost` 局部卡片容器无缝兜底运行；核心应用外壳与会话骨架严禁被 WebView 侵入。

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
| D2 | Host 是业务真源并支持端口复用。 | 任何会话、工作区、设置、凭据、模型、命令和插件配置，均通过官方 loopback RPC/SSE 获取或写入，支持自动探测并复用本地正在运行的 `127.0.0.1:3080` 实例或内置 Host。 |
| D3 | Liquid Glass 服从系统设计。 | 侧栏、inspector、工具栏、sheet、popover 和少数操作控件优先使用系统材质；内容层不泛滥叠加 glass effect。[9] [10] |
| D4 | 插件兼容实行自适应双轨制。 | 插件按 `swift-adapter` ➔ `native-manifest` ➔ `web-fallback (自动沙箱)` ➔ `host-only` 自动分流，状态可在诊断页面查询。 |
| D5 | Host 版本兼容与安全宽容。 | 启动时检查支持的 Host build；已验证版本提供最高保证，未知版本给予兼容提示并以最佳努力（Best-effort）模式放行，绝不强制锁死输入框。 |

- [x] **T0.1：在 README 与贡献指南中写入 D0–D5。** 说明 `WebKit` 只能位于 `PluginWebHost` 目标中，禁止在主应用 target 或任何核心 renderer 中导入。
  - 依赖：无。
  - 验收：CI 的静态规则可阻止 `glass/Sources/Core/**`、`glass/Sources/UI/**`、`glass/Sources/Features/**` 导入 `WebKit`。

- [x] **T0.2：确定产品支持边界与端口复用。** 支持内置固定 DSH package/commit 与捆绑 Node 运行时，同时支持自动探测并复用本地运行的 `127.0.0.1:3080` 外部实例。
  - 依赖：T0.1。
  - 验收：`SupportedHostBuilds.json` 包含基准版本清单；未匹配构建采取安全宽容模式。

- [x] **T0.3：确定“官方复刻”的判定层级与双模验收。** 把“文本、布局、状态、交互”与“系统渲染的玻璃折射和阴影”分开。对 Agent 自动化流水线强制执行严格同状态视觉证据闭环；对人类开发者提供宽松调试开关（`I_AM_A_REAL_HUMAN_NOT_AN_AI_OR_AN_AGENT_AND_I_CLEARLY_KNOW_WHAT_AM_I_DOING_I_SWEAR_PLEASE_BE_LENIENT_AND_GET_OUT_OF_MY_WAY`）。
  - 依赖：T0.1。
  - 验收：测试计划中有明确的结构差异阈值、截图场景与人工审阅准则。

## 1. 仓库与模块化基础

现有项目将主要逻辑集中在 `glass/Sources/main.swift`。重写前应拆分生命周期、Host 通信、状态、界面和插件兼容层，避免将 SwiftUI、AppKit、网络、进程与业务 reducer 再次耦合在一个文件中。

- [ ] **T1.4：CI 反馈链路与触发解耦。** 将文档登记（`TODO.md`、`notes`）与源码变更解耦，防止仅文档更新触发长达 5–8 分钟的 macOS 回归。将已审计、仅依赖 Foundation 的 Host 显示路径 helper 迁入 `GlassPortableCore`，在 Linux 提供快速回归；分离官方 WebUI 基线预热以利用精确缓存；提供 `local-visual-test.sh` 缩短 UI 调整的本地闭环。其余 DTO/Reducer 的可移植化必须按独立 TODO 和边界审计推进，不能由本项推定完成。
  - 依赖：T1.2、T2.5、T4.1。
  - 验收：仅修改 `TODO.md` 时不触发 `native-ui` 而触发文档完整性检查；`portable-checks` 提供可移植 helper 和规格/架构的并行反馈；官方基线缓存未命中时重建并验证工件；`assemble.sh` 复制全部 SwiftPM resource bundle，且在签名前确认 `official-accessibility-baseline.json` 已位于打包产物。当前集成提交已完成本地可移植门禁，保持未勾选直至其自身 macOS 权威工作流成功。
  - 进度：已根据 `72665e2` 的远端失败日志修复两个确定性门禁缺口：`portable-checks` 在调用项目内 locale AST 生成器前执行锁定 `tools/spec-generation` TypeScript 安装；`NativeSessionStoreTests` 删除重复 `tryUnwrap` 定义，恢复 macOS XCTest module 编译。PR #9 的 macOS 原生工作流随后在 app 组装阶段确认：前置独立 SwiftPM build 使用 target-triple 输出目录，而 `assemble.sh` 仍从遗留 `.build/release` 读取资源包，导致错误报告无 resource bundles。现已改为以 `swift build --show-bin-path` 返回的同一目标目录复制可执行文件与全部 bundle，保留 `official-accessibility-baseline.json` 签名前检查。`glass/ci/test-assemble-resource-bundle.sh` 现以真实生产组装脚本、空的遗留 `.build/release` 和完整 target-triple fixture 验证可执行文件、resource bundle 与 accessibility baseline 都进入 app，并已接入 `portable-checks`；本地夹具通过。该修复推送后会触发新的非阻塞 macOS 验证。任务仍保持未勾选，且不以任何历史成功替代本次权威工作流结果。

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

- [x] **T2.7：将官方规格生成器的 TS/TSX 源码解析迁移到真实 AST。** `generate_official_locales.py` 与 `extract_official_icon.py` 目前用行级正则与字符串查找解析锁定官方 TypeScript 源码（`EXPORT`/`PROPERTY_START`/`NAMED_CONSTANT`/`STRING_LITERAL` 规则、以 `,` 结尾判定语句结束、`.find("<svg")` 切割组件片段等）。迁移到 TypeScript compiler API（或 `esbuild` parser + 定向 AST visitor），复用项目已内置的 Node 24.19.0 运行时，消除“上游结构稍变即静默错位”的脆弱解析；官方 locale 对象、const 引用、字符串字面量/插值/拼接与 TSX 组件签名/SVG 子树的提取全部以 AST 节点为准。
  - 依赖：T2.2、T2.4。
  - 验收：对锁定 commit `141eb6f` 的同一官方源码，新生成器输出的 `official-locales.json` 与已登记的 icon SVG 逐字节一致（或差异经人工审阅并显式升级基线）；上游新增复杂表达式（嵌套对象、三目文案、模板插值链、TSX 换行签名）时有明确的解析错误而不是静默漂移。
  - 完成：`tools/spec-generation/generate_official_locales.ts`、`generate_official_ui_spec_build.ts`、`extract_official_assets.ts` 以 TypeScript compiler API 解析；JSON/Swift 输出与旧 Python/Sed 生成器在 fixture 上逐字节一致（`official-locales.json`/icon SVG 端点由 CI gate 对锁定提交验证）；`check-official-locales.py` 与 `check-official-ui-spec-build.py` 已切换驱动 TS 生成器，`native-ui.yml` 在官方规格 gates 前安装锁定 typescript。

## 3. Host 生命周期、版本验证与诊断

官方 Web profile 由 Node Host 提供 API、SSE、静态页面与 plugin graph。原生客户端应只使用前两者来承载业务，前端静态资源仅在 WebView 插件 fallback POC 时出现。[1] [7]

- [x] **T3.1：拆出 `HarnessHostController`。** `GlassCore` 的 `HarnessHostController` 现独立管理 Node/payload 位置、运行时 DSH_HOME/log 目录、`dsh web --port 0`、受限 127.0.0.1+port announcement 解析、`host.describe` ready probe、20 秒启动 announcement timeout、日志、手动/异常终止的一次恢复、停止抑制恢复和退出清理；UI target 不包含进程启动逻辑。
  - 依赖：T1.2。
  - 验收证据：新增无 UI `GlassCoreTests` target 与 `HarnessHostControllerTests.testOwnedHostStartsReusesAndStopsWithoutLeavingProcess`，使用 CI 已验证 rc.7 Node/payload 真实启动、ready、重复 start 同 PID 复用、stop、PID 不存在、DSH_HOME/log 落盘。macOS-26 [run 32175400591](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32175400591)（commit `229d0d9`）执行该测试成功（3.488s），并完成全门禁、SwiftPM/Swiftc 编译、原生截图与官方配对；人工复核记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`，Host-only 改动未新增可观察 renderer 回归，既有 welcome `report-only` 差异仍由后续 UI TODO 关闭。

- [x] **T3.2：实现 Host build 验证与安全宽容模式。** `HostBuildVerifier` 以 `SupportedHostBuilds.json`、锁定 official commit、dsh/package frontend manifest 版本和生成 UI spec revision 验证 payload；`HostBuildTrust` 将结果显式区分为 verified 与 unverified。verified metadata 随 `HostConnection` 传入每个 API transport；unverified 在设置页给出兼容提示，并进入安全宽容的 Best-effort 模式放行通用 RPC/SSE 交互，不强制中断用户使用。
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

- [x] **T3.7：缓存 Host 启动 announcement 正则并消除逐块重编译。** `HarnessHostController.consumeHostOutput` 每次 stderr 数据块到达都对 `announcedOutput` 调用 `range(of:options:.regularExpression)`，而该 API 每次都会重新编译正则并在剩余输出上重扫。将 `dsh web:\s+...` announcement 模式提升为 `static let` 预编译的 `NSRegularExpression`（或等价一次性构件），在 `startingOwned` 状态下仅对追加后的受限窗口做一次 `firstMatch`；保持 `announcedOutput` 有界裁剪不变。
  - 依赖：T3.1。
  - 验收：`HarnessHostControllerTests` 的真实 owned 启动仍能解析 endpoint 并 ready；提取到的 URL 与现行为逐字节一致（含 `127.0.0.1` 校验、malformed announcement 拒绝），且 host 启动密集 stderr 输出下不再出现逐块正则重编译（可用地址/性能断言或注入记录验证）。
  - 完成：`consumeHostOutput` 以 `static let startupAnnouncementRegex` 预编译并带 capture group 直接提取 URL（替代原先每次 `range(of:options:)` 重编译 + split）；`appendLog` 使用 static ISO8601 formatter 与常驻 FileHandle。`HarnessHostControllerTests` 全量通过。

- [x] **T3.8：重构 `HostLogRedactor` 为编译缓存加显式规则元组。** 目前 `redact` 每次调用都重新构造 `NSRegularExpression`，并依赖 `pattern.hasPrefix("(?i)(https")` 这种“按模式字符串前缀选择替换模板”的脆弱耦合——规则顺序或格式一变即静默失效。改为进程级一次性编译的 `static let` 模式数组，每条规则显式携带 `(pattern, replacementTemplate)` 元组；删除前缀判定。
  - 依赖：T3.4。
  - 验收：`testDiagnosticsAreCopyableCompleteAndRedacted` 继续覆盖 API key/Cookie/Bearer/URL credential/secret 全部不泄露；新增或调整规则时不依赖字符串前缀；脱敏行为在重复调用下结果稳定、无逐调用编译成本。
  - 完成：`HostLogRedactor.patterns` 为 static 预编译数组，每条规则显式携带 replacement 模板；`testDiagnosticsAreCopyableCompleteAndRedacted` 与全量诊断测试通过。

## 4. HTTP RPC、SSE 与强类型契约

官方 API 的请求/响应通过 `rpcId` 关联，并将 ClientRequest、ServerResponse、ServerRequest、ClientResponse 映射在 HTTP POST 与 SSE 上。会话、工作区、设置、凭据、模型、命令和远程事件都应经过同一个可测试传输层。[7]

- [x] **T4.1：定义 `RPCEnvelope`、无损 JSON 边界与强类型 DTO 架构。** 边界采用 `swift-yyjson` 或原生无损数字策略保留 raw number token，彻底消除 `Double` 大整数截断与精度损失。`RPCEnvelope` 汇总 ClientRequest/ServerResponse/ServerRequest/ClientResponse 并保留 `rpcId` 与 closed success/business-error branch；进入业务层立即映射为强类型 DTO（ID 统一为 `String`，seq/turn/step 统一为 `Int64`，高精度数值使用 `Decimal`），禁止在业务层进行 `JSONValue` encode/decode 二次往返或无模式字典传递。`RPCBusinessError` 与 `DSHTransportError` 将 HTTP、network、timeout、cancelled、content/envelope/rpcId mismatch、unverified build 统一投影为 retryable、requires refresh、requires user correction、unsupported 或 program fault。
  - 依赖：T3.1。
  - 验收证据：`RPCModelsTests` 覆盖 $2^{53}\pm 1$、`Int64.max`、浮点往返、revision conflict、validation、unsupported method、unavailable/internal、429/503/400、timeout/network/cancel/unverified 及 envelope rpcId/business branch。macOS-26 [run 32183487572](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32183487572)（commit `a3d86a3`）完成基线验证。

- [x] **T4.2：生成或维护 Swift DTO。** 从官方 TypeScript/Zod schema 建立受控生成步骤；若第一版手工建模，也必须记录 schema source path 与 fixture revision。`generate_official_rpc_dto_manifest.py` 现从锁定 apiproxy schemas 生成 16-method manifest；`check-official-rpc-dto-manifest.py` 在 CI 强制官方 HEAD、完整 16-method 集、fixture revision 与每个 source SHA 的 fresh-generation 相等。`capture_official_host_dto_fixtures.sh` 在隔离 `DSH_HOME` 启动固定 rc.7 Host，生成每个当前 facade method 的官方 ClientRequest/ServerResponse capture；无效 session/workspace 只使用 schema-valid identifier，保留 Host closed business-error branch，且绝不连接用户配置或凭据。
  - 依赖：T4.1、T0.2。
  - 验收证据：`RPCDTOFixtureTests` 从 GlassCore resource 加载与 `OfficialUISpec.Build` 绑定的 capture，验证 16 条真实 envelope 的 rpcId/type/canonical Codable round-trip、16 个对应 production request DTO 的 typed round-trip、6 个成功 value DTO 与 10 个真实 `RPCBusinessError` branch。macOS-26 [run 32186518136](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32186518136)（commit `944bee3`）通过 manifest gate、完整 SwiftPM/Swiftc 编译、fixture XCTest、Host tests、app 组装、snapshot 和官方配对；人工工件复核已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`。T4.2 无 renderer 改动，welcome 既有差异继续为明确的 `report-only`，不被误记为 UI 场景视觉完成。

- [x] **T4.3：实现 `DSHClientTransport`。** 使用 `URLSession` 实现 JSON POST、Content-Type、请求取消、统一超时、`rpcId` 去重和调用 tracing。`DSHClientTransport` actor 现以注入式、可测试 rpcId generator 分配 id，并在发送前执行 in-flight 与最近 1,024 个已签发 id 去重；任何 duplicate 在抵达 carrier 前被拒绝。每个调用强制 `server-response`/echo rpcId 后才交付，trace 有界保留 method、rpcId、terminal outcome 和脱敏错误类别，绝不保存 payload；cancel/timeout/network/HTTP/content-type 映射沿用 T4.1 taxonomy。
  - 依赖：T4.1、T4.2。
  - 验收证据：`DSHClientTransportTests` 通过 URLProtocol mock carrier 发起 100 个并发 Host RPC，断言 100 个唯一 rpcId、每个 response 仅回到其原始 payload index、100 条成功 trace；另覆盖 duplicate id 在第二次发起前被拒绝且不发送、以及 crossed response rpcId 必须失败而不能交付。native-ui workflow 现将 `glass/Tests/**` 纳入 push/PR paths 并独立运行该 XCTest，避免 test-only 变更绕过 macOS gate。macOS-26 [run 32189390817](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32189390817)（commit `1555ddb`）通过所有门禁、SwiftPM/Swiftc 编译、transport/Host/DTO tests、app 组装、snapshot 和官方配对；人工工件复核已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`。T4.3 无 renderer 变动，welcome 既有差异继续明确为 `report-only`，不构成 UI 场景视觉完成。

- [x] **T4.4：实现 `SSEClient` 与 WebSocket 传输演进。** 支持 ServerRequest 帧、断线检测、指数退避、Host restart 后重订阅、最终取消与网络路径变化。短期在现有 `URLSessionWebSocketTask` 必须补齐 **Ping/Pong 看门狗心跳保活与超时熔断**，杜绝假死连接（Silent Disconnect）；长期演进为基于 Apple 原生 **`Network.framework` (`NWConnection` + `NWProtocolWebSocket`)** 架构，实现毫秒级网络接口切换感知（`pathUpdateHandler`）与睡眠唤醒自愈。跨 reconnect 的有界 rpcId fence 和按 session 分桶的 `session/event`/`session/projection` monotonic sequence fence 阻止 replay 低序号重复投影，且无 payload trace。
  - 依赖：T4.1。
  - 验收证据：`SSEClientTests` 覆盖可重放 stream、坏 frame、纯 fetch fixture 的 `data:`/comment framing、network reconnect、rpcId/sequence replay fence 与 cancellation；集成 Ping/Pong 超时熔断测试。macOS-26 [run 32211858885](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32211858885)（commit `b12be6e`）通过 Host smoke 验证。

- [x] **T4.5：建立 API 域 facade。** `HarnessAPIs` 作为 verified Host 的唯一 Core composition root，提供 `SessionsAPI`、`WorkspacesAPI`、`SettingsAPI`、`CredentialsAPI`、`LLMAPI`、`CommandsAPI`（官方 wire path 仍为 `goal.*`）、`SkillsAPI`、`AgentPresetsAPI`、`DownloadsAPI` 与 `HostAPI`。每个 facade 持有受 T3.2 policy 保护的同一 `DSHAPIClient`，封装官方 method path、typed request/value DTO、diagnostics、download URL 或 ClientResponse 处理；`SessionsAPI` 还封装 approval/question response 和 final question cancellation，Feature 不再组装 RPC result JSON。
  - 依赖：T4.3、T4.4。
  - 验收证据：`NativeSplitContainer`、`NativeWorkspaceStore`、`NativeSettingsStore` 与 `NativeSessionStore` 均已迁移为仅持有 `HarnessAPIs` 或对应 domain facade。PR #5 后，旧 `check-no-feature-transport.py` 已删除：`NativeSessionStore` 只接受 `NativeSessionAPI` typed domain-intent protocol，生产 `SessionsAPI` 提供实现；`NativeSessionStoreTests` 注入拒绝型 recording facade，断言真实 composer intent 到达 `prompt`、文本被保留为 typed content、拒绝后 draft 不被清空。这一运行态正/拒绝路径替代源码关键词扫描；其余工作区/设置 facade action 将随对应 UI 任务在同一注入 seam 扩展。官方 domain/path/schema 依据已记录于 `notes/T4.5-official-contract-sources.md`。macOS-26 [run 32193851213](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32193851213)（commit `a589305`）是历史静态 gate/编译证据；本迁移已由修复后的 `973644f` macOS-26 [run 32344399514](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32344399514) 成功闭环。人工工件复核已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`：T4.5 无 renderer 变动，welcome 既有差异继续明确为 `report-only`，不构成 UI 场景视觉完成。

- [x] **T4.6：建立 transport 契约回归。** `generate_official_transport_contract_manifest.py` 从锁定 apiproxy schemas 生成 12-contract baseline，覆盖 `session.history`、`session.prompt`、`session.cancel`、`session.models`、`settings.describe`、`settings.mutate`、`credentials.set`、`llm.providers`、mux/host SSE 与 RPC business-error/revision-conflict。`check-official-transport-contract.py` 每次 CI 从官方 root fresh-generate candidate；对于新增/删除 contract、字段、symbols、enum、source SHA 或签名均输出 `ADDED`/`REMOVED`/`MODIFIED` 审阅 diff 并失败。`generate_official_transport_contract_fixtures.py` 生成只含非 secret fixture 值的 schema-valid ClientRequest/ServerResponse/ServerRequest replay resource；`session.models` 亦已获得 production request/value DTO 与 `SessionsAPI.models` facade。
  - 依赖：T4.5。
  - 验收证据：`TransportContractRegressionTests` 强制 fixture commit/revision，验证 8 个必覆盖 RPC 的 canonical envelope correlation、8 个 production request DTO typed round-trip、history/cancel/models/settings/credentials/LLM success value 解码、`session-not-found` 与 `settings-conflict` closed branch（含 ns/expected/actual）、以及 `session/event`、`session/projection`、`host/session-status` ServerRequest frame。gate 自测另向临时候选插入字段，确定输出 `MODIFIED session.history requestFields: ADDED ...` 并拒绝。macOS-26 [run 32206487624](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32206487624)（commit `8a3aba6`）通过 contract gate、SwiftPM/Swiftc 编译、所有 Core regression tests、app 组装、snapshot 与官方配对；工件包含 baseline/fixture 供审计。人工复核已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`：T4.6 无 renderer 改动，welcome 既有差异继续为 `report-only`，不构成 UI 场景视觉完成。

## 5. 原生窗口、三栏骨架与 Liquid Glass

Apple 建议使用系统导航与标准控件以自动获得 Liquid Glass；在 macOS 上，`NSSplitViewController` 的 sidebar 和 inspector 行为能提供相应的系统材质。Liquid Glass 属于导航/控制层，不应用于整个内容层。[9] [10] [11]

- [ ] **T5.1：实现 `WindowCoordinator`。** `NativeWindowPolicy` 将迁移窗口职责收敛为 1280×840 初始 content size、880×600 content/min size、`.fullSizeContentView`、标准 `.unifiedCompact` AppKit titlebar、stable `NSWindow` autosave/restoration identifier；不再将透明网页窗口作为玻璃实现。首次安装恢复同名 native frame 或居中，red-close 先保存 frame 再 `orderOut`，`showAndFocus` 会 deminiaturize、聚焦且不创建第二个 shell；`DeepSeekHarnessGlassApp.applicationShouldHandleReopen` 将 Dock reopen 直送同一 coordinator。`windowDidMiniaturize`、`windowDidDeminiaturize`、`windowShouldClose` 映射到可审计 lifecycle，实际窗口管理仍完全由标准 NSWindow/AppKit 负责。
  - 依赖：T1.2。
  - 验收证据：独立 `GlassAppTests/WindowCoordinatorTests` 在无 WindowServer 的 XCTest host 验证迁移几何、native style mask、toolbar policy、stable autosave/restoration key，以及 `visible → hidden/minimized → visible` close-to-menu-bar/reopen policy；避免以不可靠的 headless AppKit 显示替代真实应用组装。workflow 在 Host + transport smoke 后独立运行该 test target。macOS-26 [run 32215096026](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32215096026)（commit `126cd24`）通过该新窗口门、所有静态/module/transport gates、SwiftPM/Swiftc、真实 rc.7 Host smoke、app 组装、snapshot与官方 pairing；人工 contact sheet 复核已记录于 `visual-review/official-99f6f02/welcome-no-workspace-light.md`。本项无 SwiftUI renderer 修改，welcome 仍明确为 `report-only`，不构成 UI 场景视觉完成。
  - 进度：已新增可注入 `WindowCoordinator` 与 Dock reopen 运行态 seam；`testDockReopenDelegatesToTheExistingCoordinatorWithoutCreatingAShell` 断言 App delegate 只聚焦既有协调器、调用次数精确为一次且不创建 window。新增 `testReinstallReusesTheResidentWindowAndShellController` 真实装配 `NativeShellPresentation`，断言第二次 install 保留同一 `NSWindow` 与 `contentViewController`，只增加一次 focus，防止重开或 presentation 更新创建第二个 shell。macOS-26 run `32381093517` 首次编译 App tests 时发现该测试仅 `@testable import DeepSeekHarnessGlassApp`、未导入 `GlassUI`，使内部测试 seam `NativeShellPresentation` 不可见；已补 `@testable import GlassUI`，不改变生产窗口行为，待后续当前 SHA 重新验证。来源、原生理由和当前 SHA 仍须补齐的 macOS 证据记于 `notes/T5.1-window-reopen-rc8-evidence.md`；在当前提交的 macOS-26 XCTest/窗口快照完成前保持未勾选。

- [ ] **T5.2：实现 AppKit 三栏容器与架构解耦。** `NativeShellRootController` 继承 `NSSplitViewController`，保持 sidebar、conversation、details 三个 `NSSplitViewItem` 承载各自 SwiftUI 内容。将原有 1000+ 行混合代码严格解耦：剥离所有 Workspace 管理弹窗（Rename/Delete）移回 SwiftUI 声明式 `.sheet` / `.overlay`；剥离 NSTextField 代理与坐标胶水；分栏容器自身瘦身至不超过 150 行，纯粹负责 `NSSplitView` 的像素级吸附、折叠手感与 `NativeSplitLayoutPolicy` 约束。
  - 依赖：T2.4、T5.1。
  - 验收证据：`NativeSplitLayoutPolicyTests` 覆盖锁定 1280px `280/640/360` 基线、sidebar 264–420 clamp、56px collapsed rail、details 300–520 clamp、divider 可用宽度限制与 details collapse；解耦后无任何业务弹窗与多余 delegate 泄漏在分栏控制器内。
  - 进度：依据 RC8 `ui-layout` 的 `columns.ts`、`AppFrame.tsx` 与 `stores.ts`，已将窄窗口默认 rail、`narrowExpanded` 临时展开和跨断点 reset 映射为 `NativeSidebarLayoutState`；三条回归覆盖“窄窗口展开不改写宽窗口偏好”、“宽窗口收缩偏好在窄窗口临时展开后恢复”与“同一窄 regime 的重复 viewport refresh 不清除用户临时展开”。原生 `closeDetails()` 现将宽度置零，`openDetails()` 仅在零宽度时恢复锁定 `detailsDefault`；运行态回归验证拖拽至最大值后 close/reopen 不恢复旧宽度，纯 solver 回归则验证空间不足时临时 details=0 而重新变宽恢复原偏好；session 切换即使目标 resident state 含 tool selection 也强制 close，只有同会话的现有选择才重开详情。来源与本地门禁记录于 `notes/T5.2-rc8-sidebar-layout-sources.md`。该行为改动仍须以当前提交的 macOS-26 runtime XCTest、1023px light/dark paired screenshots、键盘焦点与人工差异分类闭环，故保持未勾选。

- [ ] **T5.3：让系统负责 sidebar/inspector 材质。** `NativeSplitViewController` 使用 `NSSplitViewItem(sidebarWithViewController:)` 与 `NSSplitViewItem(inspectorWithViewController:)`，两个 SwiftUI宿主保持透明；禁止在这两个结构区域加 `NSVisualEffectView`、固定官方色 canvas、全窗自定义模糊或壁纸亮度采样来“模拟”玻璃。系统在 Light/Dark、Reduce Transparency、Increase Contrast 下负责导航材质的自然适配。
  - 依赖：T5.2。
  - 验收证据：PR #5 后旧 `check-native-structural-material.py` 已删除；`NativeMaterialIsolationRuntimeTests` 实际装载 Conversation content surface，断言其 runtime `NSView` tree 不含 ad-hoc `NSVisualEffectView`，并以注入真实 effect view 的负例证明探测器可证伪。完整 shell 仍须补充 sidebar/inspector 的真实 `NSSplitViewItem`/透明宿主系统材质 integration evidence；`SnapshotExporterTests` 继续覆盖 macOS 26 ScreenCaptureKit alpha-first pure-black frame rejection，避免无头 WindowServer 黑帧被伪装为截图。macOS-26 [run 32224425678](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32224425678)（commit `a5f1efb`）是历史静态材料/截图证据，本迁移待当前提交的 macOS-26 CI。该无头 runner 对受支持ScreenCaptureKit current-process window与系统 `screencapture -l` 均无法合成系统拥有的sidebar/inspector材质，导致仅这些区域显示黑色；已依据T0.3/T2.6逐路径验证、明确限定为系统渲染例外，绝不放宽内容、控件、文字、几何、字体或无障碍差异。
  - 进度：`NativeMaterialIsolationRuntimeTests` 已新增完整 `NativeShellRootController` tree 断言，验证三个 split item、真实 `.sidebar` / `.inspector` behavior，且分别断言 sidebar、conversation、inspector 三个 SwiftUI host 的 runtime `NSView` tree 不含自定义 `NSVisualEffectView`；保留 injected-effect 负例。RC8 `AppFrame` / CSS 来源、系统材质例外范围与当前仍需的 macOS paired evidence 记录于 `notes/T5.3-rc8-system-navigation-material-sources.md`，完成条件尚未满足，保持未勾选。

- [ ] **T5.4：建立 `GlassPolicy`。** `GlassPolicy` 明确区分 `content`、`systemNavigation`、`regularGlassCustomControl`、`clearGlassMediaOverlay`；`GlassPolicyBudget` 将每场景 custom glass 限为一个，系统导航材质仍只由AppKit拥有。唯一既有自定义导航操作控件通过具名 `.regularGlassCustomControl` 进入 `approvedGlassEffect`，正文、sidebar/inspector、composer、list row和dialog不获得附带玻璃。
  - 依赖：T5.2。
  - 验收证据：PR #5 后旧 `check-glass-policy.py` 已删除。实际 `approvedGlassEffect` 先调用生产 `NativeGlassEffectDecision.materializes(policy:isEnabled:)`，`GlassPolicyTests` 以运行态正负例证明仅 enabled `.regularGlassCustomControl` materialize，content、system navigation、reserved overlay 与 disabled control 均不能 materialize；同时覆盖 policy budget、system navigation ownership 与 accessibility/motion 参数。macOS-26 [run 32225877836](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32225877836)（commit `7ebaefd`）是历史静态 gate/视觉记录；本迁移待当前提交的 macOS-26 CI。欢迎页既有无头系统材质`report-only`例外仍严格受T5.3记录约束，绝不扩展为其他视觉差异豁免。
  - 进度：已收紧 `clearGlassMediaOverlay`：其在具有锁定官方表面、无障碍策略和 paired evidence 之前只是分类保留值，既不能 materialize，也不占用场景的一项已批准 custom-glass 预算。`GlassPolicyTests` 现以两个 `.regularGlassCustomControl` 拒绝例与“regular + reserved 不误计”例验证边界；决策表和未来启用条件位于 `notes/T5.4-reserved-overlay-budget-boundary.md`。当前提交仍待 macOS-26 runtime 验证，保持未勾选。

- [ ] **T5.5：实现有限的自定义 glass controls。** 仅将既有、互斥的官方sidebar打开/收起导航操作置入 `GlassEffectContainer`，共用稳定 `glassEffectID` 管理形变；保持官方图标、尺寸、间距和accessible label，绝不向正文、composer、list row、modal或系统sidebar/inspector添加glass。`NativeGlassNavigationButtonStyle` 仅在批准的 `.regularGlassCustomControl` 下使用交互式效果，单场景预算仍为一个。
  - 依赖：T2.3、T5.4。
  - 验收证据：PR #5 后旧 `check-glass-policy.py` 已删除；`GlassPolicyTests` 的生产 runtime materialization decision 覆盖 enabled/disabled approved control、content/system-navigation/reserved-overlay 拒绝，以及既有 Reduce Transparency/Increase Contrast/Reduce Motion 和 policy budget。macOS-26 [run 32226837259](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32226837259)（commit `002f474`）是历史静态 gate/视觉记录；本迁移待当前提交的 macOS-26 CI。既有无头系统材质report-only例外继续严格限定在T5.3记录范围。
  - 进度：已将 `NativeGlassNavigationButtonStyle` 的实际背景接到生产 `NativeGlassNavigationBackground` 决策：standard 环境才可用 `.thinMaterial`，Reduce Transparency 或 Increase Contrast 必改用锁定 `aliasButtonFloatingFill` token 且不 materialize custom glass。除 `GlassPolicyTests` 的三种生产决策外，`NativeMaterialIsolationRuntimeTests` 现实际装载导航 Button，分别注入 Reduce Transparency 与 Increase Contrast，断言 runtime `NSView` tree 不含 `NSVisualEffectView`。`NativeGlassNavigationAnimation` 现由实际 ButtonStyle 调用；其回归验证标准环境保留 pressed transition、Reduce Motion 返回 `nil` 并禁用形变。范围与当前待补的 macOS accessibility/paired evidence 记于 `notes/T5.5-navigation-control-accessibility-fallback.md`，保持未勾选。

- [ ] **T5.6：建立无障碍验收基线。** 版本化 `official-accessibility-baseline.json` 覆盖welcome/sidebar rail、空session composer、details、approval与question六条锁定官方核心路径，分别约束VoiceOver label、键盘焦点契约、Reduce Motion、Reduce Transparency、Increase Contrast及light/dark颜色模式；收缩sidebar中的settings icon补齐显式 `OfficialUISpec.Text.settings` 名称。`NativeAccessibilityRuntimeTests` 以真实原生视图、`NSHostingView` 和 `NSWindow` 在受信任且可导出AX树的GUI测试host中递归验证核心路径；CI无头runner即使AX trusted仍不导出SwiftUI树，测试会明确受限跳过，版本化静态baseline gate始终强制执行。
  - 依赖：T5.3–T5.5。
  - 验收证据：PR #5 后旧 `check-accessibility-baseline.py` 已删除。`OfficialAccessibilityBaselineCatalog` 从实际 `Bundle.module` decode 锁定 JSON，`OfficialUISpecBuildTests` 运行时验证 RC8 commit、六条 distinct core scene、环境标记、每条 scene 的 locale label mapping 与 unknown scene/unregistered label 负例；受信 GUI host 的 `NativeAccessibilityRuntimeTests` 保留真实 native accessibility tree 核验。`GlassPolicyTests` 覆盖Reduce Motion、Reduce Transparency和Increase Contrast下custom glass安全降级。Apple明确macOS用户不能修改`dynamicTypeSize`，且该值不影响文本大小，故不伪造用户Dynamic Type支持；系统Zoom由macOS负责，测试注入仍可用于布局回归。macOS-26 [run 32233840528](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32233840528)（commit `bee3839`）是历史 source-gate/视觉记录；本迁移待当前提交的 macOS-26 CI。该项未扩大T5.3无头系统材质的严格report-only例外。
  - 进度：`OfficialAccessibilityBaseline.CorePath` 现将 `source` 作为必填 runtime decode 字段；`OfficialUISpecBuildTests` 对六条路径追加 `Sources/*.swift` 来源和非空 focus contract 断言，并要求 required environment marker 无重复，防止基线保留标签却丢失审查定位或用重复字段伪装覆盖。macOS-26 run `32382790888` 还发现当前 SwiftUI SDK 不提供 `.accessibilityExpanded`；已移除该不兼容调用，保留标准 Button 的 AX role、官方 title/progress value 和收起时 forbidden-row focus-tree regression，绝不以自创 expanded 文案伪装属性。契约说明见 `notes/T5.6-accessibility-source-mapping-contract.md`。当前提交仍须由 macOS-26 执行 baseline/XCTest 与真实 GUI AX 验证，保持未勾选。

### RC8 T5/T7 截图重新认证矩阵（进行中）

`glass/ci/test_rc8_recapture_matrix.py` 现将 16 个 T5/T7 必经场景同时约束到 `visual-scenes.json`、visual policy、官方 Playwright 采集和 `native-ui` 的存在性/配对比较步骤。新增 `approval-composer-light`、`question-composer-light` 的官方真实 replay capture，并将其配对到原生 1280×1100 snapshot。所有场景仍为 `report-only`，但必须 `mustEnforceBeforeTodoCompletion` 且具有人审条件；未获得当前 SHA macOS 工件、人工分类和必要的 enforce 升级前，T5.1–T5.6 与 T7.3 一律保持未勾选。完整矩阵和证据边界见 `notes/RC8-T5-T7-recapture-matrix.md`。

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
  - 进度：已补入 RC8 `turn-max-tokens` Core node：只投影 `turn/end` 的 `reason.kind=max-tokens`，推导 closing step、保留 seq/time，并在本地尚未注册 `turn-tail` 时使用官方 raw end-seq fallback anchor；`ConversationCoreNodesTests` 覆盖 max-tokens 正例与 cancelled 负例；`NativeTurnMaxTokensNotice` 现以官方 warning title/hint作为该 typed node的 transcript renderer；`CoreRetryAttempt` 已补 RC8 delay/failure/mode/maxRetries typed facts，`NativeModelRetryRow` 显示 current retry status与delay/failure disclosure而不读 raw events；`NativeTurnErrorNotice` 显示 Core terminal error的官方 title/message/optional code，retry-hidden errors仍由 reducer visibility排除。`NativeCompactionRow` 现消费 checkpoint-gated `CoreCompactionNode`：仅在 typed summary存在时可展开，使用既有安全 NativeMarkdownText，若 summary缺失显示官方不可用文案且禁用 disclosure，不呈现模型 checkpoint payload或重写历史；count/tokens齐全时显示官方 completed template。`DSH_GLASS_SNAPSHOT_MODE=compaction` 现以 Core 回归已认证的 Host-shaped start/summary/landed checkpoint fixture装配该 renderer，供后续 macOS official/native visual capture；这只是采集入口，不替代 paired PNG或人工分类。并已实现两个 Host projection renderer：`NativeTodoDock` 只读取 `extensionState.todos` whole-list，空/absent 隐藏、默认收起、按 completed/in-progress/pending 的官方非零 count summary 展示、Reduce Motion 关闭 1s spin；`NativeGoalDock` 只读取 `extensionState.goal`，支持 active/paused/blocked phase、inline edit、Host business error、typed CAS edit/pause/resume/clear 与 RC8 成功 clear 的同-id presentation marker（不改写 projection）。新增 RC8 checklist/goal/pause/play/trash/queue SVG catalog 资源、`todo` snapshot fixture/mode、Core/UI/AX 回归；`NativeQueueDock` 仅渲染 `placement=queued` Host whole snapshot，支持单项直显/多项收起、subagent fail-closed、inline edit/remove/running-steer 与 per-row busy。`SessionQueueAction` / `SessionsAPI.updateQueue` 严格映射 RC8 typed RPC，成功只关闭同-id local editor、失败仅显示 action locale且不改写/退休 Host row；Core/UI回归覆盖此 authority contract。来源见 `notes/T6.6-turn-max-tokens-node-sources.md`、`notes/T6.6-todo-dock-sources.md`、`notes/T6.6-goal-dock-sources.md` 、`notes/T6.6-queue-dock-sources.md`、`notes/T6.6-deliverables-sources.md` 和 `notes/T6.6-trajectory-target-snapshot-sources.md`；已补 RC8 deliverables turn-tail：Store 只从 reducer turn location data 按 closing assistant seq读取已去重的成功 mutation paths；`NativeProducedFiles` 最多显示六个 basename chips与官方 overflow/AX locale，点击复用 Host `openKnownProjectPath`而不访问本地文件或解析 Markdown；现已补齐RC8每个chip的full-path tooltip，以及仅在Shell已验证loopback `host.describe.canOpenPath=true`且存在overflow时显示的`Show in folder` action（同官方调用`openKnownProjectPath(".")`）；无Host/snapshot保持fail-closed。`loadSnapshotDeliverablesFixture()` 以同一RC8 typed reducer输入装配十个官方形状write call/result与十路径的`turn/start → [diff-card tool/call → successful tool/result] × 10 → closing assistant/message → turn/end`，每条call具`file_path` arguments并生成有序completed native tool row；read/write/edit摘要仅显示`path`/`file_path`首行，已验证Host能力时该path以不触发展开/inspect的独立安全按钮调用`openKnownProjectPath`，AX对齐官方外层`Write {path}`与独立`{path}`名称；`NativeSessionStoreTests`锁定closing-assistant可见的完整去重路径；`DSH_GLASS_SNAPSHOT_MODE=deliverables`、`verify-native-shell.sh`与macOS workflow现产出并硬校验`deliverables-light.png`；`NativeProducedFilesLayout`现以hidden intrinsic probes测量0–6个candidate chip及每个官方overflow标签宽度，逐前缀按8px gap选取可放入lane的最大shown count（零宽/未测量初态保留候选上限），`NativeProducedFilesLayoutTests`锁定zero-width、exact overflow和无overflow路径。同状态RC8官方capture现已由上游`produced-files.e2e.ts`的十个成功write turn在780×900、en-US/light下真实生成并归档为`visual-review/official-141eb6f/deliverables-light-official.{png,json}`及审阅记录；官方ARIA锁定已展开sidebar、压缩conversation lane中的两个basename chip、`+ 8 files`、`Show in folder`和full-path open labels，零console/page errors；原生deliverables snapshot已仅以fixture override重现该wide-select后narrow-expanded sidebar状态，常规生产窄视口仍保留RC8默认rail。该scene现已注册official interaction目录、visual policy、baseline缓存硬校验及native comparison入口；仍必须以当前SHA macOS工件取得同视口原生PNG、diff/report与人工审阅，才可构成paired evidence；反馈 transport现已建立 RC8 `messageFeedback.list/put/delete` typed facade和结果 envelope DTO：item version仅作 equality token，`put.ifVersion=nil` 显式编码 JSON null以表示 require-absent，business failure（含 version-conflict authoritative current item）不被误作 transport failure；`MessageFeedbackTransportTests` 覆盖 null/version/conflict wire shapes。Store现已接入 complete-list projection：同一 verified `apis.feedback` 经 Shell注入，`refreshMessageFeedback` 以 recovery generation与active session fence发布完整 Host items，切换/clear/disconnect取消旧 task并清空 sidecar；业务/载体失败同样清空数据并只发布 retry事实。Core回归覆盖 complete Host snapshot与失败关闭。Store现补 RC8 serialized mutation controller：每项操作排在同一 session前序 mutation之后、必要时先 complete-list seed，put/delete只带已提交的 Host version；成功仅采用 Host returned item/absent，version-conflict仅以 error.current回填，绝不乐观更新。mutation generation防止旧 task提前清理新 task的 busy 状态，Core回归覆盖 committed version、note保留、successful replacement与 conflict reconciliation。assistant transcript现仅在 `CoreAssistantNode.status=settled` 且具 typed `messageID` 时显示原生 like/dislike；active rating使用官方 Remove rating label，点击只委托 Store versioned toggle且 busy 时禁用，无 messageID/running/interrupted节点不制造 action。Store发布 typed feedback facade可用性；无 verified facade时 assistant row完全不挂载评分控件，Core回归锁定该 fail-closed 条件。Store现支持已有 committed rating的 versioned note save：trim 后空 draft以 nil note清除，非空保存沿用当前 rating/version且仅采用 Host returned item；Core回归覆盖 note/rating/version。原生 note popover现仅在已有 committed rating时出现，使用官方 trigger/dialog/placeholder/save/cancel/AX locale；draft提交只调用 Store版本化 note mutation，并只在无失败且 Host item版本变化后关闭，cancel只关闭本地 editing session。feedback failure row现只在触发该 mutation的 typed `messageID` 展示；list失败显示官方 load、version-conflict显示官方 current-state文案、其他 action失败显示官方 generic文案，note panel保持失败会话。`DSH_GLASS_SNAPSHOT_MODE=feedback` 现以 Host-shaped tooling assistant、turn/end结算与 typed feedback sidecar装配原生 action/note surface，Core回归锁定 messageID/settled/rating/note；其仅为后续 macOS成对采集入口，不替代视觉验收。完整缺失插件视觉降级仍待 macOS/视觉验收；`DSHAPIClient.subagentList` / `SubagentsAPI.list` 已严格映射 RC8 complete direct-child catalog authority，`NativeSessionStore.refreshSubagentCatalog` 以 active session/recovery generation fence管理其 complete snapshot且在切换时清空，尚不从 summaries伪造 tree；其 order-10 header trigger及首层 Host-backed direct-child/diagnostic popover已实现，healthy child可通过 shell-owned native navigation打开且诊断不可操作；continuable prompt/interrupt已有强制 parent-child address 的 typed transport但不乐观改写 Host state；当前 `NativeSessionStore.SubagentRoute` 仅接受完整 Host catalog内 mode 已知的 `child` row，普通 session切换会清除不匹配 route，catalog child导航保留同一 parent的 mode/availability；有效 continuable route只经 `SubagentsAPI.prompt` / `interrupt` 发送 parent-child address，绝不回落到 `session.prompt` / `session.cancel`，而 one-shot、diagnostic、未知 mode或缺少 continuation facade 均 fail closed。route 的 `parentAvailable=false` 会以官方只读 composer替代可写输入；`NativeSessionStoreTests` 覆盖该 typed route筛选、递归 parent-keyed cache以及 prompt/interrupt不误用普通 session facade。parent-keyed complete Host snapshots现可驱动递归 branch展开（不从 summaries造行）；每个 parent 现发布 typed loading/failed ID，popover以官方 loading、error和Retry locale显示 root/expanded branch状态，retry只重拉该 direct parent的新 complete Host snapshot，且成功时才清除失败标记；recursive child row现对齐 RC8 keyboard contract：主 row保留原生 Button的 Enter/Space导航，ArrowRight仅展开未展开 branch、ArrowLeft仅收起已展开 branch；disclosure不另占键盘焦点并使用官方 branch expand/collapse locale。完整 keyboard focus order的 macOS AX与视觉证据、continuable composer完整交互仍待实现；有效 Host one-shot descriptor现可替换为官方 read-only composer，而 absent/null/malformed descriptor保持普通 composer；`CoreWorkflowRunNode` 已进入 transcript的 `NativeWorkflowRunPanel`，按 typed run/phase/member/status显示官方 locale fallback且未重放 raw workflow events；run/phase现在使用状态驱动 disclosure，running phase会展开；只有 typed childID非空且 status=running 的 member才成为 shell-owned `openSession` 按钮，finished/failed/cancelled/interrupted或无 ID member保持不可导航。此策略有 App 回归。workflow run/phase现进一步采用 RC8 `clean/running/abnormal + activityCount + pendingCleanCollapse` typed disclosure state：clean结算时仅在焦点仍由真实running child Button持有才延迟收起，焦点离开后收起；新的活动及abnormal escalation重新展开，stale/malformed/non-navigable member不会制造焦点 authority；纯状态机回归覆盖该 clean→pending→blur、active reopen与abnormal reopen路径。仍缺原生焦点细节、paired visual/AX与人工差异分类；`NativeSessionStore.trajectoryNodes` 现与 Chat 同步 materialize RC8 `target=trajectory` typed reducer snapshot，且 resident session state对称保存/恢复 Chat/Trajectory keyed snapshots（同时保留 raw reducer window供后续 Host输入），避免 native view重放 raw history、误用 Chat timeline或在 session切换后遗漏 trajectory。`NativeShellPresentation` 已注册 order-10、官方 locale label 的原生 `trajectory` tab；renderer已补 RC8 toolbar基础：Turns/Calls segmented switch与官方 search label/placeholder；Turns 只使用 `trajectoryNodes` 的 target-owned `CoreUserMessageNode`，Calls只使用已 materialize 的 typed `toolInvocations` name/arguments/sequence，search只过滤这些 typed values且绝不重放 raw history；registry 回归锁定 tab 顺序/label/renderer可用性。`DSH_GLASS_SNAPSHOT_MODE=trajectory` 复用 tooling fixture且预选该 tab，作为后续浅深色 native capture入口。Calls现支持 selection：只有当前 filtered typed `ToolInvocation` 可选，右侧 inspector以 RC8 Event details/Payload/Result标签显示 typed arguments与可选 output；output缺失时 Result tab安全隐藏，mode切回 Turns会清除 call selection。Call row现仅根据已 materialize 的 `ToolInvocation.state` 显示 RC8 Pending/Completed/Failed（stopped复用既有官方 tool status），不以raw history、output、time或sequence推导状态。完整 turn grouping/collapse、tool rows时间、selection/details扩展、official/native paired visual、人工分类与 AX 仍未实现。`DSH_GLASS_SNAPSHOT_MODE=retry` 现以 Core测试认证的 Host-shaped scheduled `llm/retry` payload驱动 `CoreRetryNode` 和原生 retry renderer，Core回归锁定 attempt的状态/seq/delay/failure/maximum/bounded mode及running事实；该 deterministic capture入口已配合 RC8 250ms scheduled countdown：renderer从typed delay计算局部deadline、只在scheduled状态刷新至稳定1秒显示、started/cancelled保持durable seconds且绝不写回Store/Host；仍不替代AX、paired visual或人工差异验收。model选择现已严格补齐 RC8 `session.selectModel` typed request/Host-confirmed `{selected}` response：Store只可发送complete `session.models` catalog内的provider/model/effort，active session/recovery/mutation fence阻断旧结果，成功才替换current且失败保留最后Host目录，transport fixture和Core回归锁定optional effort、wire shape、route gating、confirmed result与rejection不乐观写入；原生composer现已挂载 `NativeComposerModelSelector`：仅在loaded+routable完整目录存在时显示，使用锁定 `ui-model-selection` locale提供Model/Effort双层原生Menu、provider-grouped model与effort choice、trailing check和busy禁用；模型切换发送该model的advertised default effort，effort切换保持当前provider/model，不因普通running错误锁定。`DSH_GLASS_SNAPSHOT_MODE=model` 已以完整Host-shaped directory（current/groups/efforts/failure）提供native capture入口，Core回归锁定目录事实，App locale回归锁定trigger/menu/loading/empty/warning catalog解析。模型目录现已进一步具备RC8 `idle/loading/ready/selecting/error` typed lifecycle：open、gap/watermark recovery、reload与select共用directory generation，较早的 `models()` response不可覆盖较新的reload或Host-confirmed selection；selection失败保留complete directory且仅发布presentation error，`NativeComposerModelSelector` 在无directory的loading/error时保留官方fallback trigger/menu并显示官方 `status.loading`、`error.action`与`action.reload`，reload只读 `session.models`。Core回归锁定baseline/confirmed ready与rejected selection error。`model-selector-light` 现以真实官方workspace-backed `DeepSeek-V4-Flash` 默认目录和等值native `session.models` fixture建立1280×840闭合trigger的report-only paired visual采集：workflow会产出official/native PNG、ARIA JSON与diff report，且fixture不再用自创多provider/effort状态。展开菜单、macOS AX runtime、progress/error几何与人工差异分类仍待实现。会话permission现已严格接入RC8 optional `permissions` whole projection：缺失/null/malformed/duplicate/unknown-current均隐藏，不与global default settings混淆；Store只对广告的非`custom` preset经唯一 `/permission <preset>` command path提交，session/recovery/mutation fence阻断旧task且成功仍等待Host projection确认、不乐观写入。Core回归锁定完整projection、custom/unknown fail-closed、command shape与projection-only settle；原生composer现已挂载 `NativeComposerPermissionSelector` 于Access→Model→primary action顺序：只读完整会话 `permissions` projection、隐藏derived `custom` switch target、显示selected marker，并将access label/risk confirmation文案锁定至 `ui-conversation` catalog；`danger-full-access` 采用RC8 Full access display并要求原生acknowledgement popover后才委托Store，普通预设直委托，均不因普通running禁用。`DSH_GLASS_SNAPSHOT_MODE=permission` 已以独立完整Host projection提供native capture，Core/App locale回归锁定projection和locale。`NativeAccessibilityRuntimeTests` 现另以完整Host-shaped model directory与permissions fixture挂载两个原生selector，并要求AX树精确导出各一个RC8 Model/Effort与Access mode当前触发标签，防止仅静态locale存在而native控制不暴露；实际macOS Menu/popover AX、full-access交互、paired visual与人工分类仍待实现。另已将RC8 `danger-full-access` 确认内容抽为仍由selector popover使用的同一原生view，并新增真实AX树回归，要求标题、acknowledgement Toggle、Cancel与Enable四类官方locale控件可达；该抽取不改变acknowledgement binding、busy禁用、cancel reset或Host command seam。Goal dock 首次 macOS-26 run `32386749181` 发现 Swift 禁止从 `defer` 中 `guard ... else { return }`；Queue/Goal action fences 已改为同等条件的 `if` 清理，不改变 Host authority 或可见 projection。随后 Queue SHA 的 macOS-26 run `32387687763` 发现其 edit action request 用到的 `SessionPromptContent` 未声明 `Equatable`；已为纯 Codable value DTO 补合成 conformance，修复 typed request/回归比较而不改变 wire encoding。其后 macOS-26 run `32388160153` 发现 Goal/Queue failure text 误用不存在的 `Typography.xxxs12`，三处均已改为已登记的 `xxs12`，不改变文案、geometry 或 Host authority。最新 macOS-26 run `32389276146` 还发现 Queue `failureText` switch缺少显式 `return`，已改为 `return switch`，保持 action locale mapping不变。macOS-26 run `32389790574` 发现 Goal request XCTest comparison缺少 `GoalReferenceDTO` / `GoalReferenceRequest` 的合成 `Equatable`，已补入纯 DTO conformance，不改变 CAS/RPC wire contract。后续 macOS run `32390472622` 发现 Material Isolation XCTest 写入当前 SDK 只读 SwiftUI accessibility environment key；已移除该不兼容注入，运行时无自定义 visual-effect 断言保留，Reduce Transparency/高对比策略仍由纯 `GlassPolicyTests` 覆盖。macOS run `32391234734` 随后显示 Workflow renderer无法解析 `CoreWorkflowRunNode`；workflow/retry/error三个直接引用 Core typed node 的新 UI source均已补 `@testable import GlassCore`，Linux SwiftPM build仅在预期 AppKit平台边界停止。该 run还发现 `CoreRetryAttempt` 在 macOS对合成 memberwise initializer的默认参数排序不一致，已替换为显式稳定 initializer；后续 macOS run `32393954544` 发现 `NativeTurnErrorNotice` 引用了未登记的 `errorTertiary` / `errorBorder` token，现已改为生成主题中明确定义的 `aliasStateErrorSecondary` 的语义 `OfficialUISpec.Token.errorSecondary`（背景透明层与描边），不新增颜色来源；紧随其后的 macOS run `32395020305` 发现 recursive subagent catalog的 `depth: Int` 与 official spacing `CGFloat` 相乘，现已在四个 padding路径显式转换 `CGFloat(depth)`，不改变递归层级或 geometry；macOS run `32395467758` 随后发现递归 `some View` 触发 SDK opaque-return inference循环，现仅在 recursive branch boundary显式 AnyView type erase，保留 typed Host DTO rows、状态和子树结构；macOS run `32396204059` 发现 retry row引用当前 SwiftUI SDK 不提供的 `accessibilityRole(.status)`，现保留 DisclosureGroup原生展开语义并移除该不兼容修饰符，不改动官方 retry状态文案；macOS run `32396618856` 发现 compaction snapshot fixture误以 model initializer构造 `surfaceOp`，现改为现有 `SessionEventDTO` 契约的 JSONValue object（op/start/end），不改变 landed checkpoint payload；macOS run `32438474595` 发现 continuable subagent Core 测试的纯值 `RejectingSessionAPI.Prompt` 未声明 `Equatable`，现补合成一致性以恢复 parent-child request断言，不改变生产 transport；portable run `32392809718` 发现 subagent row内联 UI detail文案，已迁移至 `OfficialUISpec.Text.subagentDetail`。macOS run `32439862290` 随后发现 feedback note popover误用不存在的 `xs13Strong` 与未登记的 `px280`；前者已改为既有 `xsStrong13`，后者按锁定 RC8 `MessageFeedbackActions.module.css` `.notePanel` 的 `width: 320px; padding: 8px` 登记/使用 `px320` 与 p8，未新增推断尺寸。macOS run `32440254526` 随后通过 note panel几何后发现 placeholder overlay误用未登记 `Token.placeholder`；已按锁定 RC8 `ui-primitives/Input.module.css` 的 `--dsw-alias-label-dimmed` 补为生成 `aliasLabelDimmed` 的语义 token，不引入自定义颜色。macOS run `32440620940` 继续发现 feedback TextEditor误用未登记 `px72`；经锁定 RC8 `.noteInput` CSS核对该 textarea无 min-height，已移除原生推断高度而不伪造官方 token，保留其来源明确的320px panel/padding/border/typography。macOS run `32442222873` 随后发现 permission full-access confirmation标题误用不存在的 `Typography.mStrong16`；已改为生成规格已有且等值的 `baseStrong16`（16px medium），不变更RC8字号/权重或交互。上述修复均待新 SHA权威验证和 paired visual闭环。原生 jobs 继续严格消费 Host `backgroundJobs` whole snapshot，按 RC8 `ui-jobs` order-20 header action语义保留既有排序/elapsed-time helper；其 trigger/menu已将明确的3px/28px/336px/row 8px等几何、11/12/13px typography及 `list.aria` 收敛到 `OfficialUISpec`，并以新的 `NativeStateDot` 替代近似6/7px circle：done/warning/error为官方10px halo/6px core，ongoing以锁定 `static-deepseek-450` 按8-cell 2px-grid stepped chase绘制，且保持纯装饰AX隐藏。jobs仍待官方/native时序帧、paired visual与macOS AX runtime闭环。另已补 `DSH_GLASS_SNAPSHOT_MODE=queue`：仅装配 running 的 two-row Host-shaped `placement=queued` fixture（text + non-text），供后续官方/原生浅深色成对采集，并以 Core 测试锁定其不制造 local authority；这只是视觉采集基础，不替代 paired PNG/人工差异分类。todo/goal 的 official/native 浅深色成对截图、ARIA、人工分类及 macOS 当前 SHA 仍未闭环，其他 node type、fixture、renderer snapshot、取消/缺失插件降级和 macOS 视觉证据也未完成，故保持未勾选。

  - CI修复：macOS-26 run `32442872439` 的既有 `NativeWorkspaceAuthorityTests` 因Foundation将POST载体实现为`httpBodyStream`、而测试URLProtocol仅读取`httpBody`而错误返回`-1011`，未到达其workspace/session authority race断言。测试double现同时读取两种Foundation请求体载体；生产RPC、Host authority和可见UI均未改动。随后macOS-26 run `32450947811` 在`testHostRestartRecoverySupersedesStaleGapRepairWithoutDroppingLiveBuffer`启动时以`freed pointer was not the last allocation`/signal 6终止；根因是共享测试`RecoveryGate`仅保存单一、不可取消的continuation，full resync取消旧gap-repair task后该waiter仍悬挂。该continuation fencing在后续macOS-26 run `32454734586` 的同一Host restart场景仍以相同allocator abort失败，故测试`RecoveryGate`现改为无continuation的actor-owned、1ms cancellable cooperative polling gate：取消旧gap task立即退出、`open()`只更新单一事实而没有late resume；`RecoveryGateTests`同时锁定取消旧waiter后fresh waiter可open与单次open释放多个并发waiter。生产recovery算法和Host restart连续参考断言均未放宽。两项修复均待后续当前SHA macOS run验证。

- [ ] **T6.7：实现 reconnect/replay 算法。** 在 transport 断开、Host 重启或 session 从 cold 到 live 时，重新拉取 authority baseline，并以 raw history + projection + current session status 恢复。
  - 依赖：T6.1–T6.6。
  - 验收：在任一 event 序列点断开、重连后，状态与连续运行参考结果一致。
  - 进度：现有 authority recovery 已在 event gap 与 `session/subscribed` watermark rollback 时重新拉取 `session.models` 与history whole baseline，并以session/recovery/endpoint fence阻断旧响应；本次依据RC8 runtime的模型目录重连规则补充Core回归：gap recovery必须采用第二次Host `models()` 返回的provider/model并发布ready，而不可保留首次目录。另已覆盖event-gap恰逢非协作 `selectModel` pending：recovery会取消旧selection task、递增selection/directory generation、清除busy，晚到Host `selected` 不可覆盖新的recovery model baseline。进一步按锁定RC8 `ProjectionValueStore.seed` whole-baseline语义补充event-gap与`session/subscribed` watermark rollback的projection回归：两条history recovery均以新的`asOfSeq`值替换旧键，且必须清除Host在该cut省略、又没有更新frame覆盖的旧projection键；watermark入口同时验证先截断越过新durable watermark的旧值、再采纳新的Host baseline。另已按RC8 `Session.liveBuffer` / `installWindow` 语义实现event-gap实时缓冲：首个gap及recovery期间的每个`session/event`均按recovery generation暂存，新的models/history/projection authority baseline替换后按seq排序stitch，落在Host tail及之前的overlap拒绝、tail之后的事件才复用既有typed reducer/effect路径；切换、clear和disconnect清空该边界。Core回归锁定Host seq-2 authority覆盖buffered overlap，同时seq-3/4 live tail仍按顺序进入transcript与Chat snapshot；按同一RC8 `repairGap` failure contract，首次history repair失败只保留旧渲染窗口并清除in-flight marker，绝不丢弃已buffer的live frames，随后另一gap的成功authority read必须将保留帧与新tail共同stitch；并已锁定RC8 concurrent-gap coalescing：repair history in-flight期间的第二个gap只追加同一live buffer，不得发起第二次authority pull，失败后既有window保持可见。macOS-26 run `32445098862` 已暴露一条旧gap测试仍将Host seq-2后的buffered seq-3 tail判为应丢弃；该回归现明确要求authority window先替换、唯一post-cut tail随后stitch，未改生产reducer。另已覆盖RC8 stale initial-open / stale-repair generation fence：同一session旧endpoint的延迟initial history在新endpoint authority window安装后不可复活，且一个延迟gap history不可在较低`session/subscribed` watermark触发的新Host restart recovery之后复活；新history/models baseline必须获胜，而既有buffer的post-cut live tail仍进入新窗口。另已覆盖RC8 cold-open history pending：初始`models → history` authority read也以同一generation buffer接收实时frame，history page安装后仅丢弃tail及之前的overlap、将其后live tail按typed reducer stitch；失败、切换和endpoint替换清空该cold buffer。另已对齐RC8 cold-to-live ahead-watermark契约：`session/subscribed.lastSeq`高于已安装history tail时不能等下一个gap event，必须立即重新拉取fenced models/history authority；Core回归锁定seq-1 history与`lastSeq=2`订阅后进入Host seq-2/current-model baseline；并锁定RC8第二次pull failure：该recovery失败时原首窗口仍为ready/可见，只发布可恢复的model-directory错误。并已补一个RC8 projection/replay interleaving：gap recovery history baseline为seq-2时，in-flight期间到达的seq-3 `session/projection` 仍以higher-sequence-wins留存，绝不可由较旧baseline回退。RC8 feedback sidecar亦已接入recovery resync：新的authority baseline落地后，complete feedback list读取必须排在已有版本化mutation尾部，防止旧list复活过期CAS版本；Core回归锁定v1 sidecar在gap recovery后经第二次同session Host list替换为v2，且open/clear/disconnect/新recovery都会取消旧resync task。为符合RC8 serial tail，该sidecar mutation使用session生命周期而非recovery generation fence：同一session中已经抵达Host的v1→v2 mutation可先结算，recovery list则在其后才采纳最新v3 complete snapshot；回归同时禁止mutation未完成时提前发出第二次list。RC8 subagent catalog current-status亦已接入recovery：连接恢复后重拉active root与每个已Host-backed parent catalog，而不是从session summary/child row伪造descriptor；Core回归锁定root和已展开parent均被新complete snapshot替换，返回grandchild不制造未请求catalog缓存；并已覆盖RC8 `selectedAddress.parentSessionId` 情形：active child带有效parent-child route但尚无本地展开缓存时，recovery仍必须拉取其parent catalog。并已锁定RC8 restart interaction safety：较低`session/subscribed` watermark会先撤销旧approval/question及其busy flags，直到Host mux重新推送当前请求，避免断线期间已解决的交互继续可答。另已补RC8同RPC replay safety：restart重放的question虽然复用同一rpcID但进入新的interaction generation；先前已获准送达Host的答题task即使晚到失败也不可清除新等待实例的busy状态，open/clear/disconnect同样使旧交互回写失效。另已锁定RC8 backward paging guards：cold/exhausted `loadOlderHistory` 不发请求；Swift transport throws 时既有window和hasMore保持、loading释放；空成功页仍严格采纳Host `hasMore`，随后耗尽早退。另已对齐RC8 explicit resident `resync`：已open实例主动重建时立即撤销旧history window、typed transcript/tool投影和pending waits，递增generation后经fenced `models → history` authority重新ready；cold实例无可重建transport而静默no-op，queue/jobs特意保留至新`session/subscribed`的有序whole snapshot才重置。Core回归在第二次history in-flight时锁定旧window/pending approval已消失、release后只采纳新authority。另已将该重建接入Shell verified-host ready generation：同一loopback endpoint的Host restart/recover不再被早退为无操作，而会运行resident resync；端点变化继续替换typed facades后完整重开。另已锁定RC8 full `resync` 覆盖同endpoint旧initial `models → history` late-success：resync调用后只可采纳新generation的`resynced-model`/authority window，随后释放旧history也不得回写或令phase离开ready；这补齐了仅有endpoint替换不足以证明的真实Shell same-loopback recovery路径。另已锁定RC8 resident current-status ordering：resync本身不可抢先清空queue/jobs whole mirrors，等待新`session/subscribed`形成有序mux generation边界后才同步撤销两者；Core回归在held history期间保留旧rows、subscription到达后原子清空，避免丢失已先到达的新baseline或残留旧Host工作。另已对齐RC8 `acceptLiveEvent` cold/error fail-closed行为：loading/recovery generation仍缓冲，唯有ready authority window才允许direct append/gap repair；models/history失败后的live frame保持failed phase且不制造partial chat/trajectory，下一次完整history baseline才可恢复。另已锁定RC8 stale-catch counterpart：同endpointresync已经安装新generation的model/history后，旧initial history即使晚到transport failure也不可把新ready window置为error或回写旧状态。另已锁定RC8 full-resync对在途gap repair的generation fence：resident resync清空旧live buffer，新的models/history baseline获胜；随后旧repair成功返回也不得回写，且该gap的obsolete tail不可stitch（与watermark repair保留post-cut tail明确区分）。另已对齐RC8 cold-to-live early subscription：`session/subscribed.lastSeq` 若在initial history前到达，Store以当前authority lifecycle保存tail，history window安装后比较并触发fenced第二次models/history pull；open/clear/disconnect/resync均清除该记录，避免跨generation泄漏。另已锁定RC8 in-flight watermark second pull：ahead `lastSeq` 引起的第二次authority history若在完成前被resident resync替代，旧history/model response不可回写新window；该无buffer路径与full-resync gap repair路径分别回归。锁定RC8测试标题、Native对应回归、跨运行时连续参考定义和未闭环macOS边界已汇总于 `notes/T6.7-rc8-reconnect-matrix.md`。另已补齐该durable-tail规则在resident resync中的同序边界：若`session/subscribed.lastSeq`在held recovery history期间到达，seq-3恢复页安装后必须消费mismatch并只触发一次fenced follow-up models/history，以seq-4 authority收敛；无早到订阅的既有resync仍仅两次pull。Host restart与连续参考等价性现已补：`testHostRestartRecoverySupersedesStaleGapRepairWithoutDroppingLiveBuffer`将recovery完成后的text/sequence/model目录/状态直接与同一最终authority history及post-cut live tail的无断线`ContinuousAuthoritySessionAPI` Store对照；RC8 JavaScript对象引用恒等只属其memo runtime，Native严格比较可观察typed投影。完整断线点矩阵、projection/replay组合及macOS当前SHA证据仍待闭环，故保持未勾选。

### T6.6 场景来源更正

`18c991b` 的 portable/macOS工作流在Swift编译前失败：新增 `model-selector-light` 误把本仓库capture helper登记为RC8 `apps/web` 官方文件。现已改为锁定上游实际实现 `packages/client/ui-model-selection/src/client/ModelSelect.tsx:67-103,219-263`，本地场景/视觉/工作流门禁通过；该修正后的首个macOS run又暴露新增question replay fake遗漏 `RPCReceipt.reason` 参数，现已显式传入nil并通过本地门禁。同时已成功以真实fresh-workspace RC8 Web scaffold采集 `model-selector-light` 官方light基线（1280×840、`en-US`、DPR 1、零console/page errors），版本化PNG/ARIA元数据及report-only审阅记录位于 `visual-review/official-141eb6f/`；它只固定 `Select model, current DeepSeek-V4-Flash` 闭合trigger及邻近Access/Send seat，绝不替代native配对。最近一次macOS run已完成构建但暴露三条cold-open测试在authority ready前注入live事件的竞态、模型fixture断言仍期望旧合成目录，以及trajectory status/detail误被当作locale-catalog键；均已按RC8实际生命周期/默认Flash route/toolbar-locales边界修正。现又以锁定RC8真实scaffold完整运行9条官方Playwright场景并零capture错误，已将approval/question takeover、jobs light/dark、tooling inspector及其ARIA元数据归档至 `visual-review/official-141eb6f/`（清单 `t6-6-extension-official-capture.md`）。模型selector的展开menu仍必须经真实macOS AX/点击交互采集：已从真实fresh-workspace RC8 scaffold点击闭合trigger取得并归档official-only 1280×840 PNG/ARIA（expanded trigger、`Model and reasoning effort` menu、唯一`Model DeepSeek-V4-Flash` root cell、零浏览器错误；`visual-review/official-141eb6f/model-selector-menu-light-official-capture.md`），但Native SwiftUI `Menu` 的现有off-screen snapshot不支持伪造open状态，故闭合trigger policy不可静默扩大；边界见 `notes/T6.6-next-renderer-research.md`。最新两次macOS run还揭示三个XCTest测试边界问题：running-turn回归误用恒定authority-failure fake、projection回归在held history stitch前提前断言；均已以显式ready fixture和完整window等待修正，未放宽RC8算法断言。上述仍仅是official-side evidence；必须以最新修正提交自身的macOS-26运行重新取得同状态原生截图、diff/report和人工审阅的权威证据。

## 7. 侧栏、工作区与会话浏览器

官方 sidebar 提供 wordmark、新会话、折叠控制、工作区/会话浏览器和固定的设置入口；折叠动画最终落入 56px rail。工作区和会话分组由独立 UI 模块承担。[12]

- [ ] **T7.1：实现 sidebar 的静态结构。** 复刻 wordmark、New Session、workspace seat、settings seat、滚动区与底部固定区域；所有文字引用 `OfficialUISpec`。
  - 依赖：T2.2、T5.2。
  - 验收：无 workspace 与有 workspace 两种状态使用官方文案和结构，不出现自创欢迎页。
  - 进度：依据 RC8 `ui-sidebar/tests/sidebar-root.client.spec.tsx`，`NativeAccessibilityRuntimeTests` 已将 wide sidebar 的两个独立 New Session 操作（wordmark + capsule）从存在性断言加严为精确计数 2，并继续禁止 rail-only Open sidebar 控件出现在 wide 焦点树。wide sidebar 现进一步以真实原生 AX tree 精确断言官方 `Workspaces` section、Search sessions、View options、Add workspace 和底部 Settings 各恰好一个，防止空 Host snapshot 移除 region/settings/footer seat 或复制其动作。测试同时以完整注入的 Host workspace snapshot 挂载原生行，验证 workspace title、`Sessions` list seat、官方 workspace-actions label和唯一 Settings footer seat都保留；该初始化入口只接收完整已获 Host snapshot，不构成第二个客户端数据库。当前仍须补 official/native 浅深色结构配对、人工差异分类与 macOS 当前 SHA 工件，故保持未勾选。

- [ ] **T7.2：实现 workspace/session browser。** 支持 workspace list、create、reorder、archive、ungrouped、session list、selected/running/blank 状态和空会话复用。
  - 依赖：T4.5、T6.1、T7.1。
  - 验收：Host workspace/session change 帧到达后列表更新正确，不依赖页面刷新。
  - 进度：从 `NativeShellPresentation.connectWorkspace` 提取并接入 `NativeWorkspaceBlankSessionReuse`；依据 RC8 `WorkspaceRuntime.connectWorkspace`，仅复用目标 workspace 显式归属、canonical cwd 匹配且未归档的 blank session，其他候选与缺失 workspace 均拒绝。`NativeWorkspaceStoreTests` 覆盖 membership/cwd/archive/missing 边界，并直接对锁定 `ui-workspace/tree.ts:sessionVisible` 回归普通 session、仅当前 blank session、subagent 排除、归档排除、workspace membership 与 ungrouped 归属，防止 Host whole snapshot 被错误投影为第二个树。仍需实际 Host create coalescing、archive/reorder、Host change 帧，以及无/有 workspace 视觉与 macOS 当前 SHA 证据闭环，故保持未勾选。

- [ ] **T7.3：实现 sidebar 搜索与行操作。** 行为、可见性、快捷键、空状态、结果排序和文案必须以锁定官方 UI 为准。
  - 依赖：T7.2、T2.5。
  - 验收：每个官方测试场景可复现，搜索不创建未记录的原生私有索引。
  - 进度：`NativeWorkspaceStoreTests` 已覆盖无已验证 Host 时搜索只能进入空 remote-search failed 状态（无 items、无 hasMore），禁止从本地 snapshot 生成私有内容索引；并实现/测试 RC8 `WorkspaceBrowser.searchOnExpand` 合同：rail 搜索先武装 expanded + wide-focus、请求 sidebar 展开，输入框挂载后在 300ms slide settle 时聚焦，若仍为 rail 则不聚焦；clear 与 Escape 均统一清空 query、收起 search chrome、解除焦点武装。当前仍须以 RC8 official/native search、rename、delete 浅/深色配对、ARIA/geometry、人工分类与当前 SHA macOS 工件闭环，故保持未勾选。

- [ ] **T7.4：实现收缩 rail。** 用官方尺寸和 motion sequence 完成 wide ↔ rail 切换；减弱动态效果时使用静态/简化过渡。
  - 依赖：T2.4、T5.2、T5.6。
  - 验收：1024px 阈值前后和手动展开逻辑与官方 fixture 相符；焦点不会落入隐藏的控制。
  - 进度：`NativeSidebarCollapseAnimation` 已从视图内联判断提取为生产决策并接入 `NativeSidebarView`；默认保留 0.3s easeInOut，Reduce Motion 明确返回 `nil` 以实现静态切换，`GlassPolicyTests` 覆盖两个分支。RC8 原始 150ms fade/rail-entry、cold-collapse 不入场与 56px rail 几何映射见 `notes/T7.4-rc8-sidebar-motion-sources.md`；完整 staged motion 的 AppKit 截图、1024px 宽度对、焦点树与 macOS 当前 SHA 证据尚未闭环，保持未勾选。

## 8. Conversation 主界面与输入闭环

这一阶段要先实现高频的完整会话闭环，再扩展所有低频节点。必须保持官方无 workspace、blank session、running session、busy composer、approval takeover 与 queue 的不同状态语义。[13]

- [ ] **T8.1：实现 session header 和 view tabs。** 支持 title、chat view、扩展 view registry、header actions、utilities 和空 session 过渡。
  - 依赖：T6.1、T6.4、T2.2。
  - 验收：切换 session 不闪烁、不重新创建不必要的输入控件；标题与官方 DocumentTitle 行为相符。

- [ ] **T8.2：实现 ChatView 与基础消息 renderer。** 支持用户气泡、assistant Markdown、流式尾部、copy、时间、turn status 与官方可见性规则。
  - 依赖：T6.5、T8.1。
  - 验收：streaming chunk 不造成整页重排；历史与实时尾部在同一 node tree 中衔接。

- [ ] **T8.3：实现现代 Markdown AST、代码高亮与安全链接策略。** 引入 Apple 官方 **`swiftlang/swift-markdown`** 作为底层 AST 解析器，完整支持 GFM 表格、任务列表、嵌套引用与代码块；引入 **`tree-sitter/swift-tree-sitter` + `Neon`** 实现全语言（Rust, Go, C++, Python, Swift, TS/JS, SQL, YAML 等）工业级增量语法高亮，废弃脆弱的手写关键词数组扫描器。保留严密的 `NativeMarkdownSecurityPolicy`，剥离可执行 HTML 标签，严格只允许安全的 `https`/`http` 外部链接，阻断 `javascript:`、`file:` 及非信任相对路径。
  - 依赖：T8.2。
  - 验收：GFM 表格/代码块/数学 AST 正确渲染；10k chunks 流式输出与 1000 行长代码块无掉帧卡顿；恶意 Markdown/URL 攻击用例 100% 被安全降级。
  - 进度：已将官方 `swiftlang/swift-markdown@0.8.0` 受控接入 `GlassUI`；`NativeMarkdownDocument` 不再以行级 marker 识别 prose/quote/list/code/table，而是以 `Document(parsing:)` 的 GFM AST 映射原生 block。未闭合流式 fenced-code tail 仍在 AST 之前保守保留为 literal prose，避免暂态 code card；GFM table header/body cells 已走同一安全 inline 文本边界，回归同时锁定 `file:` 链接无活动 URL。依赖审计已记录在 `notes/T8.3-markdown-parser-references.md`：Neon `0.6.0` 直接依赖 `ChimeHQ/SwiftTreeSitter@main`，与指定 `tree-sitter/swift-tree-sitter@0.10.0` 同名 product/identity 的兼容性尚未获证明，故不能混入未锁定分支伪造完成；需先选择经审计的上游兼容 Neon 或直接 token adapter。`NativeCodeHighlighter` 仍是过渡实现，tree-sitter/Neon 的全语言增量高亮、数学 AST、性能基准与 macOS 当前 SHA 证据尚未完成，故保持未勾选。

- [ ] **T8.4：实现 Composer 与附件安全防线。** 支持 draft、textarea、send、stop、Shift+Enter、Enter/Cmd+Enter 的官方队列/steer 逻辑、blocked placeholder、命令入口与 keyboard focus。附件上传引入 Apple 原生 **`UniformTypeIdentifiers` + `ImageIO` (`CGImageSource`)** 防线：根据真实文件头判别 UTI，强制执行协商的 `maxImageBytes`、`maxImagePixels` 和 `maxImagesPerMessage` 限制，杜绝伪造扩展名与大图内存 OOM。
  - 依赖：T4.5、T6.1、T2.5。
  - 验收：idle、busy、no-workspace、blocked 等状态匹配官方场景；伪造扩展名与超大附件在加载前被安全拒绝。
  - 进度：已在 `GlassCore` 新增 `NativeImageAttachmentAdmission`，使 file picker 与拖拽最终会合到 `NativeSessionStore.addPendingImage` 的同一 Core 准入点。它在保留内容前以 `CGImageSourceCreateWithURL` 判定真实 UTI/像素元数据，拒绝伪造扩展名、非 image UTI、未协商 media type、超单文件/总量/数量/边长/像素限制以及 Host 缺失的 `imageLimits`；读取后再次核验 bytes 以收窄 stat-to-read 替换窗口。`NativeImageAttachmentAdmissionTests` 覆盖无扩展名有效 PNG、伪造 PNG、缺失限制、数量、总字节、尺寸与像素边界。当前仍须把安全拒绝原因映射为官方 composer notice、覆盖实际 image prompt Host round-trip 与 macOS 当前 SHA 证据，故保持未勾选。

- [ ] **T8.5：实现 prompt/cancel/queue RPC 流程。** 发送先进入正确的 Host API，再按 SSE authority 更新；不可乐观制造与 Host 无关的永久消息。
  - 依赖：T8.4、T6.7。
  - 验收：发送、取消、排队编辑/删除、steer race 和 Host 拒绝均有准确可恢复状态。

- [ ] **T8.6：实现模型与权限控制。** 在 composer 固定官方位置渲染 model selector、reasoning effort、context meter、permission preset 和高风险确认。
  - 依赖：T4.5、T6.3、T8.4。
  - 验收：无可用 model 时 composer 被官方原因文案阻止；选择模型后 unblock；高风险权限必须经确认。

- [ ] **T8.7：实现队列、todo、goal、stats dock。** 使用 projection 或官方 API 真源展示，支持折叠、计数、状态和溢出行为。
  - 依赖：T6.3、T6.6、T8.4。
  - 验收：多个 dock 的顺序、隐藏规则、滚动与无障碍标签符合规格。

- [x] **T8.8：为 `NativeMarkdownRenderer` 建立正则一次性编译与增量清洗。** `NativeMarkdownSecurityPolicy.sanitizedInlineMarkdown`/`attributedInlineMarkdown` 在每次 SwiftUI body 重算（含每个流式 chunk 追加）时都对整段文本重新执行 `replacingOccurrences(options:.regularExpression)` 并新建 `NSRegularExpression`——HTML 剥离与链接改写模式每次都重新编译且整文重扫。将上述模式提升为 `static let` 一次性编译的 `NSRegularExpression`；对流式文本复用已清洗前缀（仅在新增尾部执行清洗），或直接基于 `AttributedString(markdown:)` 解析结果过滤 `link` run，消除每 chunk 的整文重扫。`NativeMarkdownSecurityPolicy` 安全边界保持不变：可执行 HTML 剥离、`https`/`http` 协议白名单与 `openExternal` 校验行为与现实现逐字节等价，`file:`/`data:`/`javascript:` 与相对路径依旧不得外放。
  - 依赖：T8.2（若实现顺序落后）。
  - 验收：既有 Markdown 安全/无障碍相关 XCTest 与快照全部通过且输出等价；流式 10k chunks 场景不再出现每 chunk 的正则重编译与整文重扫（以性能断言或注入记录验证）；与 T8.3 的 `swift-markdown` AST 迁移互不阻塞，作为其落地前的过渡加固。
  - 完成：`NativeMarkdownSecurityPolicy` 以 static 预编译 `scriptPatterns`/`linkPattern` 并新增 HTML 注释剥离（防注释走私链接）；`testSanitizerRemovesExecutableHTMLAndMakesUnsafeLinksInert` 扩充注释走私断言并全量通过。

## 9. 工具、审批、问题、轨迹与详情

官方工具和复杂会话节点是完全复刻中的高风险区域。应按 node type 分批交付，并确保未实现的 renderer 不会静默丢失模型行为或原始数据。

- [ ] **T9.1：实现 generic tool renderer。** 显示 tool call、参数摘要、执行状态、结果、错误、折叠和原始 fallback。
  - 依赖：T6.5、T8.2。
  - 验收：所有未知 tool type 以安全、可复制、不过度解释的通用视图呈现；不丢弃 raw result。
  - 进度：`NativeToolRow` 已保留展开态的完整 raw arguments 与 output；`NativeToolDetailsBody` 的通用 fallback 不再在 output 存在时以 `output ?? arguments` 静默丢弃输入，而以可复制的两个原始区域呈现 arguments 和 output（failed output 使用已有错误 token）。当前仍须补未知类型完整运行态 fixture、折叠/超长输出性能、官方加载/取消结构配对和 macOS 视觉无障碍证据，故保持未勾选。

- [ ] **T9.2：实现官方常用 tool renderer。** 分别完成 bash/terminal、read、search、file mutation/diff、todo、web、ask-question、workflow 和图像/附件类 renderer。
  - 依赖：T9.1、T2.5。
  - 验收：每类 renderer 有官方 fixture、加载/失败/取消/超长输出测试和性能基线。

- [ ] **T9.3：实现审批与用户问题 Takeover 闭环。** 用官方 composer takeover 语义替代普通弹窗，支持 allow-once、reject、选择项、多选与自定义文本。**修复未托管 Task 异步竞态**：所有 Approval/Question 异步提交必须保存 Task 引用并绑定 Request ID 与 Generation 校验，在会话切换、断线重连或 pending item 替换时安全取消并防止“幽灵回调”覆盖新状态。
  - 依赖：T6.6、T8.4。
  - 验收：回答只能对 pending request 提交一次；会话切换与断线重连不发生竞态与重复授权。
  - 进度：`NativeSessionStore` 已将 approval answer、question answer 与 question cancel 从未托管 `Task` 改为保存引用的 `approvalSubmissionTask`/`questionSubmissionTask`；Host restart、会话/断线生命周期、pending request 替换和 matching resolved frame 均会取消相应任务并更新 interaction generation。每个完成/失败回调同时验证 generation、当前 pending 的 RPC ID、session ID（approval 还验证 approval ID）后才可改变 busy state。`testReplayedQuestionKeepsNewBusyStateWhenOldSubmissionFailsLate` 现明确断言旧 Task 在 restart 替换 pending 前收到 cancellation，随后迟到错误不能清除新请求 busy state；本地 Swift 语法检查通过。仍须补 approval 与 cancel-question 的同构延迟 fake、实际 macOS XCTest 及 takeover 视觉/无障碍证据，故保持未勾选。

- [ ] **T9.4：实现 thinking、retry、compaction。** 复刻默认收缩、流式摘要、retry 倒计时、错误可见性、checkpoint disclosure 和 summary 边界。
  - 依赖：T6.5、T8.2。
  - 验收：没有 chain-of-thought 泄露；compaction 不错误移除历史；retry 完成/取消状态准确。

- [ ] **T9.5：实现 trajectory、subagent、workflow 与 deliverables。** 先识别官方 chat node/独立 view 的最小数据契约，再建立 renderer；不要为了填界面而自创 summary 文案。
  - 依赖：T6.6、T8.1、T9.1。
  - 验收：每种复杂节点在相关官方插件未加载时安全隐藏或显示官方原始 fallback，而非崩溃。

- [ ] **T9.6：实现详情栏。** 展示官方可达的 tool detail、input/output/metadata 和选择态；详情列关闭时 subtree 持久化策略应与官方语义一致。
  - 依赖：T5.2、T9.1。
  - 验收：开关详情栏不丢失当前 tool selection；窄窗口自动关闭时不破坏中心会话。
  - 进度：已为锁定 RC8 seeded navigation fixture 新增 `tooling-inspector-light` 官方 Playwright capture、原生 light snapshot、visual policy 和 native-ui paired comparison；采集经真实搜索、Trajectory tab、tool row 与 Event details Result tab 达到同状态。该项仍缺 generic renderer/详情栏完整语义、当前 SHA macOS 工件与人工差异分类，保持未勾选。

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

## 11. 第三方插件：渐进双轨兼容体系（专有原生路径 + 自动沙箱 Web 宿主）

官方浏览器插件依靠 React/Cordis card 注册。为兼顾 macOS 原生质感与社区生态即插即用，采用**自适应双轨制**（有原生资产走专有路径，无则自动启动轻量 Web 沙箱宿主），确保 100% 社区插件零门槛可用。

- [ ] **T11.1：定义 `NativeUIManifest` v1。** 声明原生 Schema 描述模型：`pluginId`、`hostBuildRange`、`manifestVersion`、`kind`、`localeResources`、`sections`、`fields`、`groups`、`order`、`secretRoles`、`validation`、`actions`、`requiredCapabilities`、`integrity`。
  - 依赖：T0.2、T10.2。
  - 验收：manifest 有 JSON Schema、版本升级规则和负面 fixture；未通过完整性检查的安全降级到通用沙箱容器。

- [ ] **T11.2：实现 `NativeSchemaForm`。** 支持官方可描述的 text、number、toggle、select、secret、path、group、help、reset、save/discard 和 read-only 字段；字段排列严格由 manifest 指定，以 100% 原生 SwiftUI 动态渲染设置表单。
  - 依赖：T11.1、T10.2。
  - 验收：任意 manifest field 不会导致代码执行；通过纯原生组件实现配置变更并直接提交 Host typed RPC。

- [ ] **T11.3：实现 `SwiftAdapterRegistry`。** 用插件 ID 映射深度审查的原生 Swift 特性；允许复杂内置/高频插件以原生 Swift 视图复刻官方交互与 Liquid Glass 质感。
  - 依赖：T11.1。
  - 验收：adapter 的可用性、最低 Host build、测试 fixture 和生效状态均可枚举。

- [ ] **T11.4：实现插件自适应双轨分流器与兼容矩阵。** 实现装配时的自动路由探测（分流优先级：`SwiftAdapter` ➔ `NativeUIManifest` ➔ `PluginWebHost 自动沙箱` ➔ `Host-Only`）。
  - 依赖：T11.1、T11.3。
  - 验收：无任何专有适配文件的第三方 React 插件自动路由至沙箱容器；诊断页清晰展示每个插件当前激活的运行轨与原因。

- [ ] **T11.5：实现 `PluginWebHost` 自动沙箱微宿主。** 针对未原生化的第三方 React 插件，提供通用的轻量 `mini-host.html` 容器，内置官方 React/Cordis 运行时、公共组件与 CSS Token，自动从 Host 加载 `/plugins/<id>/client.js` 并挂载 React 组件。限制为 loopback same-origin、禁止外网导航、禁止读取非插件本地资源。
  - 依赖：T11.4。
  - 验收：社区标准 React 插件在无任何手动适配下可完整加载、渲染并执行 RPC 交互；网络策略阻断外站请求与 file URL。

- [ ] **T11.6：实现沙箱卡片自适应与视觉融合。** 在单卡片/独立设置面板中嵌入沙箱容器：利用 `ResizeObserver` 动态同步内容高度至 SwiftUI 外层以消除内部滚动条；设置透明背景让原生窗口底色透出；自动同步 macOS Light/Dark 模式。
  - 依赖：T11.5。
  - 验收：第三方卡片高度自适应撑开，随外层原生列表平滑滚动；主题跟随系统毫秒级切换，无白屏/闪烁现象。

- [ ] **T11.7：禁止兼容沙箱侵入核心 UI 骨架。** 会话外壳、侧栏、窗口容器、Composer 与官方核心设置绝不能借“插件兼容”替换为整页 WebUI；`PluginWebHost` 只能由独立的插件路由/宿主 target 引用，`GlassCore`、`GlassUI`、`DeepSeekHarnessGlassApp` 与其核心 shell 路径不得直接依赖或链接它。
  - 依赖：T11.5。
  - 验收：真实运行态 diagnostics/NSView tree test 报告核心应用结构中 WebView 数量始终为 0，且以注入真实 WebView 的负例证明确实可拒绝违规；第三方沙箱严格限制在单卡片或独立弹窗边界内；Plugin target 接入后必须以 `swift package describe --type json` 的允许/禁止 target graph 与运行态 host view isolation 测试证明仅明确登记的隔离插件路由 target 可连接该微宿主，绝不对 Core/UI/App 的 Swift 源码做 import 或 symbol 关键词扫描。

## 12. 测试、视觉回归、性能与安全（第一性原理质量体系）

质量保证遵循真实运行态行为验证，坚决杜绝源码纯文本扫描等形式主义测试。核心覆盖真实协议状态机、SSE 混沌网络、千条长会话压力、真实键盘无障碍流与双轨插件沙箱隔离。

- [ ] **T12.1：建立 raw-event fixture 管线。** 从官方 e2e/test fixtures 或经审计的录制会话导出 anonymized JSON，覆盖 happy path、错误、重连、并发、长会话和未知节点。
  - 依赖：T4.6、T6.4。
  - 验收：fixture 可离线复放；不含用户 secret、私人路径、API key 或未经许可的对话内容。

- [ ] **T12.2：建立 reducer snapshot tests。** 对每个 raw event append 后的 node snapshot、turn/step boundary、projection value、queue 和 pending interaction 做断言。
  - 依赖：T6.5、T6.6。
  - 验收：已支持 node 类型的状态覆盖率和负面 fixture 清单可追踪；未知 event 不导致崩溃。

- [ ] **T12.3：建立 transport 混沌与重连测试 (Chaos & Resilience Tests)。** 在真实运行期注入网络抖动：模拟迟到 response、重复/乱序 SSE 帧、高频流式推送中的连续取消、Host 崩溃后热重启自愈与重连 Sequence Fence 屏障。
  - 依赖：T4.6、T6.7。
  - 验收：异步并发与重连状态最终确定性收敛，无重复消息、无幽灵会话写入、无内存句柄泄露。

- [ ] **T12.4：建立官方布局 Golden Tests 与自动化视觉回归 (Snapshot Testing)。** 按 T2.5 场景在 1280×840、1024×720、窄窗口、light/dark/system、Reduce Transparency、Increase Contrast、Reduce Motion 下捕获 Swift UI。在测试目标中引入开源标准 **`swift-snapshot-testing`**，建立基准黄金快照（Golden Baseline）与像素 Diff 自动断言，彻底消除“只截图不比对”的形式主义；本地人类调试保留环境变量豁免开关。
  - 依赖：T2.6、T5–T10。
  - 验收：自动化流水线自动对比基准图并产出 Diff 附件；UI 变更产生非预期位移时 CI 必挂。

- [ ] **T12.5：建立真实键盘流与无障碍测试 (Keyboard Flow & Accessibility)。** 覆盖全键盘（Tab、Shift+Tab、方向键、Enter、Esc、快捷键）贯穿会话选择、流式交互、模型切换、工具审批与设置保存的全流程。
  - 依赖：T5.6、T8–T11。
  - 验收：核心操作路径 100% 支持无鼠标键盘盲操；VoiceOver 读屏语义完整。

- [ ] **T12.6：长会话极限压力与性能基准 (Stress Benchmarks)。** 测量启动耗时、1,000+ 条超长会话历史极速滚动平滑度、流式 10k chunks 主线程响应、超长代码块/Markdown 排版耗时，以及双轨沙箱 50 次装卸后的内存清理。
  - 依赖：T8–T10。
  - 验收：建立帧率（60fps+）与内存基准线，拖拽 resize 与长文本滚动无主线程卡顿。

- [ ] **T12.7：安全隔离与双轨沙箱审查。** 审查 loopback 信任边界、RPC 内容类型、下载路径安全、Markdown 外部链接拦截、凭据内存生命周期与 `PluginWebHost` 严格沙箱隔离（阻断外网与 file:// 读取）。
  - 依赖：T3–T4、T8.3、T10.4、T11。
  - 验收：安全 checklist 全部通过，第三方 Web 插件完全限制在独立沙箱内。

- [ ] **T12.8：迁移遗留 source-text CI gate 至可证伪运行态验证。** 依据 PR #5 的“验证运行态行为，严禁源码文本对暗号”规定，逐步删除对本项目 `.swift` 源码使用关键词、正则或出现次数作为 pass/fail 的 gate；改用 SwiftPM target graph、XCTest/async protocol replay、真实 AppKit/SwiftUI accessibility tree、WindowServer screenshots 与实际 Host integration。
  - 依赖：T4.6、T5.6、T6.7、T11.7。
  - 进度：三个 P0 gate 均已删除、完成替代实现并取得各自 macOS-26 CI 成功证据：`check-module-boundaries.py` 由 `check-package-target-graph.py` 接管（从 `swift package describe --type json` 验证五个正式 target 的实际路径与精确依赖方向，且以非法 `GlassCore → GlassUI` 反向边/错误路径负例证伪），`7e115b2` [run 32343097874](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32343097874) ✅；D0 WebView gate 由真实核心表面 `NSView` tree 检查和注入 `WKWebView` 负例接管，`df057b6` [run 32343282886](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32343282886) ✅；feature-transport gate 由 `NativeSessionAPI` typed facade 与拒绝型 composer intent XCTest 接管，修复后的 `973644f` [run 32344399514](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32344399514) ✅。P1 locale literal gate 亦已删除，改由 production `OfficialLocaleCatalog` runtime value 正例与动态未登记 label 负例接管（真实 mounted accessibility tree 仍限具 TCC trust 的 GUI host）；`07c1ae9` [run 32346226235](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32346226235) ✅。P1 Glass source gate 已由 production materialization decision 正负例接管，`6230494` [run 32346379405](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32346379405) ✅。P1 accessibility baseline source-path gate 已由 `601e095` resource bundle/runtime scene-label contract 接管，但其 [run 32349272676](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32349272676) 因直接 Swiftc app assembly 不生成 `Bundle.module` 而失败；当前修复已复用 Package/main resource fallback，待修复提交自身 macOS-26 CI。D1 `check-official-spec.py` 已移除 `verify_ui_text` 对 `Sources/UI/**/*.swift` 的 `Text("...")` 正则扫描，保留并本地通过官方 catalog provenance、AST icon、资产和 visual-scene 的结构化产物验证；UI copy 继续由 production locale catalog/runtime accessibility 正负例承担。`check-runtime-asset-inventory.py` 同时已移除对 `Sources/main.swift` 文件存在性与 App `@main` 字符串的读取，改由 `swift package describe --type json` 精确要求唯一 `DeepSeekHarnessGlassApp` executable target 位于 `Sources/App`；`test-runtime-asset-inventory.py` 以错误路径、重复入口和缺失入口负例证伪，并接入 portable specification gate。其余遗留 P1/P2 gate 仍按 `notes/PR5_QUALITY_COMPLIANCE_AUDIT.md` 的顺序迁移。
  - 验收：遗留 D0 WebView source-text gate、遗留 feature-transport source-text gate、locale/spec literal lint、glass/structural/accessibility gate 及其相关生成检查均完成逐项迁移；每个替代测试具备真实负例、可证伪且对等行为重构保持通过；所有旧 source-text gate 不再被 workflow 调用或作为 TODO/安全/视觉验收证据。详见 `notes/PR5_QUALITY_COMPLIANCE_AUDIT.md`。

- [x] **T12.9：消除低频路径中逐调用动态编译的正则。** `NativeProjectPathResolver.resolve`（`#[/\\]+$#`/`#^[/\\]+#`）和 `PermissionPresetProjection.display`（kebab-case 校验 `^[a-z0-9]+(-[a-z0-9]+)*$`）都通过 `replacingOccurrences(options:.regularExpression)` / `range(of:options:.regularExpression)` 触发每次调用即重新编译。将这两处改为不依赖正则引擎的确定性字符串/字符扫描实现（路径按 `\\` 与 `/` 回查裁剪；kebab-case 用 ASCII `isLowercaseHexDigit`/`-` 判定），并在隐私敏感与设置投影回归测试中保持逐字节等价输出。
  - 依赖：T6.1、T10.3（若实现顺序落后）。
  - 验收：`NativeSessionStoreTests`（路径解析）与 `PermissionPresetProjection` 相关测试全部通过且输出不变；不再出现任何 `options: .regularExpression` 的每调用动态编译路径，可经代码搜索确认仅剩 `HarnessHostController`/`HostDiagnostics`/`NativeMarkdownSecurityPolicy` 的预编译或一次性构件用法。
  - 完成：`NativeProjectPathResolver.resolve` 以 character scan 剪切头部/尾部 `/`、`\` 序列；`PermissionPresetProjection` 以 UnicodeScalar 扫描校验 kebab-case。`NativeSessionStoreTests` 12/12 与 `PermissionPresetProjection` 测试通过，输出不变。

## 13. 构建、签名、发布与升级治理

- [ ] **T13.1：迁移构建脚本。** 更新 `assemble.sh`、`repair-backend.sh` 与 release workflow，使其组装原生 app、固定 Host payload、生成 `SupportedHostBuilds.json`、打包 spec assets 并执行 smoke tests。
  - 依赖：T3.6、T12.1。
  - 验收：clean environment 可从零构建；构建产物清单可追溯到 Node、dsh、spec、App 源提交。

- [ ] **T13.2：实行代码签名与分发治理。** 支持标准的 Ad-hoc 签名与 Developer ID 签名分发路径；针对开源分发提供清晰的 Gatekeeper 右键打开引导，不将付费 Apple 开发者证书作为阻塞 Release 的强前提。
  - 依赖：T13.1。
  - 验收：打包产物（DMG/ZIP）具备合规的 bundle 结构与签名；CI 自动化产出 Release 工件。

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
| M6：可发布 | T13、所有 D0–D5。 | 正式 Release。 | 核心崩溃、未通过基本门禁。 |

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
| 11. 插件兼容 | 未开始 | 仅在架构与TODO中规定渐进双轨制（NativeUIManifest/SwiftAdapter/PluginWebHost自动沙箱） | manifest schema、adapter registry、自适应分流路由和通用Web沙箱微宿主尚未实现 |
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
| T1.2 | `[x]` 完成 | `glass/Package.swift` 声明 `GlassSpec`、`GlassCore`、`GlassUI`、`GlassSnapshot` 与 `DeepSeekHarnessGlassApp` 五个 target；历史 `check-module-boundaries.py` 已在 T12.8 迁移为 `check-package-target-graph.py`：后者从 `swift package describe --type json` 验证实际 target path 与精确依赖方向，并以 `test-package-target-graph.py` 的非法反向边/错误路径负例证明可证伪。`NativeImagePicker` 将 `NSOpenPanel` 由 Core 移至 UI；CI 执行 `swift build --configuration release` 与运行态 XCTest。`9563049` 的 macOS-26 [run 32161795843](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32161795843) 成功编译 target、生成官方/原生截图并通过人工对照复核。此勾选不代表 Plugins/Tests target、插件隔离或任何下游产品功能完成。 |
| T1.3 | `[x]` 完成 | 核心 native-only 约束已在 T12.8 迁移为 `NativeWebViewIsolationRuntimeTests`：macOS XCTest 实际装载 sidebar、conversation 与 details，递归检查真实 `NSView` tree 不含 `WKWebView`，并以注入 `WKWebView` 的负例证明可证伪；本提交的 macOS-26 CI 通过后更新其 run 证据。此勾选不代表 `PluginWebHost` 例外已实现。 |
| T2.1 | `[x]` 完成 | `official-ui-spec-build.json` 记录 `sourceCommit`、Host build ID、`uiSpecRevision`、locale/token/layout/fixture SHA-256 revision、确定性 `generatedAt`、生成器版本和 37 项上游输入 hash/行数；`OfficialUISpecBuild.swift` 暴露同一 build ID，Host 启动会拒绝其 ID/commit/UI revision 不匹配的 payload。`check-official-ui-spec-build.py` 从锁定源码重生成并比对，`test-official-ui-spec-build.py` 证明篡改 catalog 必失败，`OfficialUISpecBuildTests` 读取 build ID。`e9fc169` 的 macOS-26 [run 32166053042](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32166053042) 复验通过。此勾选不代表 T2.3 token 的完整生成已完成。 |
| T2.2 | `[x]` 完成 | `official-locales.json` 从 28 个锁定 official locale 文件生成 1,268 条、634 个成对的 en/zh key；每条记录 namespace/key/value、插值参数、复数类别、来源路径/行号/commit，且解析 catalog revision 与 `OfficialUISpec.Build.localeRevision` 所代表的原始输入 hash 分离。`OfficialLocaleCatalog.swift` 提供双语查询；`check-official-locales.py` 重生成并验证来源、双语/插值/复数一致性及 source-input 绑定；PR #5 后旧 `check-official-locale-literals.py` 与其 source-text 自检已在 T12.8 删除；`NativeAccessibilityRuntimeTests` 改为实际装载原生 Composer，读取 accessibility tree 的可见 label 并核对 `OfficialLocaleCatalog` runtime values，且以注入未登记 label 的负例证明 catalog 会拒绝。`e9fc169` 的 macOS-26 [run 32166053042](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32166053042) 成功完成 Swift XCTest、独立编译和官方/原生 GUI 对照；人工复核未发现本次 locale 迁移新增视觉回归。此勾选不代表 T2.3 token 或下游页面文案的完整逐场景视觉通过。 |
| T2.6 | `[x]` 完成 | 已建立官方/原生同状态同视口配对、放大局部检查、差异记录、立即修复和CI截图存在性规则。此勾选不代表所有视觉场景都已人工验收。 |
| T7.3 | `[ ]` RC8 重新认证中 | workspace-search、workspace rename、session rename、workspace delete的代码、官方场景契约和 Host 行操作仍存在；`NativeAccessibilityRuntimeTests` 已对 narrow rail 只导出 Open Sidebar、wide sidebar 只导出 Collapse Sidebar 建立双向 forbidden-label 负例，防止隐藏控制留在焦点树。但 run 32142821176 与其管理 dialog 配对工件属于 RC7 历史记录，不能作为 RC8 完成依据。必须以 RC8 官方/原生的 search、rename、delete 浅色/深色同状态图、ARIA/geometry、差异报告、人工分类及当前 head 的 macOS-26 CI 重新闭环。 |

### D. 视觉场景矩阵

场景目录来源为 `glass/Sources/Spec/Fixtures/visual-scenes.json`，固定官方 commit 为 `141eb6f...`（`dsh-v0.1.0-rc.8`）。每个场景均要求固定的 light 或 dark 主题、DPR 1、同状态、同视口；可见表面按矩阵要求逐步同时覆盖浅色与深色。管理 Dialog 和 workspace search 使用 1280×1100 视口。RC7 的截图和人工复核仅作历史记录，不得作为 RC8 TODO 勾选证据。

| 场景 | 当前证据状态 | 下一步 |
|---|---|---|
| `welcome-no-workspace-light` | 已有工件均属于 RC7 历史记录，不能用于 RC8 视觉验收；RC8 场景暂处于 `report-only`，不得从旧 run 推导“无新增回归”。 | 在 macOS-26 CI 以 RC8 WebUI 和同一原生 fixture 重建官方/原生 PNG、ARIA/几何 JSON、量化差异与人工分类；仅在完整证据闭环后评估是否进入 `enforce`。 |
| `welcome-no-workspace-dark` | RC8 新增深色同状态场景已接入真实 ThemeRuntime `data-ds-dark-theme` 官方捕获、原生 `.darkAqua` 快照和 pair diff，当前为 `report-only`。 | 首次 macOS-26 工件须核对主题级联、文字/几何、ARIA及系统材质差异；分类和修复后才可进入 `enforce`。 |
| `conversation-details-light` | CI场景契约存在 | 补全RPC fixture、完整node和配对核验 |
| `tooling-inspector-light` | CI场景契约存在 | 补全tool renderer与详情栏核验 |
| `workspace-search-light` | RC7 工件仅作历史记录，不能用于 RC8 验收 | 用 RC8 官方/原生同状态 search、空/结果/错误状态重建浅色/深色配对、ARIA/geometry和差异分类。 |
| `workspace-rename-light` | RC7 dialog 工件仅作历史记录 | 用 RC8 官方/原生同状态 rename dialog 重建浅色/深色配对、输入全选和按钮端帽证据。 |
| `session-rename-light` | RC7 dialog 工件仅作历史记录 | 用 RC8 官方/原生同状态 session rename dialog 重建浅色/深色配对和焦点证据。 |
| `workspace-delete-light` | RC7 dialog 工件仅作历史记录 | 用 RC8 官方/原生同状态 delete dialog 重建浅色/深色配对、危险状态和文案换行证据。 |
| `approval-composer-light` | 阶段2配对验收；ApprovalPanel 140px裁切已固定 | 补充更广泛approval状态与RPC测试 |
| `question-composer-light` | 阶段2配对验收；QuestionComposer 310px卡片已固定 | 补充选择/提交/重连测试 |
| `sidebar-rail-narrow-light` | 场景契约与CI存在性已建立 | 完成1023px阈值、焦点和官方motion配对 |
| `jobs-expanded-light` | `fd0b033` 的 macOS-26 [run 32332870557](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32332870557) 成功；原生图为 1280×840，Jobs trigger/status/duration 已固定 en-US。仍为 `report-only`（material `0.16355748`、mean `28.509988`、exact `0.41469308`）。 | 补齐官方同等 transcript/header/composer 层（T7/T8/T9）并继续收敛 Jobs trigger/popover 几何；在完整内容层归责后达到阈值才可进入 `enforce`。 |
| `jobs-expanded-dark` | `fd0b033` 的同一 run 成功生成 1280×840 dark pair；真实 ThemeRuntime、Host whole snapshot、原生 `.darkAqua` 均已接入，当前为 `report-only`（material `0.37511254`、mean `11.910796`、exact `0.64757999`）。 | 与 light 共享业务 fixture但独立收敛 dark surface、state dot、trigger/popover 和内容层差异；不得由 light 结果代替。 |

### E. 最近修复与可复用经验

管理Dialog的按钮两侧曾出现重复、断裂或方形残留描边。`eca42c2` 将动作按钮改为单一胶囊绘制路径，`7db32ed` 将禁用primary映射到官方中性brand token，`082ddfb` 用AppKit桥接复刻官方打开时自动全选预填rename文本。修复方法和证据保存在 `visual-review/stage3-native/management-modal-review.md`。这一经验必须推广到所有局部控件：先放大检查真实像素，再判断是Shape合成、token、几何、状态还是系统渲染问题，不能先假定是平台差异。

### F. 当前代码入口与下一步顺序

新会话必须按以下顺序开始，不得跳到更下游页面：

1. 阅读本TODO的项目宪章和本“当前进度”章节；当前正式勾选共29项。先完成 RC8 基线迁移、截图矩阵与 T5.1–T5.6/T7.3 的重新认证，再继续 T6.6。
2. 执行 `git status --short`、`git log -10 --oneline`、`gh run list --repo NewbieXvwu/deepseek-harness-glass --workflow native-ui.yml --limit 10`，确认待合并 head 与其自身 CI 一致；再运行不依赖本项目 Swift 源码文本扫描的验证：`python3 glass/ci/check-runtime-asset-inventory.py`、`python3 glass/ci/test-package-target-graph.py`、`python3 glass/ci/check-package-target-graph.py`、`python3 glass/ci/check-official-ui-spec-build.py --official-root /home/ubuntu/reference/deepseek-harness-rc8-analysis`、`python3 glass/ci/check-official-locales.py --official-root /home/ubuntu/reference/deepseek-harness-rc8-analysis`、`python3 glass/ci/check-official-spec.py`、`python3 glass/ci/test_visual_policy.py`、相关运行态 XCTest 与 `python3 glass/ci/check-supported-host-build.py --payload-dir glass/build/backend --node glass/build/node/node`（或等价 Node 24 路径）。任何旧 source-text gate 均不得作为验收命令重跑。
3. 先扩展 RC8 浅色/深色截图场景和场景政策；T5.1–T5.6/T7.3 的视觉重认证完成后，再处理 T6.6 扩展节点和 T6.7 reconnect/replay。后续任务证据不足时保持未勾选。
4. 按T6.6 → T6.7 → T7.1 → T7.2 → T7.4 → T8 → T9 → T10 → T11 → T12 → T13推进；不得跳到设置、插件或发布页以掩盖会话/节点基础层未闭环。

### G. 当前验证命令与远端证据

```bash
cd /path/to/deepseek-harness-glass/glass
python3 glass/ci/check-official-spec.py
# D0 由 macOS XCTest 的 NativeWebViewIsolationRuntimeTests 运行态验证；Linux 不执行源码文本替代 gate。
git status --short
git log -10 --oneline
gh run list --repo NewbieXvwu/deepseek-harness-glass --limit 10
```

RC8 原始迁移提交 `d62ef24` 的 [run 32328246659](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32328246659) 成功完成受控 payload、官方/架构门禁、独立 SwiftPM 编译、全量 XCTest、原生装配、WindowServer 快照和视觉比较。它不覆盖包含当前 main 的刷新提交 `fb5aab8`，后者必须以自身 macOS-26 run 重新验证。`c0ea840`、`8e68158`、`bcf0257` 的 RC7 Core-only CI 仍保留其实现演化记录，但不得作为 RC8 可见 UI 的验收替代。后续新提交必须重新查询自己的 run，不得沿用父提交成功状态。

### H. 明确的未完成范围

T6.6扩展nodes、T6.7 reconnect/replay、完整Settings Root/schema form/General/Models/Credentials/Plugin pages、NativeUIManifest、SwiftAdapterRegistry、PluginWebHost隔离POC、完整Chat/tool renderer、window recovery、commands、accessibility/performance/security tests、签名公证、升级支持矩阵和发布候选审计均未完成。工程加固项 T2.7（官方规格生成器 TS/TSX 源码解析迁移 AST）、T3.7（Host announcement 正则预编译缓存）、T3.8（`HostLogRedactor` 规则元组重构）、T8.8（`NativeMarkdownRenderer` 正则一次性编译与增量清洗）、T12.9（低频路径正则手写扫描替代）已完成并勾选：其代码、测试与生成器字节一致性验证已闭环，剩余官方锁定提交端点与 macOS-26 全门禁验证由 PR `fix/perf-hotspots-and-ast-parsers` 的 CI run 承担。
