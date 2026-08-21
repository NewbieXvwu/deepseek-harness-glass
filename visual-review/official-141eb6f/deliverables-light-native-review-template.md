# T6.6 Deliverables：原生配对审阅模板

> **状态：待当前 macOS-26 工件。** 本记录只定义审阅方法；不得在未取得同一 SHA 的原生 PNG、ARIA、diff 与 report 前标记完成。

## 配对范围

| 字段 | 固定值 |
|---|---|
| 官方规格 | `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534` |
| 官方基线 | `deliverables-light-official.png` / `deliverables-light-official.json` |
| 视口 | 780 × 900，DPR 1，en-US，light |
| 会话状态 | 十个成功 `write` 调用、closing assistant、finished turn |
| 宽度状态 | 先宽视口选中会话，再在窄视口保持 `narrow-expanded` sidebar |
| 能力事实 | 记录的 loopback `host.describe.canOpenPath=true` |
| 视觉策略 | `report-only`；必须人工分类差异 |

## 必须逐项核对的结构

| 区域 | 官方可观察契约 | 原生验收方法 |
|---|---|---|
| Shell | 780px 下保留已展开 sidebar，conversation lane 被压缩。 | PNG 比较 sidebar 宽度、session header、聊天起始 x 坐标。 |
| Tool context | 10 条完成 `Write · path` 行位于 assistant closing 文本之前。 | PNG/ARIA 核对数目、顺序、路径摘要；不得显示原始 JSON。 |
| Tool path affordance | 每条外层行名为 `Write {path}`；独立路径按钮仅名为 `{path}`。 | 原生 AX 树逐条核对；无 Host 能力的普通场景不应创建独立按钮。 |
| Closing message | `Created the site.` 与 `PRODUCED_FILES_DONE` 分段位于 tool rows 之后。 | PNG 与 AX 文本顺序核对。 |
| Produced tail | 首行显示 `Produced`、`关于我.md`、`index.html` 与 `+ 8 files`。 | PNG、AX 与动态fit宽度核对。 |
| Folder action | 第二行 `Show in folder` 仅因 recorded `canOpenPath` 事实出现。 | AX/PNG 核对；确认是独立 action，且普通无Host截图不会伪造。 |
| Produced chips | chip AX 名为 `Open {path}`，并保留 full path 作为tooltip/label参数。 | 原生 AX 树与官方 baseline 对照。 |

## 工件归档和结论

取得完成 run 后，将以下内容复制至该目录并将本模板替换为实际审阅记录：原生 PNG、原生 ARIA JSON、official/native diff PNG、comparison report JSON，以及每项差异的分类。分类只能是 **native defect**、**已记录系统材质/字体栅格化例外** 或 **无实质差异**；任何未分类差异均阻止勾选 T6.6。

若当前 run 失败，记录失败测试或编译信息、最小修复和新的 SHA；不得将失败工件作为 paired visual evidence。
