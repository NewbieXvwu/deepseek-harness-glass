# DeepSeek Harness Glass：持续完成 TODO 的执行计划

**作者：** Manus AI  
**制定日期：** 2026-08-19（GMT+8）  
**计划基线：** `deepseek-harness-glass/main@cf3e002`；官方参考为 `deepseek-ai/deepseek-harness@528c682e061696f5a160f363f236ecbf53cbd006`。

## 一、结论与当前基线

本计划以**持续工作直至 `TODO.md` 中 78 个编号任务全部达到可审计完成状态**为目标，而不是以“应用可启动”或“局部截图近似”为完成标准。当前本地工作树位于 `/home/ubuntu/work/deepseek-harness-glass`，官方参考源码位于 `/home/ubuntu/work/deepseek-harness-reference`；二者均已克隆。环境与安装事实记录于 `notes/environment-setup.md`。官方参考版本与项目锁定的 Host、协议和视觉规格版本一致，因此可以直接用于逐项追溯源码、生成 fixture 和复核 UI 行为。[1] [2] [3]

| 指标 | 当前值 | 计划含义 |
|---|---:|---|
| 已正式勾选任务 | 33 | 基础边界、规格、Host/传输、窗口/三栏以及部分会话基础已具备可复用门禁。 |
| 未完成任务 | 45 | 先处理 T6 的证据债，再依赖顺序完成会话、界面、工具、设置、插件、测试与发布。 |
| 总任务 | 78 | 所有编号任务均需要代码、官方来源、测试和适用的视觉证据闭环。 |
| 正式完成比例 | 42.3% | 此比例仅计 `TODO.md` 已勾选条目；已有代码但缺少证据的任务不得提前计入。 |
| 当前视觉策略 | `report-only` | `welcome-no-workspace-light` 尚未达到严格阈值，不能作为任何 UI TODO 的完成证据。 |

> **执行原则：** 官方 WebUI 的文本、布局、状态与交互是规格；原生 macOS 材质只能作为有边界的系统渲染例外。任何核心界面、官方设置或会话流均不得以 WebView、DOM、JavaScript 或 CSS 注入替代原生实现。[3] [4]

## 二、不可改变的工作约束

所有后续工作遵循项目已定义的 D0–D5。也就是说，业务数据始终由已验证 DeepSeek Harness Host 经类型化 loopback RPC/WebSocket 提供；SwiftUI/AppKit 仅承载原生视图与瞬态显示状态；未验证 Host 不得伪装为可写入的兼容目标；第三方插件的 WebView 只能作为单独审计后的最小化例外。[3]

| 约束 | 持续执行规则 | 验证方式 |
|---|---|---|
| 官方来源可回链 | 每个可见文本、图标、尺寸、状态和交互，在实现前登记官方文件路径、锁定提交、选择器或行区间。 | 更新 `OfficialUISpec`、源映射注释与对应 fixture。 |
| Host 为唯一真源 | 不在原生端建立冲突的会话、工作区、设置、模型、凭据或插件配置数据库。 | 仅通过 `HarnessAPIs` 域 facade；新增 DTO 与合同回归。 |
| 核心 UI 零 WebView | 会话、侧栏、工具、官方设置、模型与凭据持续禁止 WebKit。 | 每个 PR 运行 native-only 与模块边界门禁。 |
| 视觉完成可量化 | 同一 commit、fixture、locale、DPR、视口和颜色模式采集官方/原生配对；新场景先 `report-only`，收敛后才可 `enforce`。 | 官方 PNG/JSON、原生 PNG、diff、报告 JSON、人工分类记录齐全。 |
| 失败关闭 | Host、fixture、截图、认证、编译或 CI 失败时，停止下游勾选并记录事实、根因与恢复步骤。 | 在 `TODO.md` 的唯一续跑入口与视觉审阅目录同步状态。 |

## 三、持续节奏与统一交付闭环

