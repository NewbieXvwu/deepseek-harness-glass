# RC1 官方 WebUI 运行态观察

- **来源**：`@deepseek-ai/dsh` 与 `@deepseek-ai/dsh-web-frontend` `0.1.1-rc.1`，官方标签提交 `528c682e061696f5a160f363f236ecbf53cbd006`。
- **运行方式**：隔离 `DSH_HOME`、Node `24.19.0`，本地回环 WebUI，浏览器地址 `http://127.0.0.1:3081/`。
- **首帧可见结构**：左侧为会话/工作区导航区，主区域是空会话欢迎态，包含 “Choose workspace” 控件、`Standard mode` 预设、描述输入框和 `Continue` 操作。
- **遮罩状态**：首次运行显示 “Internal Testing Notice” 模态；底层内容被灰色遮罩，模态在主区域居中，带单一 `Continue` 按钮。该状态来自官方运行时，后续审查应在关闭通知后观察常态界面。
- **审查判断**：本次 RC1 源码差异未涉及欢迎态布局或三栏几何；欢迎态仅作为基线运行健康度和非回归参考，不将首帧遮罩纳入原生壳层像素对比。

关闭首次通知并选择 “Configure later” 后，官方常态欢迎界面呈现为轻量三栏布局：左侧导航区包含 New Session、Workspaces、搜索/视图/新增工作区控件和底部 Settings；
主区居中显示 `Into the Unknown` 标题与 `Preview` 标识，下方依次是工作区选择器、`Standard mode` 预设、单行主提示输入区和提交箭头。
输入区在无工作区时以 “Choose a workspace to start” 明确禁用语义。该布局与 RC8 已有欢迎场景的结构一致；RC1 官方源码差异不包含此区域的 CSS/TSX 修改。
