# Contributing to DeepSeek Harness Glass

本项目的目标是在固定的官方基线上完整复刻 DeepSeek Harness 的官方客户端 UI，并保证每一步都可以审计和回归。所有任务以 [TODO.md](TODO.md) 为跨会话入口。

## 1. 开始前确认基线

```bash
git status --short
git log -10 --oneline
python3 glass/ci/check-official-spec.py
python3 glass/ci/test-package-target-graph.py
gh run list --repo NewbieXvwu/deepseek-harness-glass --limit 10
```

官方基线固定为 `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534`；支持的 Host 记录在 `glass/Sources/Spec/SupportedHostBuilds.json`。一切以锁定源码为准，官方仓库的当前内容和个人记忆都不算数。

在 Linux 环境中可以用本地官方 WebUI 做参考验证；macOS 原生 GUI 的权威截图与无障碍证据来自 `macos-26` GitHub Actions。

## 2. WebKit 边界

核心应用的 sidebar、conversation、details、settings 等原生表面不得在运行态 `NSView` tree 中装载 `WKWebView`，也不得以 Web/DOM/CSS 注入替代核心交互。D0 由 `NativeWebViewIsolationRuntimeTests` 在 macOS XCTest 中实际装载核心 SwiftUI 表面、递归检查其 `NSView` tree，并以注入真实 `WKWebView` 的反例证明探测器可证伪；不得以对项目 Swift 源码的关键词扫描取代该运行态证据。

第三方插件的 Web 兼容由未来独立编译的 `Plugins/PluginWebHost` target 承载，实行自适应双轨制（原生 Manifest/Adapter 优先，未适配的第三方 React 卡片自动由轻量沙箱微宿主兜底）。沙箱严格限定在单卡片或独立设置面板内，遵循 loopback same-origin 策略并由独立安全测试覆盖，严禁侵入会话、侧栏、官方设置、模型、凭据或工具页面等核心结构。

## 3. 官方来源到实现的闭环

每个任务先登记来源，再写 Swift 代码：

| 记录项 | 内容 |
|---|---|
| 官方来源 | 固定 commit、源码文件、行号或 CSS selector、相关 locale key、token、图标和 e2e 场景 |
| Host/协议 | RPC method、请求/响应 DTO、SSE frame、错误、取消与 revision 语义 |
| UI 状态 | 初始 fixture、动作序列、窗口尺寸、DPR、语言、颜色模式、辅助功能条件与预期布局树 |
| 原生映射 | `OfficialUISpec` 键、Swift type/View/Reducer 文件、可访问性 label |

可见字符串来自受控官方 locale；颜色、间距、圆角、字体和图标经官方 token/资产映射取得。

## 4. 截图与视觉差异流程

所有可见 UI 任务都要先抓官方 WebUI、再抓原生 App，两侧保持同一个可复现状态（同一窗口尺寸、缩放、语言、色彩模式、辅助功能选项、fixture 和动作序列）：

1. 在隔离 `DSH_HOME` 中启动锁定官方 WebUI 和对应 fixture。
2. 以固定 viewport/DPR 捕获官方 PNG、DOM 几何、computed token、可访问性树和控制台/网络错误。
3. 在 macOS 26 GitHub Actions 以同样像素尺寸和状态捕获原生 GUI、布局测量、accessibility tree 和应用日志。
4. 生成全图差异、布局树差异、token 差异和关键区域放大图。
5. 对每一处可观察差异记录原因、代码修复、修复后截图和 CI run。系统 Liquid Glass 的动态折射按层级、位置、对比度和系统偏好响应验收，不参与 CSS 像素阈值判定。

## 5. 测试门禁

| 变更类别 | 必需证据 |
|---|---|
| 官方文本、图标、token、布局 | `OfficialUISpec` 来源映射、locale/token/layout 测试和 golden 场景 |
| RPC/SSE/DTO | Codable round-trip、真实 Host 或经审计 fixture、`rpcId`、取消、错误、冲突和重连测试 |
| Reducer/事件 | 每次 raw event append 的 node snapshot、乱序/重复/replay/unknown event 安全处理 |
| 原生界面 | macOS 26 UI test、键盘路径、VoiceOver label、焦点、配对截图与差异报告 |
| Glass 或自定义控件 | `GlassPolicy` 理由、容器策略、Reduce Motion/Transparency、Increase Contrast、Light/Dark 测试 |
| 插件 | 兼容性矩阵、manifest/adapter/fallback 原因、隔离和导航安全测试 |
| 安全敏感内容 | fixture 去敏、日志脱敏、secret 生命周期、URL/path/download/attachment/manifest 审计 |

提交前运行适用的本地检查；推送后等待并审阅当前 SHA 的 `native-ui` GitHub Actions 结果。

测试必须真实断言。因环境缺失而静默通过的 skip、只检查输出里有没有“没问题”字样的断言，都不算证据——这类测试宁可删除，也不要留着制造绿色假象。

## 6. TODO 更新纪律

TODO 条目是原子完成单元：

1. 确认依赖的条目已完成。
2. 完成来源映射、实现、测试和官方/原生视觉证据。
3. 当前提交的 macOS GitHub Actions 全部适用门禁成功后，才把条目从 `- [ ]` 改为 `- [x]`。
4. 同次更新 TODO.md 的“当前进度”：提交 SHA、CI run、视觉证据、已关闭差异、剩余工作和下一步。
5. 验收条件缺失时，把阻塞事实写进 TODO，保持未勾选。

提交信息包含任务编号和可观察结果，例如 `feat(T10.1): render native Settings Root from official spec`。

## 7. Host 升级与发布

Host payload 升级顺序：锁定新官方 commit → 生成和审阅 `OfficialUISpec` → 更新 DTO → 契约回归 → reducer 回归 → 官方/原生 golden → 无障碍与性能 → 更新 `SupportedHostBuilds.json` → 当前 SHA CI 成功。

正式发布还需要 clean environment 构建、Build Manifest、Developer ID 签名、Hardened Runtime、公证和 stapling。
