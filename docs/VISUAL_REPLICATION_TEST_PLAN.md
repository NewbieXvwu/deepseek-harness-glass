# 官方 WebUI 严格复刻视觉测试计划

本计划定义 DeepSeek Harness Glass 对锁定官方 WebUI `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534` 的**可判定复刻标准**。它将产品行为拆为必须严格相同的文本、布局、状态和交互，以及必须使用系统原生 API 但不伪造 CSS 光学细节的材质渲染两类。官方 WebUI 的布局参数、Host 协议和原生 Liquid Glass 边界来自锁定源码与 Apple 文档。[1] [2] [3] [4]

> **核心规则：** 生成截图、拥有低差异值或通过 report-only CI 绝不等于视觉验收。只有场景在 `visual-validation-policy.json` 变为 `enforce`、所有阈值通过，并附上本计划要求的人工分类记录后，相关 UI TODO 才能勾选。

## 1. 证据链与不可变性

每一次可验收场景必须以同一官方 commit、同一 locale、同一颜色模式、同一 DPR、同一逻辑视口和同一业务 fixture 生成五类证据。官方截图必须由官方 `apps/web` 的真实 composition 和 Playwright 获取；不允许以手写 HTML、模拟页面或旧截图代替。原生截图必须由 `macos-26` GitHub Actions 中编译的 app 获取。CI 会上传官方截图、官方 DOM/ARIA/几何 JSON、原生截图、放大差异图、三栏对照图、量化报告和工具链元数据。

| 证据 | 生成者 | 作用 | 任何缺失时的结论 |
|---|---|---|---|
| Official PNG + JSON | 锁定官方源码的 Playwright 场景 | 锁定真实文本、可访问性树、视口和布局结果 | 场景不可比较，相关 TODO 不可勾选。 |
| Native PNG | macOS-26 原生 app | 锁定 SwiftUI/AppKit 的可观察输出 | 场景不可比较，相关 TODO 不可勾选。 |
| Diff PNG + 对照图 | `compare_visual_pair.py` | 将像素差异定位为可审阅区域 | 不允许只靠“看起来接近”通过。 |
| Report JSON | 同一比较器 | 写入尺寸、变化比例、平均差异、政策、阈值判定与人工审阅要求 | 没有机器可读结果即不具备审计性。 |
| 人工分类记录 | 评审 Markdown/issue，链接上述工件 | 将每项残留差异归为缺陷或明确的系统渲染例外 | 严格场景即使指标通过，也不能作为 TODO 完成证据。 |

## 2. 判定层级

下表不是优先级建议，而是验收边界。**严格项**存在差异即为产品缺陷；**系统渲染项**不能用 CSS 假造，但仍必须检查 API 层级、可读性、辅助功能和状态响应。

| 层级 | 必须严格对照的内容 | 允许的系统原生差异 | 验证方式 |
|---|---|---|---|
| 文本 | 所有可见文字、locale、顺序、折行、截断、placeholder、数值格式、禁用/错误文案和 accessible label | 仅字形抗锯齿；不得改变字距、基线、换行、内容或语义标签 | 官方 DOM/ARIA JSON、OCR/文本断言、放大截图。 |
| 布局 | 视口、三栏/rail 让步、列宽、最小尺寸、锚点、间距、圆角、裁切、滚动位置、popover/dialog 位置与焦点 | 字形 rasterization 造成的低振幅边缘像素 | 官方几何 JSON、Swift 测量、截图 diff 和聚焦审阅。 |
| 状态 | loading、empty、disabled、hover、focus、selection、approval、question、error、reconnect、dirty 和 destructive state | 无 | 固定 Host fixture + 定向交互驱动 + 状态截图。 |
| 交互 | 键盘顺序、快捷键、点击目标、sheet/popover 打开关闭、Escape、确认/取消、输入选中、持久化和 RPC 回写 | 原生菜单/系统目录选取器外框 | Playwright/原生 UI 自动化、accessibility tree、Host contract assertion。 |
| 系统材质 | SplitView、Toolbar、Sheet、Popover、侧栏、语义按钮与系统 glass 层级 | Liquid Glass 折射、动态模糊、系统阴影与色彩采样可随 macOS/硬件变化 | 检查 SwiftUI/AppKit API、层级、Reduce Transparency/Increase Contrast 响应、文本对比度和焦点环；不得用网页 CSS 仿制。 |

Apple 的迁移指南建议优先采用系统导航和标准控件，以便自动获得正确的系统材质与可访问性行为；自定义 glass 仅用于没有系统等价物的区域。[3] [4]