后续不按“页面数量”推进，而按小而可回归的任务闭环推进。每一项编号任务使用一个独立主题分支或一组单一目的提交；每次变更均从官方源码阅读开始，以本地单元/契约测试、macOS 26 持续集成、官方/原生视觉配对和 TODO 证据写回结束。Linux 环境不能替代 Xcode 26/macOS 26 的真实原生渲染验证，因此 macOS 26 CI 成功及其工件审阅是 UI 任务的硬门禁。[3] [4]

| 每个任务的固定循环 | 必须产出 | 不满足时的处理 |
|---|---|---|
| 1. 锁定规格 | 官方路径、commit、行为与几何记录；必要时生成/更新 fixture。 | 不开始原生 UI 编码。 |
| 2. 建立失败测试 | DTO、reducer、交互、无障碍或视觉测试先描述所需行为。 | 测试不足时保持任务未勾选。 |
| 3. 最小原生实现 | 在 `GlassSpec → GlassCore → GlassUI → App` 的既有单向模块边界内实现。 | 发现跨层依赖时先修边界，不以快捷方式绕过。 |
| 4. 回归与安全检查 | 运行 Linux 可移植检查（逻辑/契约/规格）与 macOS 原生门禁。 | 失败关闭，修复后重新跑完整受影响集合。 |
| 5. 视觉与人工复核 | 生成同状态官方/原生工件；优先使用本地 `local-visual-test.sh`，再以 CI 为准。 | 场景保持 `report-only`，相应 UI TODO 不得勾选。 |
| 6. 证据写回 | 纯文档提交不再触发 macOS CI；更新 `TODO.md` 时必须引用步骤 4 的成功 SHA。 | 缺少任一证据即不合并、不勾选。 |

## 四、阶段 0：同步、基线复核与证据债关闭

第一阶段不扩展产品表面，而是关闭 T6.2、T6.4、T6.5 已有实现的**证据债**。当前任务清单明确指出这三项已有代码和成功 CI，但没有完整的官方来源、逐 append replay、当前 HEAD 的人工审阅或合理的 Core-only 视觉边界，因此不应继续向 T6.6 及下游 UI 扩张。[3]

| 顺序 | 任务 | 必做工作 | 完成门槛 |
|---:|---|---|---|
| 0.1 | 基线重放 | 记录 `git status`、当前 commit、固定 Host/spec revision；运行仓库列出的规格、模块、原生 WebView 禁止、视觉策略与 Host 支持矩阵门禁。 | 所有本地可运行门禁通过；无法在 Linux 运行的 macOS 验证明确转交 CI。 |
| 0.2 | T6.2 `SessionHistoryPager` | 把官方 history/tail/`beforeSeq` 来源写入任务证据；补齐/核对分页、乱序、重复、compaction、live gap 的离线 fixture；明确该任务是 Core-only，或在 ChatView 基础实现后制作同状态分页视觉配对。 | `SessionHistoryPagerTests`、来源映射、当前 revision 的 CI 与人工边界记录均完成。 |
| 0.3 | T6.4 `ConversationNode` | 对照官方 `packages/client/runtime/src/client/contract/conversation.ts`，建立逐 append 的 `match → start/update → publication → buildViewNode` replay snapshot；证明 renderer 不接触 raw wire event。 | 每个生命周期边界有官方输入、Swift snapshot、未知事件安全处理和人工复核。 |
| 0.4 | T6.5 初始核心 nodes | 为 user/context、assistant streaming/final、thinking、tool/result、retry/error、compaction 与 interrupted anchor 建立可审计逐帧 fixture；复核当前 HEAD 截图与逻辑排序。 | 当前 HEAD 的 macOS 26 run、官方/原生配对、逐 append 节点快照、人工审阅和 TODO 链接完整。 |
| 0.5 | 文档同步 | 仅在 0.2–0.4 全部闭环后勾选 T6.2/T6.4/T6.5，并更新唯一续跑入口。 | 三项均有可复现命令、工件路径、CI run、源映射和明确的视觉范围。 |

## 五、阶段 1：完成可靠的事件到会话恢复层

