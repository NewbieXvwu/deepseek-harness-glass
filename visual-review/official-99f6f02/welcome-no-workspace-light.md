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

## 2026-08-18 — T1.2 模块边界复核

证据：macOS-26 [run 32161795843](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32161795843) 的 `welcome-no-workspace-light-comparison.png`、官方 PNG、原生 PNG 和报告 JSON。该提交引入独立 SwiftPM target 编译、Core/UI 文件选择边界和模块依赖门禁；三栏对照未显示由这些结构改动引入的新增可观察 welcome 回归。官方与原生之间原有的全图差异仍然存在，尤其是主区域的原生材质/背景与 composer 边界；它们继续保持 `report-only`，不得因本次 CI 成功或本条复核而被视为视觉验收通过。

## 2026-08-18 — T2.2 locale catalog revision review

证据：macOS-26 [run 32166053042](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32166053042)，commit `e9fc169`，工件 `artifacts/visual-diff/welcome-no-workspace-light-comparison.png`。三栏图仍显示锁定官方 WebUI、原生 macOS welcome 状态和放大差异层。侧栏、新会话按钮、空工作区、welcome 标题、模式控制行与 composer 的结构位置与 T1.2 对照一致；T2.2 生成语言包/规格输入 hash 迁移未引入新的可观察结构性偏移或文本替换。右侧放大差异仍集中在既有系统材质、边缘抗锯齿、原生虚线/描边与 composer seat 渲染，不得将本次“无新增回归”误记为 welcome 场景已视觉通过；该场景继续保持 `report-only`，直至下游界面任务按 T0.3 关闭现存差异。

## 2026-08-19 — T2.3 official theme catalog review

证据：macOS-26 [run 32169307451](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32169307451)，commit `2fbdeb7`，工件 `artifacts/official-webui/welcome-no-workspace-light.png`、`artifacts/native-shell/welcome-dark.png`、`artifacts/visual-diff/welcome-no-workspace-light-comparison.png`、amplified diff 与报告 JSON。该 run 已成功编译全部 SwiftPM target、执行 `OfficialUISpecBuildTests`（包括 162 个生成 CSS theme token 的 source/revision/RGBA 测试）、生成原生截图并完成官方配对。

人工检查三栏对照图确认：侧栏、wordmark、New Session、Workspaces 空态、hero 标题、chooser/mode 行与 composer 的文案顺序和主要边界没有因 T2.3 将手写颜色/字体/几何替换为官方语义 token 而产生新的可观察偏移或文本替换。量化报告仍为 `report-only`：materially changed ratio `0.02957217`、mean absolute channel difference `2.829776`、exact changed ratio `0.30839937`；差异仍集中在此前已记录的原生虚线/描边、composer seat、阴影/材质与数像素几何偏差。它们不是本次 token catalog 迁移新增的差异，且本记录**不构成 welcome 场景视觉验收通过**；下游 UI 场景任务仍须逐项关闭这些差异。
