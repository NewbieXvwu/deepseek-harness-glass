# PR #2：RC8 基线迁移合并审查

## 审查结论

PR #2 的原始 head `d62ef24922f217190e1b79eeba904a727e1e1249` **不应直接合并**。它的 RC8 协议、规格生成物、受控 payload、Host 验证和 macOS 26 CI 本身均具备有效的基础证据，但其分支相对当时的 `main` 落后 19 个提交，未包含持续推进中的 T6.6 reducer、permission bridge、Jobs header/panel 与第二轮几何收敛。GitHub 标记为可合并仅说明没有文本冲突，不能替代对这些已认证主线工作和跨基线视觉证据的语义审查。

| 审查维度 | 原始 PR #2 结论 | 审计证据 |
|---|---|---|
| 目标与状态 | 合法，`main` 目标、非草稿、GitHub merge state 为 `CLEAN` | PR #2 元数据 |
| 原始 head CI | 通过，但仅覆盖 `d62ef249` | macOS 26 `native-ui` run `32328246659`，所有规格、架构、SwiftPM、XCTest、装配、快照与比较步骤成功 |
| 官方来源 | 合法 RC8 提交 `141eb6fef83422698aef7a981029e843e8161534`，受控生成物与 payload 同步更新 | `SupportedHostBuilds.json`、`official-ui-spec-build.json`、Host/transport/DTO fixtures 与锁文件 |
| Host 权威与失败关闭 | 合法 | `host.describe.home` 只在已验证 endpoint 消费；`imageLimits` 为只读 projection；planned build 保持 unverified；新增 DTO/path/limits XCTest |
| 与当前主线的历史关系 | 不适合直接合并 | merge-base `c9ae3b3`；`main` 领先 19 commits，PR 领先 7 commits；活跃 T6.6 状态路径需要带入 RC8 合并结果重新验证 |
| 旧视觉证据 | 不能作为 RC8 TODO 完成依据 | RC7 `99f6f02` 的 Jobs/欢迎页截图、差异报告及人工审阅只保留为历史记录；RC8 需要同状态新工件 |

> 原始 PR 已正确声明 RC7 视觉工件只能作为历史记录；本审查进一步要求，RC8 迁移后的分支必须携带当前主线的 T6.6 实现，并取得**更新后 head 自身**的 macOS 26 成功 run，方可合并。

## 修复策略

从 `d62ef249` 创建的 `pr2-rc8-refresh` 已合并当前 `main` 的 `f6c6447`，生成合并提交 `fb5aab8`。唯一文本冲突位于官方截图捕获脚本，并已通过三方合并保留 RC8 source metadata 与当前 Jobs 扩展捕获逻辑。合并结果带入 permission、workflow、deliverables、trajectory、Jobs 几何与 T6.6 进度记录；本地已通过模块边界、D0、D1、feature transport、locale literal、RC8 interaction scene、DTO manifest、transport contract、accessibility、runtime inventory 与 visual-policy 门禁。完整 Host payload、SwiftPM、XCTest、WindowServer 快照与差分则必须由随后推送的 macOS 26 run 验证。

## RC8 证据边界

RC8 的正式基线为 `deepseek-ai/deepseek-harness@141eb6fef83422698aef7a981029e843e8161534`（`dsh-v0.1.0-rc.8`）。旧 `99f6f02` 的 reducer研究、失败关闭记录和历史 CI 可解释代码演化，但不可单独证明 RC8 下的 UI、RPC、文本、布局或视觉验收。后续每个 T6.6 可见 renderer 修复均必须以 RC8 官方工件重新配对；`jobs-expanded-light` 在进入 `enforce` 前仍保持未完成。

## 合并前必须完成的闭环

更新后的 PR head 必须具备自身的 macOS 26 `native-ui` 成功 run，且该 run 的 head SHA 必须与待合并 SHA 完全一致。该 run 需执行受控 RC8 Host payload 验证、官方规格与架构门禁、独立 SwiftPM 编译、全量 XCTest、原生应用装配、WindowServer 快照及视觉比较。随后再复核 PR 无冲突、目标为 `main`、工作树无未提交文件，并以 GitHub 审计链接记录合并 SHA。

## References

[1]: https://github.com/NewbieXvwu/deepseek-harness-glass/pull/2 "PR #2"
[2]: https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32328246659 "PR #2 原始 head 的 macOS 26 CI"
[3]: https://github.com/deepseek-ai/deepseek-harness/tree/141eb6fef83422698aef7a981029e843e8161534 "DeepSeek Harness RC8 locked source"

## 截图矩阵失败关闭：真实视口不得被缩放或裁剪

截图矩阵提交 `a3d38ac` 的首次 macOS-26 [run 32329706938](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32329706938) 在官方 capture 阶段失败：两个主题共用的 Host workspace 导致深色 Jobs 页不再出现 `Choose workspace`。提交 `746eb6f` 隔离浏览器 context 后，仍因 Host registry 是 scaffold 级状态而失败；`721bfa0` 改为每个主题独立 scaffold/DSH_HOME。该修复又暴露 welcome 无模型场景错误加载未消费 replay 的问题，`1915fd1` 在 [run 32330510895](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32330510895) 中关闭此问题。

`32330510895` 已成功完成官方浅色/深色 capture、受控 Host、规格/架构门禁、SwiftPM、XCTest、app 装配和原生快照，但在比较步骤失败：`jobs-expanded-light` native PNG 为 **1369×840**，无法与官方 1280×840 同状态图比较；同一 run 的 `jobs-expanded-dark`、两个 welcome 图均为 1280×840。该差异是导出路径中的窗口尺寸漂移，不是系统材质例外，也不得通过缩放、裁切或跳过 light pair 绕过。

后续修复在 `SnapshotExporter` 的 SwiftUI/AppKit refresh 后重新施加 1280×840 content viewport，并在实际 WindowServer capture 前再次验证；新增 XCTest 明确拒绝 1369×840 的 post-layout drift。该提交仍必须取得其自身的 macOS-26 run，且 four-pair compare（welcome light/dark、Jobs light/dark）均完成，才可恢复 PR 合并审查。
