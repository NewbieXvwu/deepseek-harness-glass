# 原生迁移清单

本清单以 `dsh-0.1.0-rc.6-official-99f6f02` 为唯一支持基线。状态含义如下：**保留**表示可直接纳入新模块；**迁移**表示需分解后重新实现；**删除**表示不得留在主应用路径；**对照**表示仅可用于官方或旧行为核验，不得参与发布路径。

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
