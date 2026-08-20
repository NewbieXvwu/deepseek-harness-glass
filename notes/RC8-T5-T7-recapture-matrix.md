# RC8：T5/T7 重新认证截图矩阵

本矩阵以锁定 `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534` 为唯一官方基线。它服务于 T5.1–T5.6 和 T7.3 的**重新认证**；历史 RC7 成功工件只可作回归背景，不能作为这些 TODO 的完成证据。

## 受管场景

| 场景组 | RC8 官方工件 | 原生工件 | 状态 |
|---|---|---|---|
| Welcome light/dark | `welcome-no-workspace-*` | `welcome-*.png` | report-only；等待配对审阅。 |
| Jobs light/dark | `jobs-expanded-*` | `jobs-expanded-*.png` | report-only；等待配对审阅。 |
| 1023px sidebar rail light/dark | `sidebar-rail-narrow-*` | 同名原生场景 | report-only；必须验证 rail、焦点和隐藏控件。 |
| Workspace search light/dark | `workspace-search-*` | `workspace-search-official-viewport*` | report-only；T7.3 要求键盘焦点与 ARIA 复核。 |
| Workspace/session management dialogs light/dark | `workspace-rename-*`、`session-rename-*`、`workspace-delete-*` | 对应 native viewport 场景 | report-only；T7.3 要求 dialog/focus/状态复核。 |
| Approval takeover | `approval-composer-light` | `approval-panel-official-viewport.png` | 新增官方真实 replay capture；报告待人工分类。 |
| Question takeover | `question-composer-light` | `question-composer-official-viewport.png` | 新增官方真实 replay capture；报告待人工分类。 |

## 自动化纪律

`glass/ci/test_rc8_recapture_matrix.py` 将 16 个 T5/T7 场景交叉验证到四个平面：视觉场景注册、视觉策略、官方 Playwright 采集脚本和 `native-ui` 工作流。每个场景当前均必须满足 `report-only`、`mustEnforceBeforeTodoCompletion`、人工复核条件和 RC8 commit 一致性。工作流同时强制官方 PNG/JSON 存在，并运行同状态 native/official 比较，输出 comparison、amplified diff 与 JSON report。

> `report-only` 不是验收通过。它保证证据产物不丢失，并明确禁止在缺少人工分类、配对截图与当前 head macOS 结果时勾选相关 TODO。

## 当前边界

新增 approval/question 的官方采集复用 RC8 官方 e2e 的真实 replay fixture、访问模式切换和 stable takeover selector；不注入测试专用 UI 状态。由于本地 Linux 不具备 macOS 原生截图链，当前只完成 TypeScript 语法、策略 JSON、矩阵接线和视觉比较器自测。macOS-26 产出的当前 SHA 工件仍须复核、分类并在必要时从 `report-only` 升级到 `enforce`，T5.1–T5.6 与 T7.3 才可关闭。