在阶段 0 完成后，先完成 T6.6 与 T6.7。这一阶段建立全部下游聊天、工具、审批、问题、队列、交付物和详情视图共同依赖的事件语义，避免 UI 先行而后被真实重连/补历史行为推翻。官方会话合同定义了 turn/step、节点稳定 key、target 与 publication 语义；原生 reducer 必须保持这一模型，而不是退化为无结构的消息数组。[2] [3]

| 顺序 | TODO | 实施范围 | 验收输出 |
|---:|---|---|---|
| 1.1 | T6.6 扩展 nodes | 以 node type 分批实现 todo、goal、queue/steering、approval、question、workflow、subagent、trajectory、deliverables、feedback、model/permission 与 jobs。 | 每类均有官方来源、正常/失败/取消/缺插件 fixture、Core renderer snapshot 与安全 fallback。 |
| 1.2 | T12.1 原始事件管线（提前建设） | 从官方 e2e/test fixture 或审计录制会话提取脱敏 JSON，提供离线 replay。 | fixture 无秘密、私人路径或未授权用户内容，并覆盖 happy/error/reconnect/concurrency/long/unknown。 |
| 1.3 | T12.2 reducer snapshots（提前建设） | 每次 raw event append 后记录 node、turn/step、projection、queue 与 pending interaction。 | 支持 node 类型清单与负面 fixture 可追踪；未知 event 不崩溃。 |
| 1.4 | T6.7 reconnect/replay | 实现断流、Host 重启、cold-to-live 时的 authoritative history、projection 和 session status 重放。 | 任一断点重连结果与连续执行参考快照相同。 |
| 1.5 | T12.3 transport chaos（提前建设） | 注入迟到 response、重复/乱序 frame、HTTP timeout、SSE 中断、Host restart、settings conflict 和 cancel race。 | 最终收敛，无重复消息/授权、无无限 reconnect、无错误回滚。 |

阶段 1 完成后，M2 的协议可信条件才真正具有端到端意义。此时应重新运行 Host smoke、DTO/contract gate、重连测试与全部 reducer replay；若任何 replay 差异存在，优先修复 Core，不进入复杂视图开发。[3]

## 六、阶段 2：侧栏、工作区与会话选择完整化

此阶段完成 T7.1、T7.2 与 T7.4，并重新回归已勾选的 T7.3。后者在依赖 T7.2 的前提下已具有独立搜索/行操作证据，但工作区浏览器基础完成后仍需复测，确保搜索不依赖私有索引，且 archive/ungrouped/reorder/空会话复用没有破坏现有场景。[3]

| 顺序 | TODO | 工作重点 | 必须覆盖的官方/原生状态 |
|---:|---|---|---|
| 2.1 | T7.1 静态 sidebar | Wordmark、New Session、workspace/settings seat、滚动区和固定底部区域全部由 `OfficialUISpec` 驱动。 | 无 workspace、有 workspace、焦点、禁用与 screen-reader label。 |
| 2.2 | T7.2 browser | workspace list/create/reorder、archive、ungrouped、session list、selected/running/blank 与空 session reuse。 | Host change frame 驱动的实时更新、键盘操作和恢复选择。 |
| 2.3 | T7.4 rail | wide ↔ 56 px rail、1024/1023 临界值、官方 motion 和 Reduce Motion 降级。 | 临界 viewport、手动切换、焦点不进入隐藏控件、details 自动关闭。 |
| 2.4 | 视觉收敛 | 把 `sidebar-rail-narrow-light` 从契约/存在性提升到完整配对，关闭现有 welcome 的可见 composer/几何差异。 | `enforce` 阈值、人工 ARIA/几何/高幅度 diff 分类记录。 |

## 七、阶段 3：会话主界面与 Composer 的零 WebView 闭环

阶段 3 按 T8.1 至 T8.7 的编号推进。实现参考主要来自官方 `ui-conversation` 中的 `ChatView`、节点 seat、composer submission contract 和输入状态机；不以静态 mock 替代实际 Host/RPC/SSE 回写。[2] [5]

