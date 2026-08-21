# RC8 `model-selector-light` 官方采集记录

| 证据项 | 值 |
|---|---|
| 官方基线 | `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534` |
| 场景 | `model-selector-light` |
| 运行条件 | 真实 RC8 Web scaffold、连接全新 workspace、1280×840、`en-US`、light、DPR 1 |
| 触发器 | `button "Select model, current DeepSeek-V4-Flash"` |
| 官方实现来源 | `packages/client/ui-model-selection/src/client/ModelSelect.tsx:67-103,219-263` |
| 采集测试 | `capture-official-welcome.e2e.ts` 的 `official model selector` 单场景 |
| 浏览器结果 | 1 passed；8 unrelated scenes skipped；`consoleWarnings=[]`；`pageErrors=[]` |
| PNG | [`model-selector-light-official.png`](model-selector-light-official.png) |
| 元数据 | [`model-selector-light-official.json`](model-selector-light-official.json) |
| PNG SHA-256 | `6a49a2e006fd56415e97bd22e1fe0c002bb97f38904ec956b39109cc24e177f0` |
| 元数据 SHA-256 | `d9bfd44c7b0c17630a0521e502c60094d32fa6d1908bd3171d707442bc52cdf2` |

> 该文件是**官方侧的可复现基线**，不是原生实现已通过视觉验收的声明。T6.6 只能在同一场景的 macOS 原生截图、差异图、报告及人工审阅均存在后勾选。

官方闭合状态展示为全宽空会话 composer：左侧为 workspace 与 mode control，随后为输入文本区；底部控制行按 Commands、Access mode、Model、disabled Send 顺序排列。模型触发器在输入栏右侧，显示 **DeepSeek-V4-Flash** 与下拉箭头。ARIA snapshot 同时固定其精确无障碍名称、邻近 `Access mode, current: Workspace Write` 控件和 disabled `Send message`，因此 native 配对审查必须检查**真实默认模型文案、闭合 trigger 的空间位置与读取顺序**，而非只比对像素。

本地采集使用与 `native-ui.yml` 相同的锁定RC8 build/Playwright流程，并在缺失Playwright Chromium后安装该锁定版本的浏览器二进制后重新运行。首次尝试未启动浏览器便因本机可执行文件缺失退出，未产生或采纳任何基线；重试后采集成功并写入本目录。原始临时输出仍位于未跟踪的 `artifacts/official-webui-local/`，本目录的PNG、JSON与本记录构成应提交的可追溯证据。

## 待配对的原生证据

| 所需输入 | 当前状态 |
|---|---|
| `DSH_GLASS_SNAPSHOT_MODE=model` 原生 light 截图 | 等待 macOS-26 `native-ui` |
| 官方与原生对比PNG、差异JSON | 等待同一权威运行生成 |
| Official/native geometry、AX和人工审阅结论 | 等待同一权威运行生成 |
| T6.6 勾选 | 明确禁止，尚未满足 |
