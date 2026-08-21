# RC8 T6.6 扩展节点官方采集清单

| 证据项 | 值 |
|---|---|
| 官方基线 | `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534` |
| 采集器 | `tools/reference-capture/capture-official-welcome.e2e.ts` |
| 运行方式 | 锁定RC8 Web build、真实Playwright Chromium、真实 scaffold/replay、无原生WebView参与 |
| 结果 | 9 个场景全部通过；采集器中的每个场景均断言 `consoleWarnings=[]` 与 `pageErrors=[]` |
| 目的 | 为T6.6的原生 renderer 提供不可变的官方侧PNG与ARIA基线；**不代表**任一原生表面已经通过配对视觉验收 |

| 场景 | 官方输入 | 视口 / 颜色 | PNG SHA-256 | JSON SHA-256 | 待配对的原生表面 |
|---|---|---|---|---|---|
| Approval takeover | [PNG](approval-composer-light-official.png) · [ARIA](approval-composer-light-official.json) | 1280×1100 / light | `c091b043d3c5b8c86dd148e7a38a3d56998926dc17b337d6f91265d3861904a9` | `a395b11e2e2aee0ace6e93746a358aa0356e3395316dd3b62373646a91e75292` | `NativeApprovalTakeover` composer seat |
| Question takeover | [PNG](question-composer-light-official.png) · [ARIA](question-composer-light-official.json) | 1280×1100 / light | `67031102dde9e38d8f2a66aad1e28a360059f53d09384ebad7101cbbb73c5fed` | `9d5877b83c3a2b144a2a08c280fdfa297646c5d89e4138e0835da4cb2c9d5db3` | `NativeQuestionTakeover` composer seat |
| Jobs action | [light PNG](jobs-expanded-light-official.png) · [light ARIA](jobs-expanded-light-official.json) | 1280×840 / light | `a00238d4de9c3ee522b63859eb0d482b944dabd585934e969b2f8cbcf6607566` | `92beda5ea7483e0327e5bc60f2b5746a5cefc34dcdad42d94901d3f2d6ff7e7d` | `NativeJobsHeaderAction` / `NativeStateDot` |
| Jobs action | [dark PNG](jobs-expanded-dark-official.png) · [dark ARIA](jobs-expanded-dark-official.json) | 1280×840 / dark | `0095f5c8fbb6235e88c9afe406e9c7fc96760b58ca2856ac88fb0342d4a13ac4` | `98b5c55b4cdef1addf7273f21f31c55fc4ba841e1abbed68fd76dd84e3d7dd9c` | `NativeJobsHeaderAction` / `NativeStateDot` |
| Tooling inspector | [PNG](tooling-inspector-light-official.png) · [ARIA](tooling-inspector-light-official.json) | 1280×840 / light | `3808b6d98d5693f1ae39f993614e2d5f85314d5295f4f08a998b942f998c94e4` | `a782fb226009933c9b3f582d27daa9c8ea0890715eb529dbb432174627a34b94` | trajectory/details typed tool inspection |

## 人工官方侧观察

Approval和question是原对话中的composer takeover，**不是**通用系统弹窗。Approval使用带暖色状态线的卡片，header、理由/命令体和 `Reject → Allow once` 尾部操作均位于同一占位区。Question使用大号白色圆角卡片，保留问题header、可多选行、自定义答案、页码、Skip和disabled Submit的纵向结构。Jobs的浅/深色基线用于复核header trigger、列表层级、状态dot和紧凑操作菜单；tooling inspector基线用于复核typed tool row与details column。

## 未完成的权威验收

当前目录仅保存**官方侧**事实。每一场景仍必须由最新macOS-26 `native-ui`运行生成同状态原生PNG、ARIA、比较图和diff JSON，并由人工依据 `visual-validation-policy.json` 分类。未取得这些成对输入前，T6.6及任何相关T5/T7项目均不得勾选。