| 顺序 | TODO | 交付边界 | 必须验收的风险点 |
|---:|---|---|---|
| 3.1 | T8.1 header/tabs | session title、chat view、view registry、header actions 与空会话过渡。 | session 切换不闪烁或重建 composer；DocumentTitle 行为一致。 |
| 3.2 | T8.2 ChatView | 用户、assistant、streaming tail、copy、时间和 turn status。 | 流式 chunk 不引起全页重排；历史与实时尾部连续。 |
| 3.3 | T8.3 Markdown/code/link | 受限 Markdown、代码高亮/copy、路径与外部 URL 策略。 | 恶意 Markdown/URL 不执行脚本、不打开任意 file URL。 |
| 3.4 | T8.4 Composer | 草稿、文本输入、send/stop、快捷键、blocked、命令/附件入口与焦点。 | idle/busy/no-workspace/blocked/subagent 等官方场景逐一配对。 |
| 3.5 | T8.5 RPC workflow | prompt/cancel/queue/steer 仅经 Host API，SSE 作为权威。 | Host 拒绝、cancel、编辑/删除、steer race 都可恢复，无永久乐观伪消息。 |
| 3.6 | T8.6 model/permission | model、reasoning、context、permission 和高风险确认。 | 无模型时的官方阻止文案；解锁、选择、确认与回写一致。 |
| 3.7 | T8.7 docks | queue/todo/goal/stats 的 projection/API 真源、顺序、折叠和无障碍。 | 多 dock 溢出、隐藏规则、滚动与 label 和官方一致。 |

每完成一个子任务，都应为对应 `official-interaction-scenes.json` 场景补齐官方 fixture、原生自动化、视觉工件和人工审阅。完整 Composer 闭环完成前，不进入复杂工具与设置页面；这是项目 M3 禁止“先堆页面、后补会话状态”的明确要求。[3] [4]

## 八、阶段 4：工具、审批、问题、轨迹与详情

工具层按由通用到专用的路径完成 T9.1 至 T9.6。所有未知 tool 首先拥有安全、可复制且不丢失 raw result 的 generic renderer，再逐步以真实官方 fixture 扩展专用 renderer；这能避免插件缺失或新工具类型导致会话信息沉默消失。[3]

| 顺序 | TODO | 实施与证据要求 |
|---:|---|---|
| 4.1 | T9.1 generic tool renderer | 参数摘要、状态、结果、错误、折叠和原始 fallback；安全 display/复制测试。 |
| 4.2 | T9.2 常用工具 | bash/terminal、read、search、file mutation/diff、todo、web、ask-question、workflow、图像/附件分别有官方 fixture、loading/error/cancel/long output 与性能用例。 |
| 4.3 | T9.3 approval/question takeover | 使用 Composer takeover 而不是私有弹窗；一次性提交、重连去重、danger/default focus 测试。 |
| 4.4 | T9.4 thinking/retry/compaction | 默认折叠、摘要、倒计时、可见性、checkpoint 与 summary 边界；保证不泄露 chain-of-thought。 |
| 4.5 | T9.5 complex nodes | trajectory/subagent/workflow/deliverables 的最小数据合同、独立视图或安全 fallback。 |
| 4.6 | T9.6 inspector | 详情栏 selection、input/output/metadata 和关闭/窄窗口下 subtree 持久化。 |

## 九、阶段 5：官方设置、凭据、模型与插件兼容

设置工作首先完成 T10.1–T10.6，随后才进入 T11.1–T11.7。官方 settings 具有 namespace、schema、revision、secret redaction 和写入合同，因此 Store、draft 与 revision fence 先于各页面；第三方插件先有 Manifest、适配器、兼容矩阵与安全隔离，才允许研究受限 Web fallback。[3] [6]

