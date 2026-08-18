# 官方/原生视觉配对记录：welcome-no-workspace-light

**官方来源：** `deepseek-ai/deepseek-harness@99f6f02fecdb7dff40c3fbc9470f5907c29f74ca`。  
**官方截图：** `reference-artifacts/official-99f6f02/welcome-no-workspace-light.png`，由官方 `apps/web` 的真实 Web composition、keyless fixture 与 Playwright 生成。  
**原生截图：** GitHub Actions `native-ui` run `32152858091` 的 `welcome-dark.png`，1280×840。  
**配对条件：** English、light、DPR 1、1280×840、无 workspace、无 session。

> 此记录仅描述当前观察到的差异，**不构成视觉验收通过**。原生截图文件名为 `welcome-dark.png`，但实际呈现为浅色内容层；后续场景目录必须修正该命名/颜色模式歧义，避免跨状态比较。

| 区域 | 官方 WebUI 观察 | 当前原生观察 | 结论与后续动作 |
|---|---|---|---|
| 侧栏外廓 | 左侧栏宽约 280 px，wordmark、New Session、Workspaces、空态与 Settings 的相对层级完整。 | 侧栏几何与官方总体接近。 | 纳入后续布局树和像素测量；不得因“接近”视作验收。 |
| Hero 标题 | 标题基线约在 y=307，位于中心内容上部。 | 标题约在 y=314，存在数像素垂直位置差。 | 需在正式 welcome 场景的布局差异报告中用 DOM/Swift 测量确认并收敛。 |
| Composer 外框 | 官方为细灰色虚线/描边，约从 x=386 延伸至 x=1165。 | 当前为蓝色虚线描边，约从 x=391 延伸至 x=1171。 | 这是可观察 token 与几何差异；须映射官方 disabled/blocked token 并在原生 renderer 修复。 |
| 提交圆形控制 | 官方禁用圆形提交控制显著为浅蓝色。 | 当前控制为中性灰色。 | 这是可观察状态 token 差异；后续必须以官方 token 修复，不可归因于 Liquid Glass。 |
| 输入与控件垂直间距 | 官方 chooser/mode 行与 composer 间距、placeholder 位置由官方 CSS 决定。 | 当前行和输入框与官方存在可见的数像素位置差。 | 建立自动几何采样和局部放大图后逐项关闭。 |

## 当前结论

官方 WebUI 已在本地从锁定源码成功构建并运行，Playwright 截图无 console warning 或 page error。原生 CI 工件也已成功下载、查看。两者已经证实并非零差异，因此后续 UI 工作必须先建立自动对齐/差异报告，随后再开始以“完成”为目标的界面实现；任何受影响 TODO 保持未勾选。
