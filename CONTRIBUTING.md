# Contributing to DeepSeek Harness Glass

本项目的工作目标是**可审计地完整复刻**锁定版本的 DeepSeek Harness 官方 WebUI，而不是制作外观相近的示例。任何代码、测试、文档、截图和 TODO 更新均以 [TODO.md](TODO.md) 为唯一跨会话续跑入口，并受 README 中 D0–D5 的约束。

## 1. 开始前必须确认的基线

开发前必须确认工作树干净、当前 `main` SHA、锁定官方源、支持 Host build 和最近 GitHub Actions 状态。官方基线固定为 `deepseek-ai/deepseek-harness@99f6f02fecdb7dff40c3fbc9470f5907c29f74ca`；支持 Host 记录在 `glass/Sources/Spec/SupportedHostBuilds.json`。不得以官方 `main` 的当前内容、网页截图推测或个人偏好取代固定源码规格。

```bash
git status --short
git log -10 --oneline
python3 glass/ci/check-official-spec.py
bash glass/ci/check-no-webview.sh
gh run list --repo NewbieXvwu/deepseek-harness-glass --limit 10
```

在 Linux 工作环境中，本地官方 WebUI、fixture、协议和截图可用于参考验证；macOS 原生 GUI 的权威截图与无障碍证据必须来自 `macos-26` GitHub Actions。不能运行 macOS App 的环境不得宣称完成了原生视觉验收。

## 2. D0–D5 与 WebKit 的绝对边界

D0–D5 的定义见 [README.zh.md](README.zh.md) 与 [TODO.md](TODO.md)。核心规则是：`glass/Sources/App`、`Core`、`UI`、`Features`、`Snapshot` 和内置设置/会话 renderer 不得导入 `WebKit`，也不得使用 `WKWebView`、`WKUserScript`、`evaluateJavaScript`、DOM API、CSS 注入或网页脚本。`glass/ci/check-no-webview.sh` 是阻断性门禁，任何命中即为 D0 失败。

未来若出现经审计的 web-only 第三方插件，唯一可讨论的例外是独立 `Plugins/PluginWebHost` target。该 target 必须具有明确 manifest、Host build 范围、完整性校验、loopback same-origin 导航策略和独立安全测试；主应用不得直接链接它。这个例外绝不能用于会话、侧栏、官方设置、模型、凭据或工具页面。

## 3. 官方来源到原生实现的闭环

每个任务开始时，先建立以下来源记录，然后才可写 Swift 代码。

| 记录项 | 必填内容 |
|---|---|
| 官方来源 | 固定 commit、源码文件、行号或 CSS selector、相关 locale key、token、图标和 e2e 场景。 |
| Host/协议 | RPC method、请求/响应 DTO、SSE frame、authority baseline、错误、取消与 revision 语义。 |
| UI 状态 | 初始 fixture、动作序列、窗口尺寸、DPR、语言、light/dark/system、辅助功能条件与预期布局树。 |
| 原生映射 | `OfficialUISpec` 键、Swift type/View/Reducer 文件、可访问性 label、feature flag（如有）。 |

可见字符串只能来自受控官方 locale；颜色、间距、圆角、字体和图标只能经官方 token/资产映射取得。不得为了“填满界面”自创产品文案、私有尺寸或装饰性层级。

## 4. 强制截图与视觉差异流程

所有可见 UI 任务都必须先抓官方 WebUI，再抓原生 App，且两者为**同一个可复现状态**。禁止用不同窗口尺寸、缩放、语言、色彩模式、辅助功能选项、fixture 或动作序列进行对照。

1. 在隔离 `DSH_HOME` 中启动锁定官方 WebUI 和对应 fixture。
2. 以固定 viewport/DPR 捕获官方 PNG、DOM 几何、computed token、可访问性树和控制台/网络错误。
3. 在 macOS 26 GitHub Actions 以同样像素尺寸和状态捕获原生 GUI、布局测量、accessibility tree 和应用日志。
4. 生成全图差异、布局树差异、token 差异和关键区域放大图；重点审阅按钮端帽、描边、输入边缘、分隔线、间距、字体、焦点、相对时间、mask 和可见文案。
5. 对每一处可观察差异记录原因、代码修复、修复后截图和 CI run。系统 Liquid Glass 的动态折射不使用浏览器 CSS 像素阈值判定，但其位置、尺寸、层级、对比度、系统偏好响应和可读性仍必须验收。

一个 UI 任务没有官方/原生配对和差异闭环，就不具备完成资格。

## 5. 测试门禁

| 变更类别 | 必需证据 |
|---|---|
| 官方文本、图标、token、布局 | `OfficialUISpec` 来源映射、locale/token/layout 测试和 golden 场景。 |
| RPC/SSE/DTO | Codable round-trip、真实 Host 或经审计 fixture、`rpcId`、取消、错误、冲突和重连测试。 |
| Reducer/事件 | 每次 raw event append 的 node snapshot、乱序/重复/replay/unknown event 安全处理。 |
| 原生界面 | macOS 26 UI test、键盘路径、VoiceOver label、焦点、配对截图与差异报告。 |
| Glass 或自定义控件 | `GlassPolicy` 理由、容器策略、Reduce Motion/Transparency、Increase Contrast、Light/Dark 测试。 |
| 插件 | 兼容性矩阵、manifest/adapter/fallback 原因、隔离和导航安全测试。 |
| 安全敏感内容 | fixture 去敏、日志红脱敏、secret 生命周期、URL/path/download/attachment/manifest 审计。 |

每次提交前运行适用的本地检查；每次推送后必须等待并审阅**当前 SHA** 的 `native-ui` GitHub Actions 结果。当前 SHA 的截图、差异报告或 UI test 缺失、失败或不可读取时，相关 TODO 保持未勾选。

## 6. TODO 更新纪律

TODO 条目是原子完成单元，不能批量乐观勾选。每个条目按以下顺序推进：

1. 确认依赖的条目已真实完成。
2. 完成来源映射、实现、测试和官方/原生视觉证据。
3. 在当前提交的 macOS GitHub Actions 全部适用门禁成功后，才将该条从 `- [ ]` 更新为 `- [x]`。
4. 同次更新 `TODO.md` 的“当前进度”部分：提交 SHA、CI run、视觉证据、已关闭差异、尚未完成内容和下一步命令。
5. 若任何验收条件缺失，将阻塞事实写入 TODO，保持 `[ ]`；不得用“已有基础设施”“能够构建”或“单个 fixture 通过”替代完成。

提交信息必须包含任务编号和可观察结果，例如 `feat(T10.1): render native Settings Root from official spec` 或 `fix(T7.3): use single capsule action path`。本仓库按项目授权直接推送 `main`，但直接推送不是跳过门禁的理由。

## 7. Host 升级与发布

Host payload 升级的唯一顺序是：锁定新的官方 commit → 生成和审阅 `OfficialUISpec` → 更新 DTO → 契约回归 → reducer 回归 → 官方/原生 golden → 无障碍与性能 → 更新 `SupportedHostBuilds.json` → 当前 SHA CI 成功。缺少任一证据时，新的 Host 仍为未验证，不得进入 release。

正式发布还需要 clean environment 构建、Build Manifest、Developer ID 签名、Hardened Runtime、公证和 stapling。缺少签名或公证凭证属于 release blocker，不能通过声明“用户可以绕过 Gatekeeper”消除。