| 顺序 | TODO | 最小可发布定义 |
|---:|---|---|
| 5.1 | T10.1–T10.2 | Settings Root 和 `NativeSettingsStore`；描述缓存、dirty/invalid、discard、remote invalidation、reconnect refresh 与 revision conflict。 |
| 5.2 | T10.3–T10.4 | General、主题、Models、Credentials；secret 永不进入 UI dump、日志、截图、错误或 readback。 |
| 5.3 | T11.1–T11.3 | `NativeUIManifest` schema/完整性验证、`NativeSchemaForm` 与 `SwiftAdapterRegistry`；未知字段只报 unsupported，绝不执行代码或猜测 UI。 |
| 5.4 | T10.5–T10.6 | bash/agent-loop/web-search 原生卡片、Agent Presets 与 Plugin Inventory；所有危险动作保持官方语义与确认策略。 |
| 5.5 | T11.4 | 对每个检测插件记录支持层级、Host 范围、原生方案、fallback 许可和原因。 |
| 5.6 | T11.5–T11.7 | 仅在兼容矩阵批准后完成 `PluginWebHost` POC、single-card 可嵌入性实验和零核心 WebView 不变量。所有外站、file URL、未知 scheme、popup 与全局 session UI 必须被拒绝。 |

## 十、阶段 6：全量回归、性能、安全与发布治理

最后阶段以“所有界面已有实现”作为输入完成 T12 与 T13，而不是将测试和签名延后成不可控收尾。布局 golden、UI 自动化、性能与安全审计应在 UI 增量中持续建设；在任务清单中最终勾选前，必须统一达到可发布门 M6。[3] [4]

| 顺序 | TODO | 关键产物与验收 |
|---:|---|---|
| 6.1 | T12.4 golden tests | T2.5 覆盖场景的 1280×840、1024×720、窄窗口、light/dark/system、Reduce Transparency/Contrast/Motion 布局树、token、截图与例外说明。 |
| 6.2 | T12.5 UI tests | 无鼠标可完成的 keyboard/VoiceOver/focus/divider/composer/approval/settings/plugin paths；所有 icon-only action 有 label。 |
| 6.3 | T12.6 performance | 启动 ready、history tail、10k chunks、1k history、长工具输出、resize、rail 与 glass control 的目标上限、trace、回退审阅。 |
| 6.4 | T12.7 security | loopback、内容类型、open/download、Markdown URL、附件、manifest、凭据内存、日志 redaction 与 PluginWebHost navigation 的完整 checklist。 |
| 6.5 | T13.1 build | 干净环境构建，固定 Node/Host、`SupportedHostBuilds.json`、spec assets、smoke test 与产物溯源。 |
| 6.6 | T13.2 signing/notarization | Developer ID、Hardened Runtime、公证、stapling 与 CI 验证；缺少凭证时显式 Release blocker，绝不宣称可发布。 |
| 6.7 | T13.3–T13.4 | Host 升级 runbook 与 feature flags；每项未完成高风险表面隐藏或只读，有 owner、到期条件和删除计划。 |

## 十一、视觉验证与场景收敛计划

每个 UI 任务都不是在“出现截图”时完成。所有官方截图必须由锁定源码的真实 `apps/web` composition 与 Playwright 获取；原生截图必须来自 macOS 26 编译的应用。每个场景附件必须同时含 Official PNG/DOM-ARIA-geometry JSON、Native PNG、diff/三栏对照、机器报告和人工分类记录。[4]

| 场景状态 | 执行政策 | 可否勾选 UI TODO |
|---|---|---|
| 新增或尚未对齐 | `report-only`，仍上传所有工件；登记每一处高幅差异。 | 否。 |
| 差异修复中 | 先用官方几何/文本/状态定位，再修 token、约束、路径、焦点或状态机。 | 否。 |
| 审核候选 | 将残余仅限于已记录掩膜中的系统材质或低振幅字体抗锯齿。 | 仅可进入 `enforce` 评审。 |
| 严格验收 | `enforce` 下 `materiallyChangedRatio ≤ 0.008`、平均通道差 `≤ 1.15`、精确变化比例 `≤ 0.20`，且人工审阅已逐项分类。 | 是，前提是非视觉测试也全通过。 |