## 3. 机器阈值与场景状态机

政策文件为 [`glass/Sources/Spec/Fixtures/visual-validation-policy.json`](../glass/Sources/Spec/Fixtures/visual-validation-policy.json)。它将每个场景置为以下一种状态：

| 政策模式 | CI 行为 | 可否作为 TODO 完成证据 |
|---|---|---|
| `report-only` | 始终生成工件和报告；即使存在差异也不因该场景中断本次 CI。 | **否。** 必须先分类、修复差异，将场景改为 `enforce`。 |
| `enforce` | 报告以下任一指标超过阈值时以非零状态失败。 | 仅当指标通过、所有严格项的人工复核完成且证据链接写入 TODO 时可以。 |

目前通用材料差异像素阈值为单通道绝对差 `> 12`。已进入 `enforce` 的场景默认执行如下严格上限；任何新场景须在政策文件中显式写入其阈值，不能继承为“默认通过”。

| 指标 | 默认严格上限 | 目的 |
|---|---:|---|
| `materiallyChangedRatio` | `0.008` | 捕捉布局、状态色、边界、文本位置与显著 token 差异。 |
| `meanAbsoluteChannelDifference` | `1.15` | 捕捉全图系统性偏色、背景/材质层级和几何漂移。 |
| `exactChangedRatio` | `0.20` | 容忍原生字形抗锯齿等低振幅变化，但仍限制大面积细节漂移。 |

CI 自检 `glass/ci/test_visual_policy.py` 会在合成的同尺寸图片上证明：相同图片在 `enforce` 下通过，而一个单像素高幅度差异在零阈值策略下被拒绝。因此阈值不是仅写在文档里的建议。

## 4. 场景覆盖与人工审阅

所有场景都来自 `visual-scenes.json`，并应在 light、DPR 1、同一语言和同一 fixture 下完成。管理 dialog 和 workspace search 使用 1280×1100；welcome 目前使用 1280×840。每个场景至少包含一个默认、一个有焦点、一个禁用/异常或忙碌状态；涉及键盘的场景必须记录 focus order。

| 场景族 | 最低覆盖 | 强制人工关注点 |
|---|---|---|
| Welcome / composer | no workspace、workspace chosen、disabled submit、focus、permission/model dropdown | 输入框边界、placeholder、提交状态、顶部 mode 行、键盘焦点。 |
| 三栏 / sidebar | regular、rail、1023px breakpoint、details open/closed、窗口恢复 | 官方列宽让步顺序、标题/rail 可访问名称、resize/reveal 行为。 |
| Conversation | text/markdown、streaming、error/reconnect、cancel/steer、long transcript | 节点次序、滚动锚定、选中、token/progress、action 状态。 |
| Tooling / approval / question | collapsed/expanded、pending、approve/reject、multi-choice、submit | 风险文案、默认焦点、危险操作、Escape、状态回写。 |
| Workspace/session management | search、rename、delete、archive/fork、keyboard-only | 输入自动选择、button capsule、destructive token、空态与确认流程。 |
| Settings / plugins | root、general、models、credentials、plugin inventory、dirty/discard/error | sidebar rail、panel 结构、secret 显示策略、schema validation、focus return。 |

人工评审按以下顺序执行：先确认官方 JSON 的文本和 ARIA 树；再对照几何/布局锚点；随后检查放大差异图中的每个高幅度区域；最后仅将有明确系统 API 理由的残余写入例外。**“macOS 看起来不一样”“SwiftUI 自然如此”“系统材质不可避免”均不是有效例外。**

## 5. 当前 welcome 状态

`welcome-no-workspace-light` 的 RC7 配对工件位于 [`visual-review/official-99f6f02/welcome-no-workspace-light.md`](../visual-review/official-99f6f02/welcome-no-workspace-light.md)，仅作为历史偏差分类记录，**不得**作为 RC8 验收证据。RC8 升级后，该场景及所有受影响场景均保持 `report-only`，直到 macOS-26 CI 使用锁定 RC8 WebUI 与同一原生状态重新生成官方 PNG/JSON、原生 PNG、差异报告与人工分类。未经这一完整配对流程，任何旧指标、截图或 review 均不可改为 `enforce`。

## References

[1] [DeepSeek Harness locked RC8 official source](https://github.com/deepseek-ai/deepseek-harness/tree/141eb6fef83422698aef7a981029e843e8161534)
[2] [Official RC8 layout column policy](https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/client/ui-layout/src/client/columns.ts)
[3] [Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
[4] [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
