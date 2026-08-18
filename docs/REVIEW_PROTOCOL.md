# 原生迁移审查协议

本协议落实 `D0–D5`。每个变更有唯一可写实现作者；其余审查角色只能提交只读证据、评论或阻塞结论。实现作者不得自行批准自己的来源映射、视觉对照或 Glass 使用。

| 审查角色 | 必须检查的证据 | 阻塞条件 |
|---|---|---|
| 官方规格 | `official-ui-catalog.json`、上游组件/locale/token/图标来源、场景目录。 | 可见文本、图标、顺序、尺寸、状态没有锁定官方来源。 |
| Host 协议 | DTO diff、RPC/SSE fixture、错误/取消/重连测试。 | Feature 绕过 facade，或以伪本地状态取代 Host authority。 |
| 原生架构 | 模块依赖、并发边界、生命周期测试、D0 扫描。 | `Core`/`UI` 引入 WebView、进程控制或未分层的 URL/字典解析。 |
| 视觉与无障碍 | 同条件官方/原生截图、layout rectangles、键盘、VoiceOver、对比度/透明度。 | 任何未分类偏差，或仅凭肉眼声明“接近”。 |
| Liquid Glass | `GlassPolicy`、运行态证据、Reduce Transparency 行为。 | Glass 覆盖官方正文、Hero、composer、代码或消息表面，或没有 policy。 |
| 插件与安全 | manifest/adapter、兼容矩阵、secret/URL/file/fallback 隔离测试。 | 未知插件自动 WebView，或 fallback 未经显式批准。 |
| 发布门禁 | 全部 CI 工件、支持矩阵、版本变更、签名/公证状态。 | D0–D5 任一失败、证据缺失或 Host build 未验证。 |

## 每个模块 PR 的必需证据包

1. 任务编号、官方 commit、Host build 和 UI spec revision。
2. 组件—来源映射，包含 locale key、token、图标和官方场景。
3. 行为测试：RPC/SSE fixture、reducer snapshot，以及失败/取消/重连路径。
4. 同窗口、主题、辅助功能条件下的官方与原生截图、布局矩形和偏差分类。
5. VoiceOver、键盘与 Reduce Transparency/Contrast/Motion 证据。
6. 若使用 `glassEffect`，附 `GlassPolicy`、运行态窗口截图与不侵入正文的说明。
7. D0/D1 静态门禁、编译和相关回归结果。
8. 与实现作者不同的规格审查和视觉/功能审查结论；任一为阻塞时不得合并。

## 偏差处置

偏差只能分类为 `source-missing`、`text`、`asset`、`geometry`、`state`、`system-glass` 或 `font-rendering`。前五类须修复；后两类只有在来源、几何、平台设置与辅助功能证据完整时才能被批准。禁止通过新增产品文案、系统图标或未经来源支持的装饰来掩盖偏差。