当前 `welcome-no-workspace-light` 不满足这些默认严格上限，且已记录 hero 垂直偏移、composer 描边/几何及禁用提交 token 等内容层差异。因此，阶段 2 和阶段 3 应持续以此场景作为首个严格收敛目标；无头 runner 中 system sidebar/inspector 材质无法可靠合成的例外不得扩大到 composer、文本、布局、焦点或交互差异。[3] [4]

## 十二、每次提交、PR 与跨会话交接规则

每个 PR 必须只覆盖一个紧密的 TODO 闭环或一组不可分割的合同/fixture/实现变更。PR 描述中应写明 Task ID、影响的 Host build/spec revision、官方路径、测试命令、macOS CI run、视觉场景状态、风险与回滚方案。提交后立即把事实写回 `TODO.md` 的“当前进度”章节；不能以口头总结、未提交笔记或已过期的父提交 CI 替代交接材料。[3]

| PR 类型 | 强制附件/检查 |
|---|---|
| UI | OfficialUISpec 来源、locale/token/layout 变更、同状态 golden scene、原生/官方配对和人工 diff 分类。 |
| RPC/SSE | DTO/contract diff、真实或脱敏 fixture、cancel/error/reconnect 测试与 Host smoke。 |
| 文档登记 | 不修改任何源文件。必须提供关联代码 SHA 和成功的 CI Run URL，通过 `documentation-integrity` 检查。 |
| Reducer | 逐 append replay、未知 event 安全处理、状态快照和源映射。 |
| Glass/无障碍 | policy 理由、效果预算、系统偏好降级、焦点和 accessibility label 测试。 |
| 插件 | compatibility matrix、manifest 完整性、adapter/fallback 原因、navigation/isolation tests。 |
| 发布 | 可复现构建清单、签名/公证状态、升级矩阵、已知限制和 feature-flag 到期计划。 |

## 十三、停止条件与最终完成判定

持续执行在且仅在以下条件同时满足时结束：45 项未完成 TODO 全部被其自身的完成定义支持并正式勾选；所有 D0–D5 成立；全部 required visual scene 已 `enforce` 并通过阈值及人工审阅；macOS 26 上的单元、契约、Host、UI、无障碍、性能与安全门禁全部成功；固定 Host 构建可追溯、签名公证已完成且 Release 审计无未关闭 blocker。[3] [4]

若官方 Host、协议或 WebUI 在工作期间发生升级，不直接跟随 `master`。先中止新功能交付，按 T13.3 的升级序列重新锁定官方 commit，生成和审阅 OfficialUISpec，更新 DTO/fixture，运行契约、reducer、golden、无障碍和性能门禁，并在支持矩阵提交后才恢复主线实施。这避免开发者预览版的破坏性变化被无声带入原生客户端。[2] [3]

## References

[1]: https://github.com/NewbieXvwu/deepseek-harness-glass "DeepSeek Harness Glass 目标仓库"
[2]: https://github.com/deepseek-ai/deepseek-harness/tree/528c682e061696f5a160f363f236ecbf53cbd006 "DeepSeek Harness 官方锁定源码"
[3]: https://github.com/NewbieXvwu/deepseek-harness-glass/blob/main/TODO.md "项目 TODO、依赖与验收定义"
[4]: https://github.com/NewbieXvwu/deepseek-harness-glass/blob/main/docs/VISUAL_REPLICATION_TEST_PLAN.md "官方 WebUI 严格复刻视觉测试计划"
[5]: https://github.com/deepseek-ai/deepseek-harness/tree/528c682e061696f5a160f363f236ecbf53cbd006/packages/client/ui-conversation "官方 conversation UI 源码入口"
[6]: https://github.com/deepseek-ai/deepseek-harness/tree/528c682e061696f5a160f363f236ecbf53cbd006/packages/client/ui-settings-plugins "官方插件设置机制"
