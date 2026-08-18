# 原生迁移清单

本清单以 `dsh-0.1.0-rc.7-official-99f6f02` 为唯一支持基线。状态含义如下：**保留**表示可直接纳入新模块；**迁移**表示需分解后重新实现；**删除**表示不得留在主应用路径；**对照**表示仅可用于官方或旧行为核验，不得参与发布路径。

| 当前资产 | 现有职责 | 决策 | 目标归属 | 迁移条件 |
|---|---|---|---|---|
| `Sources/main.swift` | AppKit 生命周期、窗口、离屏快照入口、临时欢迎页装配。 | 迁移。 | `Sources/App/`、`Sources/UI/Shell/`、`Sources/Snapshot/`。 | 拆除临时单文件职责；窗口、Host、状态和 UI 分离。 |
| `Sources/UI/Shell/NativeAppShell.swift` | 官方欢迎态试点、三栏静态骨架、有限导航 Glass。 | 迁移。 | `Sources/UI/Shell/`、`Sidebar/`、`Workspace/`、`Conversation/`、`LiquidGlass/`。 | 必须接入真实状态、来源映射、可访问性和基线截图；不得以其作为完整 UI 证据。 |
| `Sources/Spec/OfficialUISpec.swift` | 初始官方文案、色彩、尺寸与 layout 试点。 | 迁移。 | `Sources/Spec/OfficialUISpec/`、`Locales/`、`Tokens/`。 | 由生成管线替换手工常量，并记录来源、commit 和行号。 |
| `Sources/Snapshot/SnapshotExporter.swift` | 离屏原生快照导出。 | 保留并扩展。 | `Sources/Tests/Snapshot/`。 | 支持全部标准场景、主题和辅助功能组合。 |
| `assemble.sh` | Swift 编译、Node/Host 打包、资源复制、ad-hoc 签名。 | 迁移。 | `Scripts/Build` 与 release workflow。 | 生成 build manifest，纳入 Spec/支持矩阵，并支持质量门。 |
| `repair-backend.sh` | 既有后端修复辅助。 | 审计后迁移。 | `Core/Host` 或维护工具。 | 明确其对 payload、版本和用户数据的影响；无隐式下载或覆盖。 |
| `.github/workflows/native-ui.yml` | macOS 26 编译、快照、Host payload 缓存。 | 保留并扩展。 | CI 质量门。 | 增加契约、无 WebView、规格、视觉、无障碍和审查工件。 |
| `release.yml` | 发布流程。 | 迁移。 | 发布治理。 | 仅在支持矩阵、签名、公证和完整质量门通过后发布。 |
| 当前/历史 WebView 外壳 | 将本地 WebUI 装进原生窗口。 | 删除主路径；仅作对照。 | `legacy/` 或独立对照 target。 | 主应用和核心模块不得链接 WebKit。 |
| 官方 SVG 资产与提取脚本 | 上游 wordmark、FishLogo、图标资源。 | 保留。 | `assets/`、Spec 生成管线。 | 每个资源需单根 XML SVG、原始组件来源和 hash。 |

## 当前禁止清单

主应用及其 `Core`、`UI`、`Features`、内置设置模块不得引入 `WebKit`、`WKWebView`、`WKUserScript`、`evaluateJavaScript`、`MutationObserver`、网页 CSS 注入或网页 DOM 读取。未来若存在 `PluginWebHost`，也必须独立 target、显式 manifest、严格 loopback 访问策略和独立安全审查；在此之前该目录仅用于接口定义，不可被 App target 导入。

## T1.1 运行时资产台账

下表是 [`RuntimeAssetInventory.json`](../glass/Sources/Spec/RuntimeAssetInventory.json) 的人工审阅视图；JSON 是 CI 的权威输入。它审计的是**当前与可证实的历史行为**，而不是希望未来拥有的功能。历史提交 `95c3ad8` 的“3080 外部实例挂接”与当前 T0.2 单一受控 Host 边界冲突，因此明确删除；菜单栏驻留、显示、受控重启和退出则保留为原生协调器行为。

| 资产或隐式行为 | 决策 | 当前归属 | 必须保留/禁止的事实 | CI 验证 |
|---|---|---|---|---|
| `Sources/main.swift` 单体入口 | 替换 | `Sources/App/DeepSeekHarnessGlassApp.swift` | snapshot 分流必须先于正常 UI；不得再次把窗口、Host、菜单与状态塞回一个入口文件。 | legacy 文件不存在；新入口是唯一 `@main`。 |
| 1280×840 window、880×600 最小尺寸、透明 titlebar、聚焦 | 迁移 | `Sources/App/WindowCoordinator.swift` | 坐标和标题栏策略保持，关闭主窗只隐藏而不退出。 | 原生 snapshot 与 window coordinator 代码审阅。 |
| 历史 `NSStatusItem` 驻留与菜单 | 迁移 | `Sources/App/MenuBarCoordinator.swift` | 关闭窗口后仍可从菜单显示窗口、重启**内嵌** Host 或退出。 | 资产门禁检查协调器存在；后续 UI/accessibility 任务补充菜单自动化。 |
| Host 启动、状态订阅、停止和一次恢复 | 迁移 | `Sources/App/HostLifecycleCoordinator.swift` + `Sources/Core/Host/` | 仅由 app bundle 的 Node/DSH 启动；保留 `DSH_HOME`、日志、状态与 stop。 | 支持矩阵门禁、Host lifecycle 测试和 app 组装。 |
| 历史 `127.0.0.1:3080` / `__DSH_BOOT__` 探测 | 删除 | 无 | 不得把任意外部 `dsh web` 当作读写 Host；这会绕过固定 package/commit 边界。 | 资产门禁扫描所有 Swift 源码。 |
| 离屏 snapshot export | 保留并扩展 | `Sources/Snapshot/SnapshotExporter.swift` | 环境请求时只渲染目标场景，随后退出，不启动菜单栏/Host。 | native-ui 工件包含场景 PNG。 |
| 用户数据与日志 | 保留 | `Sources/Core/Host/HostRuntimeConfiguration.swift` | 使用 Application Support 的 app-scoped `DSH_HOME` 和 `logs/host.log`；禁止写入任意外部实例目录。 | Host failure 带 log path；支持矩阵与运行时测试。 |
| Node、payload、manifest、Info.plist、图标、签名 | 保留 | `assemble.sh`、payload lockfile、Spec | Node 24.19.0 与 rc.7 payload 必须精确对应锁定官方 commit；原子 staging 后 ad-hoc 签名。 | `check-supported-host-build.py`、codesign 和 artifact manifest。 |
| `repair-backend.sh` | 保留（维护工具） | `glass/repair-backend.sh` | 只重装 exact rc.7 payload；临时 `DSH_HOME` 冒烟，不覆盖用户数据。 | 脚本静态审阅；后续维护工具测试。 |
| native CI 与 release workflow | 保留并扩展 | `.github/workflows/` | native CI 是 D0/D1/support/visual 工件门；release 仅使用同一精确 payload，签名/公证仍待发布治理任务。 | macOS-26 当前提交 run。 |
| 历史 WebView/DOM/CSS 注入壳 | 删除主路径，仅官方对照可用 | App target 外部参考目录 | 任何主业务 UI、Core、UI、Features 不得链接 WebKit 或读取网页 DOM。 | D0 `check-no-webview.sh`。 |

> 资产清单不等于完成所有功能。它只保证 T1.1 的运行时意图已被显式分类、每项都有目标归属和可执行验证，之后的 T1.2–T13 必须逐项实现其产品行为与视觉证据。
