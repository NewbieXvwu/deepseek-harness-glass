# DeepSeek Harness Glass

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的**原生 macOS 客户端**。本仓库保留 DeepSeek Harness Host，并以 **Swift 6、SwiftUI 与 AppKit** 重建官方 Browser Client。

> **项目方向。** 本项目不是 CSS 改色，也不是网页外壳。锁定官方 WebUI 的文本、顺序、布局、状态迁移、错误路径和交互语义是唯一产品规格；Liquid Glass 只能增强 macOS 的导航与控制层，不能凭空创造产品内容，也不能遮掩与官方客户端的不一致。

- **English documentation:** [README.md](README.md)
- **贡献规则与验收协议：** [CONTRIBUTING.md](CONTRIBUTING.md)
- **唯一权威实施清单：** [TODO.md](TODO.md)

## 支持基线

| 项目 | 固定支持值 |
|---|---|
| 官方源码 | [`deepseek-ai/deepseek-harness@99f6f02fecdb7dff40c3fbc9470f5907c29f74ca`](https://github.com/deepseek-ai/deepseek-harness/tree/99f6f02fecdb7dff40c3fbc9470f5907c29f74ca) |
| 支持的 DSH 包 | `@deepseek-ai/dsh` 与 `@deepseek-ai/dsh-web-frontend` `0.1.0-rc.6` |
| 运行时 | 应用内置 Node `24.19.0` |
| 客户端平台 | macOS 26+、Xcode 26+、Apple Silicon、Swift 6 |
| 支持记录 | `glass/Sources/Spec/SupportedHostBuilds.json` |

应用启动时必须校验 Host build。未列入支持记录的 Host 均为**未验证**，不得被当成可写入的兼容目标；升级 Host 必须走 `TODO.md` 定义的升级门禁，不能因为某个 loopback 端口能启动就被接受。

## D0–D5：不可突破的完成规则

| 规则 | 要求 | 可验证事实 |
|---|---|---|
| **D0 — 核心业务 UI 原生化** | 会话、侧栏、工作区、官方设置、模型、凭据、工具、审批、问题、命令与插件配置全部使用原生 UI。 | 核心 target 不含 `WebKit`、`WKWebView`、网页 JavaScript、CSS 注入或 DOM 扫描；CI 执行 `glass/ci/check-no-webview.sh`。 |
| **D1 — 严格复刻官方 UI** | 官方 locale 文本、结构、间距、状态和交互场景是规格。 | 每个 SwiftUI 表面回链 `OfficialUISpec`、锁定源码位置，以及同状态官方/原生视觉证据。 |
| **D2 — Host 是唯一真源** | 持久的会话、工作区、设置、凭据、模型、命令与插件配置均归 Host 所有。 | 原生状态只使用强类型 loopback RPC/SSE DTO，不建立冲突的业务数据库。 |
| **D3 — 遵从系统的 Liquid Glass** | Glass 只用于导航、split 结构、工具栏、sheet、popover、inspector 与必要的官方操作控件。 | 内容层不被自定义玻璃覆盖；CI 覆盖辅助功能与系统外观偏好。 |
| **D4 — 插件兼容性显式分级** | 每个插件必须声明 native-manifest、Swift-adapter、web-fallback、host-only 或 unsupported 状态。 | 诊断/兼容性矩阵记录支持等级、Host 范围和任一 fallback 原因。 |
| **D5 — 仅向已验证 Host 写入** | 未验证 Host 不得伪装为兼容。 | 不支持的 build 以“未验证”状态显示，并禁止写入，除非明确的开发策略允许。 |

`WebKit` 只可能出现在未来独立编译的 `Plugins/PluginWebHost` 例外 target 中，且仅限指定、已审计、技术上无法等价原生化的第三方插件。主应用 target 与全部核心 renderer 永远不得导入或链接它。

## 架构

```text
DeepSeek Harness.app
├── App/                   应用生命周期、窗口和菜单栏协调
├── Core/
│   ├── Host/              内置 Node/DSH 生命周期和 build 校验
│   ├── Transport/         强类型 HTTP RPC、SSE、DTO、取消与调用追踪
│   ├── Session/           历史、投影、reducer 与重连权威基线
│   └── Settings/          Host-backed 草稿、revision 和凭据边界
├── Spec/                  官方 locale、token、layout、资产与 fixture 来源
├── UI/                    原生 shell、sidebar、workspace、conversation、tooling、settings
├── Plugins/               原生 manifest/adapter；仅在批准后隔离 fallback
└── Tests/                 契约、reducer、截图、无障碍与性能证据
```

客户端严格单向分层：**Host → 强类型 transport → domain facade/store/reducer → 原生 UI**。View 不得启动 Node、拼接 URL、解析无类型 JSON，也不得解释原始 SSE 业务事件。

## 视觉与交互保真协议

每一个 UI 状态都先阅读锁定官方源码，并在同一 fixture、窗口尺寸、device-pixel ratio、语言、颜色模式与辅助功能条件下捕获官方 WebUI。原生 View 再在完全相同条件下渲染。两套截图、布局/树测量、token 差异、关键区域放大图以及每个可观察差异的修复结论均须作为 CI artifact 保存。

本项目不会用全窗模糊、不同视口、不同状态或“抗锯齿差异”掩盖问题。系统材质的动态光学效果由 macOS 负责；它以层级、位置、对比度和无障碍进行验收，而非伪造浏览器 CSS 折射的逐像素复刻。

## 当前已验证状态

唯一权威进度位于 [TODO.md](TODO.md) 的**“当前进度”**章节。只有同时完成来源映射、代码实现、测试、视觉证据以及适用的 macOS GitHub Actions 证据的任务才可勾选。能编译的页面、静态 fixture 或局部 DTO 不能视为完成。

## 开发与验证

macOS 应用通过 `glass/assemble.sh` 组装。CI 运行于 `macos-26`，下载固定 Node 与 DSH payload，验证 D0 规则和官方规格来源，构建应用、生成原生 GUI 截图并上传审阅 artifacts。完整的开发要求、来源映射格式、测试门禁、截图配对和唯一允许的 TODO 更新步骤详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

修改任何面向官方的行为前，先执行适用的本地检查：

```bash
python3 glass/ci/check-official-spec.py
bash glass/ci/check-no-webview.sh
```

最终验收必须基于**当前提交**的 GitHub Actions，包括原生截图包及其官方对照记录。

## 许可证与归属

本项目是开源 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的独立客户端，与 DeepSeek 无隶属或背书关系。项目采用 [MIT](LICENSE) 许可证；捆绑组件见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
