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

## 2026-08-19 — T2.4 official three-column fixture review

证据：macOS-26 [run 32171801347](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32171801347)，commit `4f6c7e5`，工件中的官方 PNG、`welcome-dark.png`、三栏 comparison、amplified diff 与报告 JSON。该 run 成功执行直接调用锁定 `computeColumns` 的 30 个 fixture gate、SwiftPM resource 编译、逐 fixture `OfficialColumnLayout` XCTest、直接 Swiftc app 装配、原生截图和官方配对。

人工检查并排图确认：该提交只增加算法 fixture、bundle 加载与资源复制，不修改 renderer；侧栏、hero、chooser/mode 行、composer、文案及可见三栏边界均与前一成功对照保持相同。报告的 materially changed ratio 为 `0.02959635`、mean absolute channel difference 为 `2.812569`、exact changed ratio 为 `0.30891369`；相对前一 run 的极小像素波动没有对应的结构或 token 变更，属于同一截图/光栅管线的 report-only 波动。原有 composer 描边、材质和几何差异仍未关闭，且本记录**不构成 welcome 场景视觉验收通过**。

## 2026-08-19 — T2.5 official interaction scene directory review

证据：macOS-26 [run 32173433660](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32173433660)，commit `09afcc5`，工件中的锁定官方 PNG、原生 PNG、comparison、amplified diff 与报告 JSON。该 run 成功校验 `official-interaction-scenes.json` 的 13 个必覆盖场景均具备实际官方 e2e 来源、Host fixture/seed、视口、颜色与辅助功能状态、动作序列、文本、布局树、ARIA baseline 和 PNG baseline contract；随后完成完整 SwiftPM 编译、app 组装与现有 screenshot pairing。

人工复核 comparison 确认：本提交只增加版本化场景目录和来源 gate，不修改 SwiftUI renderer；既有 welcome 结构和已登记 report-only 差异保持不变。当前指标为 materially changed ratio `0.02959449`、mean absolute channel difference `2.814778`、exact changed ratio `0.30825986`，没有对应的 renderer、asset、文案或布局变更。T2.5 已完成“目录覆盖与可复现 capture contract”验收；目录中的每个下游 renderer 场景仍须在其所属 UI TODO 完成时使用同状态官方/原生 PNG 和差异报告关闭，不能把本条目录验收误作这些界面的像素验收。

## 2026-08-19 — T3.1 Host lifecycle review

证据：macOS-26 [run 32175400591](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32175400591)，commit `229d0d9`。该 run 的 `HarnessHostControllerTests.testOwnedHostStartsReusesAndStopsWithoutLeavingProcess` 在 arm64e macOS runner 上以真实固定 rc.7 Node/payload 通过（3.488 秒）：验证 Host 启动、官方 `dsh web: http://127.0.0.1:<port>` announcement、`host.describe` ready、重复 start 复用同一 PID、stop 后 PID 消失、DSH_HOME 和日志落盘。完整 SwiftPM target 编译、直接 Swiftc app 装配、原生 snapshot 与官方 capture 亦成功。

人工检查 comparison 确认 T3.1 只涉及 Core Host 进程监督、无 UI XCTest 和 CI 注入，不改变 native renderer；侧栏、hero、composer、文本顺序和主要可见边界没有新增变化。报告为既有 `report-only`：materially changed ratio `0.02923084`、mean absolute channel difference `2.737691`、exact changed ratio `0.30920666`。这些波动没有关联的 UI diff，且不构成 welcome 场景视觉完成；已有材质、composer 描边和几何差异继续由后续界面 TODO 关闭。

## 2026-08-19 — T3.2 Host build trust review

证据：macOS-26 [run 32178347783](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32178347783)，commit `ae35887`。该 run 在真实固定 payload 上通过两项无 UI `HarnessHostControllerTests`：已验证 rc.7 build 的启动/ready/reuse/stop（2.788 秒），以及人为不匹配 catalog 时 manifest/package metadata 返回 `unverified`、控制器不启动为 ready、默认仅准许 `host.describe` 而拒绝 `session.prompt`、开发者 override 才启用写入（0.002 秒）。所有 SwiftPM target 编译、Swiftc app 组装、snapshot 和官方 capture 均成功。

人工检查 comparison 确认 T3.2 只更改 Core build verification state、显式 connection build metadata 和 transport access policy；没有 renderer、文案、asset 或布局变化。量化报告继续是既有 `report-only`：materially changed ratio `0.02958705`、mean absolute channel difference `2.787254`、exact changed ratio `0.30924386`。该条不是 welcome 像素完成声明；既有材质、composer 边缘和几何差异仍须由后续 UI TODO 同状态收敛。

## 2026-08-19 — T3.3 lifecycle-state review

证据：macOS-26 [run 32180108638](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32180108638)，commit `363b534`。`HarnessHostControllerTests` 在真实固定 rc.7 payload 上执行 3 项无 UI 测试并全通过（3.519 秒）：verified Host start/reuse/stop、unknown build write protection、以及 `idle → startingOwned → verifying → ready → stopping → idle` transition ledger/日志与官方 locale `Loading…`、`Failed to load`、`Retry` presentation。实现同时加入 explicit `probingExternal`，其 diagnostics-only `host.describe` 成功也保留 `unverified`，不能由 endpoint 是否存在推断 ready 或取得写权限。

人工 comparison 检查确认本项仅改动生命周期模型、Core 日志与文案 projection；无 renderer、资产、布局或产品可见文案替换。量化报告仍为既有 `report-only`：materially changed ratio `0.02955357`、mean absolute channel difference `2.761307`、exact changed ratio `0.30867467`。这不构成 welcome 完成，既有材质、composer 与几何差异仍由后续 UI TODO 同状态关闭。

## 2026-08-19 — T3.4 diagnostics review

证据：macOS-26 [run 32181832902](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32181832902)，commit `e93273a`。`HarnessHostControllerTests` 在真实固定 payload 路径执行 4 项无 UI 测试并全通过（4.392 秒）。新增测试断言可复制 `HostDiagnosticSnapshot` 含 Host build、port、DSH_HOME、ownership/PID、last SSE time、last RPC error、protocol fixture revision、plugin compatibility 与 lifecycle；fixture 注入 API key、cookie、Bearer、URL user-info/secret 后，copy text 不含任一原文 secret，保留 `<redacted>`。RPC facade、Core readiness/probe 和 Host SSE consumer 现共用 actor-isolated recorder，保存的仅是错误摘要，不含 request/response payload。

人工 comparison 检查确认 T3.4 只改变 Core diagnostics 和事件/API 注入；原生 renderer、文案、资产、布局保持不变。量化报告仍为既有 `report-only`：materially changed ratio `0.02942987`、mean absolute channel difference `2.743943`、exact changed ratio `0.30950521`。该结论不把 welcome 标为视觉完成；既有材质、composer 与几何差异继续由后续 UI TODO 对照关闭。

## 2026-08-19 — T4.1 RPC envelope/error-model review

证据：macOS-26 [run 32183487572](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32183487572)，commit `a3d86a3`。新增 `RPCModelsTests` 经 Xcode 编译；`RPCEnvelope` 保留 request/response `rpcId` 和 closed business-error branch，`RPCBusinessError` 与 `DSHTransportError` 分类覆盖 retryable、requires refresh、requires user correction、unsupported 和 program fault。URLSession 亦将 timeout、cancelled 与网络失败映射为显式 transport 状态。现有真实 Host Core test 继续成功，完整 native app 组装、snapshot 和官方 capture 完成。

人工 comparison 检查确认此项只修改 Core HTTP/RPC model 和错误映射；原生 renderer、文案、资产与布局未改。量化报告仍为既有 `report-only`：materially changed ratio `0.02958705`、mean absolute channel difference `2.789118`、exact changed ratio `0.30974888`。该结论不将 welcome 标为视觉完成；既有材质、composer 与几何差异仍由后续界面 TODO 收敛。

## 2026-08-19 — T4.2 official RPC DTO fixture review

证据：macOS-26 [run 32186518136](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32186518136)，commit `944bee3`，工件中的锁定官方 PNG、`welcome-dark.png`、`welcome-no-workspace-light-comparison.png`、放大差异层与报告 JSON。该 run 已通过固定 commit 的 16-method RPC DTO source-manifest SHA gate、完整 SwiftPM target 编译、`RPCDTOFixtureTests`、真实 Host lifecycle tests、直接 Swiftc app 组装、原生 snapshot 与官方 WebUI capture。`RPCDTOFixtureTests` 从 GlassCore resource 加载隔离 rc.7 Host 的 16 个 request/response capture，逐个验证 ClientRequest/ServerResponse envelope canonical Codable round-trip、每个 facade payload 的 production DTO round-trip、成功 response value DTO 和 closed business-error DTO；direct app resource copy 与 SwiftPM `Bundle.module` resource load 均已覆盖。

人工检查成功工件的三栏对照确认：本项仅改变 Core transport DTO、fixture resource、schema provenance gate 与测试，未修改 SwiftUI renderer、官方 locale 文案、资产、窗口布局或主题 token。侧栏、wordmark、New Session、Workspaces 空态、hero、chooser/mode 行与 composer 的可见结构与先前对照一致。报告继续是既有 `report-only`：materially changed ratio `0.02945871`、mean absolute channel difference `2.746264`、exact changed ratio `0.30927176`；差异仍集中在已登记的原生材质/背景、composer 描边、提交控制与数像素几何偏移，并非 T4.2 新增。此复核**不构成 welcome 场景视觉验收通过**；该 UI 场景仍由后续 SwiftUI renderer TODO 依据同状态官方/原生配对逐项关闭。

## 2026-08-19 — T4.3 concurrent transport review

证据：macOS-26 [run 32189390817](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32189390817)，commit `1555ddb`，工件中的锁定官方 PNG、`welcome-dark.png`、`welcome-no-workspace-light-comparison.png`、放大差异层与报告 JSON。该 run 完整执行固定 Host/规格门禁、SwiftPM target 编译、官方 RPC DTO fixture tests、Host lifecycle tests、`DSHClientTransportTests`、直接 Swiftc app 组装、原生 snapshot 与官方 capture。新增 transport test 使用独立 URLProtocol carrier 对 100 个并发 `host.describe` RPC 回显实际 official ServerResponse envelope，断言全部 rpcId 唯一、payload index 无串线、100 条成功 trace；同时以重复 id generator 验证第二个 in-flight request 不抵达 carrier，并以错误 response id 验证 caller 永不收到串线 response。trace 只保留 method、rpcId、结果与脱敏类别，不记录 payload。

人工检查成功工件的三栏对照确认：本项仅改变 Core URLSession carrier、rpcId allocation/trace、Core tests 和 workflow test path；未修改 SwiftUI renderer、官方 locale 文案、资产、窗口几何或主题 token。侧栏、wordmark、New Session、Workspaces 空态、hero、chooser/mode 行和 composer 的可见结构与前一成功对照一致。报告仍为既有 `report-only`：materially changed ratio `0.0295917`、mean absolute channel difference `2.817961`、exact changed ratio `0.3083324`；差异继续属于已登记的原生材质/背景、composer 描边、提交控制与数像素几何偏移，未发现 T4.3 引入的新视觉差异。此复核**不构成 welcome 场景视觉验收通过**；相关 UI TODO 仍需用同状态官方/原生配对逐项关闭上述 renderer 差异。

## 2026-08-19 — T4.4 reconnecting SSE review

证据：macOS-26 [run 32191536807](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32191536807)，commit `f8e0835`，工件中的锁定官方 PNG、`welcome-dark.png`、`welcome-no-workspace-light-comparison.png`、放大差异层与报告 JSON。该 run 通过完整 source/asset/module/native-only/DTO 门禁、SwiftPM/Swiftc 编译、Host lifecycle/RPC DTO/concurrent transport/录制 SSE XCTest、app 组装、snapshot 与官方 capture。新增 `SSEClientTests` 覆盖官方 `data:` framing 对 `: connected`、malformed JSON 和非 `server-request` envelope 的跳过，录制断流后按确定性指数退避重开 mux stream，跨 reconnect 的 rpcId、`session/event` seq 和 `session/projection` seq replay fence，以及最终取消停止 retry loop。`NativeSessionStore` 与 `NativeWorkspaceStore` 已实际改用 reconnecting mux/host stream，保留既有 Host lifecycle endpoint replacement 和 reducer/session history 幂等边界。

人工检查成功工件的三栏对照确认：本项仅更改 Core SSE carrier、session/workspace data consumer、Core tests 和 CI；未修改 SwiftUI renderer、官方 locale 文案、资产、窗口几何或主题 token。侧栏、wordmark、New Session、Workspaces 空态、hero、chooser/mode 行和 composer 的可见结构与前一成功对照一致。报告仍为既有 `report-only`：materially changed ratio `0.02900205`、mean absolute channel difference `2.904255`、exact changed ratio `0.30610026`；差异继续属于已登记的原生材质/背景、composer 描边、提交控制与数像素几何偏移，不存在可归因于 T4.4 的新视觉变更。此复核**不构成 welcome 场景视觉验收通过**；相应 UI TODO 仍需使用同状态官方/原生配对关闭 renderer 差异。

## 2026-08-19 — T4.5 API domain facade review

证据：macOS-26 [run 32193851213](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32193851213)，commit `a589305`，工件 `native-ui-a58930519ab72da3c447d7f67956fcaf3c6b1131`（SHA-256 `c2cdd8052c9eaa13d984b49039c1136f544f312421a012b79378488810cc5040`）中的官方 PNG、`welcome-dark.png`、`welcome-no-workspace-light-comparison.png`、放大差异层与报告 JSON。该 run 通过固定规格/asset/module/native-only/DTO provenance 与新增 Feature facade boundary gate、全部 SwiftPM/Swiftc 编译、Host/RPC DTO/并发 transport/SSE XCTest、app 组装、snapshot 及官方 capture。

人工检查成功工件的三栏 contact sheet 确认：本项将 UI 与 session projection 对 `DSHAPIClient`、URLRequest、RPC envelope 和 JSONValue wire construction 的直接依赖迁移至 `HarnessAPIs` 下的命名 domain facades；没有改变 SwiftUI renderer、官方 locale 文案、资产、窗口几何或主题 token。侧栏、wordmark、New Session、Workspaces 空态、hero、chooser/mode 行与 composer 的可见结构均与 T4.4 对照保持一致。报告继续是既有 `report-only`：materially changed ratio `0.02955822`、mean absolute channel difference `2.762044`、exact changed ratio `0.30897507`；差异仍集中于已登记的原生材质/背景、composer 描边、提交控制与数像素几何偏移，未发现可归因于 T4.5 的新增视觉回归。此复核**不构成 welcome 场景视觉验收通过**；相关 UI TODO 仍需用同状态官方/原生配对逐项关闭 renderer 差异。

## 2026-08-19 — T4.6 transport contract regression review

证据：macOS-26 [run 32206487624](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32206487624)，commit `8a3aba6`，工件中的锁定官方 PNG、`welcome-dark.png`、`welcome-no-workspace-light-comparison.png`、amplified diff、报告 JSON、`official-transport-contract-manifest.json` 和 `official-transport-contract-fixtures.json`。该 run 通过 12-contract official schema baseline/diff gate、完整 SwiftPM/Swiftc 编译、`TransportContractRegressionTests`、Host/RPC DTO/concurrent transport/SSE tests、app 组装、snapshot 和官方 capture。

人工检查三栏对照确认：本项仅新增 session.history/prompt/cancel/models、settings.describe/mutate、credentials.set、llm.providers、SSE event/projection/host frame 与 RPC settings-conflict 的 schema-bound transport contract 回归；没有修改 SwiftUI renderer、官方 locale 文案、资产、窗口布局或主题 token。侧栏、wordmark、New Session、Workspaces 空态、hero、chooser/mode 行和 composer 的可见结构与前一成功对照一致。报告继续是既有 `report-only`：materially changed ratio `0.0295917`、mean absolute channel difference `2.817961`、exact changed ratio `0.3083324`；差异仍归于已登记的原生材质/背景、composer 描边、提交控制与数像素几何偏移，未发现可归因于 T4.6 的新增视觉回归。此复核**不构成 welcome 场景视觉验收通过**；下游 UI TODO 仍须同状态官方/原生配对关闭 renderer 差异。

## 2026-08-19 — T3.5 native download/export review

证据：macOS-26 [run 32208063025](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32208063025)，commit `0d57ee4`，工件中的锁定官方 PNG、`welcome-dark.png`、`welcome-no-workspace-light-comparison.png`、amplified diff 与报告 JSON。该 run 通过 source/asset/module/native-only/DTO/transport-contract gates、SwiftPM/Swiftc 编译、`SessionLogExporterTests`、其他 Core regression tests、app 组装、snapshot 与官方 capture。`SessionLogExporterTests` 以 URLProtocol 验证官方 host-only GET attachment、Content-Disposition 安全名称、同名 ` (2)` 冲突处理、预返回 staging 保留、404 映射以及 unverified Host 不可生成文件物化 URL。

人工检查三栏对照确认：本项仅新增 URLSessionDownloadTask 本地 ZIP 落盘、UI 层 `NSWorkspace` opener 与 trust gating；未修改 SwiftUI renderer、官方 locale 文案、资产、窗口几何或主题 token。侧栏、wordmark、New Session、Workspaces 空态、hero、chooser/mode 行与 composer 的可见结构与前一成功对照一致。报告仍是既有 `report-only`：materially changed ratio `0.02945871`、mean absolute channel difference `2.746265`、exact changed ratio `0.30927176`；差异仍属于已登记的原生材质/背景、composer 描边、提交控制和数像素几何偏移，未发现可归因于 T3.5 的新增视觉回归。此复核**不构成 welcome 场景视觉验收通过**；后续 UI TODO 仍须使用同状态官方/原生配对关闭 renderer 差异。

T3.5 cancellation addendum：macOS-26 [run 32208551395](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32208551395)，commit `cad9cea`，在原有 export 证据基础上新增挂起 URLProtocol request 的 task cancellation regression，并在实际 runner 中确认其映射为 `DSHTransportError.cancelled`。本次成功工件的 contact sheet 已人工查看；新增测试不改 renderer，三栏结构、文本和控件状态保持一致。报告继续为 `report-only`（material ratio `0.02835286`、mean absolute channel difference `2.726433`、exact ratio `0.30792783`），不构成 welcome 视觉完成。

## 2026-08-19 — T4.4 WebSocket carrier 与 T3.6 Host/transport smoke review

证据：macOS-26 [run 32211858885](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32211858885)，commit `b12be6e`，工件中的锁定官方 PNG、`welcome-dark.png`、`welcome-no-workspace-light-comparison.png`、amplified diff 与报告 JSON。该 run 通过全部 source/asset/module/native-only/DTO/transport-contract gates、SwiftPM/Swiftc 编译、现有 Host/RPC/transport/SSE/contract/export regressions，以及新增 `HarnessHostTransportSmokeTests`：固定 rc.7 Host verified ready 与 `host.describe`、`session.create`→`session.list`、真实 mux WebSocket `session/subscribed`、主动 SIGTERM 后 lifecycle `recovering`→新 endpoint verified ready、只读 `session.models` cold-resume 后的新 mux subscribed、真实 network taxonomy/diagnostics 与注入 503 retryable taxonomy。该 smoke step 与 Host lifecycle command-line tests 共用固定 Node/payload 环境，并在 workflow 中独立执行。

人工检查三栏 contact sheet 确认：本项将 `/api/events.mux` 和 `/api/events.host` 从错误的普通 HTTP SSE GET 改为固定 rc.7 Host 实际注册的 `URLSessionWebSocketTask` downlink；只改 Core carrier、Host recovery 的 typed facade handoff 与测试，未修改 SwiftUI renderer、官方 locale 文案、资产、窗口几何或主题 token。侧栏、wordmark、New Session、Workspaces 空态、hero、chooser/mode 行和 composer 与先前成功对照一致。报告继续为 `report-only`：materially changed ratio `0.02959263`、mean absolute channel difference `2.816593`、exact changed ratio `0.30847005`；剩余差异仍属于已登记的原生材质/背景、composer 描边、提交控制和数像素几何偏移，未发现可归因于 T4.4/T3.6 的新增视觉回归。此复核**不构成 welcome 场景视觉验收通过**；后续 UI TODO 仍须使用同状态官方/原生配对关闭 renderer 差异。

## 2026-08-19 — T5.1 native WindowCoordinator review

证据：macOS-26 [run 32215096026](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32215096026)，commit `126cd24`，工件中的锁定官方 PNG、`welcome-dark.png`、`welcome-no-workspace-light-comparison.png`、amplified diff 与报告 JSON。该 run 通过全部 source/asset/module/native-only/DTO/transport-contract gates、SwiftPM/Swiftc 编译、真实 rc.7 Host/transport smoke、`WindowCoordinatorTests`、其余 Core regressions、app 组装、snapshot 与官方 capture。窗口协调器保留 1280×840 初始 content size、880×600 minimum content size、`.fullSizeContentView`、标准 `.unifiedCompact` 原生标题栏、`NSWindow` autosave/restoration identifier；red-close 保存 frame 后 `orderOut`，menu-bar/Dock reopen 会 deminiaturize、makeKeyAndOrderFront 并复用唯一 shell。测试在无 WindowServer 的 XCTest host 中验证相同策略值、stable native restoration key及 visible→hidden/minimized→visible lifecycle，而真实 AppKit delegate 映射 `windowDidMiniaturize`、`windowDidDeminiaturize` 与 `windowShouldClose`。

人工检查三栏 contact sheet 确认：本项只更改 AppKit window lifecycle、Dock reopen 和 policy tests；没有改动 SwiftUI renderer、官方 locale 文案、资产、三栏几何或主题 token。侧栏、wordmark、New Session、Workspaces 空态、hero、chooser/mode 行和 composer 均与前一成功对照一致。报告继续为 `report-only`：materially changed ratio `0.02953683`、mean absolute channel difference `2.757835`、exact changed ratio `0.30945033`；现有差异继续归属原生材质/背景、composer 描边、提交控制和数像素几何，未发现可归因于 T5.1 的新增 renderer 回归。此复核**不构成 welcome 场景视觉验收通过**；T5.2 及后续 UI TODO 仍须使用同状态官方/原生配对关闭 renderer 差异。

## 2026-08-19 — T5.2 native AppKit split-container review

证据：macOS-26 [run 32216703475](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32216703475)，commit `304da29`，工件中的锁定官方 PNG、`welcome-dark.png`、`welcome-no-workspace-light-comparison.png`、amplified diff 与报告 JSON。该 run 通过全部 source/asset/module/native-only/DTO/transport-contract gates、SwiftPM/Swiftc、真实 rc.7 Host/transport smoke、所有 `GlassAppTests`、其余 Core regressions、app 组装、snapshot和官方 capture。生产 `NativeShellRootController` 保持 `NSSplitViewController` 为完整 AppKit view-controller tree，sidebar/conversation/details 只承载 SwiftUI列内容；`NativeSplitLayoutPolicy` 是 production divider constraint 与 regression 的共用政策。它使用锁定 `OfficialColumnLayout`，保证 1280px 基线 `280/640/360`，sidebar 264–420 clamp、manual/automatic collapse 的 56px rail、details 300–520 clamp，且在无法同时满足 sidebar + 640px center minimum 时折叠 details。拖动后的 constrained width 写回 presentation preferences，因此刷新和窗口重布局不会抹去用户调整。

人工检查三栏 contact sheet 确认：本项仅增加官方三栏 constraint policy、divider preference 回写及回归测试；没有改动 SwiftUI renderer、官方 locale 文案、资产或主题 token。侧栏、wordmark、New Session、Workspaces 空态、hero、chooser/mode行与 composer 均保持此前可见结构。报告仍为 `report-only`：materially changed ratio `0.02958519`、mean absolute channel difference `2.786226`、exact changed ratio `0.30927641`；未发现可归因于 T5.2 的新增 renderer 回归，既有材质/背景、composer描边、提交控制和数像素几何差异仍须由下游视觉 TODO 关闭。此复核**不构成 welcome 场景视觉验收通过**。

## 2026-08-19 — T5.3 system sidebar/inspector material review

证据：macOS-26 [run 32224425678](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32224425678)，commit `a5f1efb222f0f51e7d66ef4857b10468397f8181`，工件 `native-ui-a5f1efb222f0f51e7d66ef4857b10468397f8181` 中的官方 PNG、`welcome-light.png`、`welcome-no-workspace-light-comparison.png`、amplified diff 和报告 JSON。该 run 通过全部静态、native-only、module、feature-facade、RPC/transport-contract、**native structural material** gates、SwiftPM target 编译、真实 rc.7 Host/transport smoke、`GlassAppTests`、`SnapshotExporterTests`、其余Core regressions、应用装配、原生快照和官方配对。结构门禁要求 `NSSplitViewItem(sidebarWithViewController:)` 和 `NSSplitViewItem(inspectorWithViewController:)`，禁止侧栏/inspector使用 `NSVisualEffectView`、固定 structural token 背景或自绘canvas；生产列内容保持透明，以便系统决定其导航材质。

人工检查三栏对照确认：原生 welcome 内容、文字顺序、三栏主要锚点、wordmark、New Session、Workspaces 空态、hero、chooser/mode 行和 composer 均可见并可复核。系统 sidebar/inspector 位置在无头 runner 的截图中仍为黑色；量化报告为 `report-only`，materially changed ratio `0.03563988`、mean absolute channel difference `5.988779`、exact changed ratio `0.50732887`。为排除导出器缺陷，提交序列 `8ecacf8`、`509ff4d`、`c63d50f`、`1872703`、`4ebf634` 与本提交依次验证了 macOS 26 受支持的 `SCScreenshotManager` rect/current-process-window 路径、alpha-first black-frame rejection 和系统 `screencapture -l` 单窗口路径：该无头 WindowServer 对这些路径要么返回无错误的黑SDR帧，要么拒绝产生可用合成图。导出器会拒绝该帧并以确定性AppKit位图保存布局证据，避免将全黑图作为视觉结果。

结论：黑色仅限于 GitHub 无头 WindowServer 无法快照的**系统拥有材质区域**，已被明确分类为 T0.3/T2.6 允许的系统渲染例外；它不能放宽任何内容层、控件、文案、几何、字体、无障碍或其它视觉差异。实际生产树使用原生 AppKit sidebar/inspector，而非固定色/手工模糊伪造，且没有壁纸亮度采样逻辑。故本次复核可作为 **T5.3 的系统API、层级与可读内容证据**，但不将 welcome 全场景标记为像素视觉完成；后续界面TODO仍须关闭composer、token和几何等独立差异。

## 2026-08-19 — T5.4 explicit Liquid Glass policy review

证据：macOS-26 [run 32225877836](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32225877836)，commit `7ebaefdddef1c00b75f8bd22f611323a35abdf52`，工件 `native-ui-7ebaefdddef1c00b75f8bd22f611323a35abdf52` 中的官方 PNG、`welcome-light.png`、comparison、amplified diff 与报告 JSON。该 run 通过全部既有静态/module/transport/material gates，并新增通过 `check-glass-policy.py`；SwiftPM、真实rc.7 Host smoke、`GlassAppTests`（含 `GlassPolicyTests`）、`SnapshotExporterTests`、其余回归、应用装配、原生截图和官方配对均成功。

人工检查对照确认：GlassPolicy将内容层、系统导航、regular custom control 与预留media overlay显式分开，且把原有 `NativeGlassNavigationButtonStyle` 的唯一 `glassEffect` 迁移为具名的 `.regularGlassCustomControl`。静态门禁拒绝任何未通过 `approvedGlassEffect` 声明policy的自定义效果，并将单场景custom glass预算固定为一个；因此该变化未在sidebar、inspector、composer、dialog、list row或正文叠加非官方玻璃。欢迎页文本、三栏主锚点、wordmark、New Session、空态、hero、chooser/mode 行与composer结构没有出现由T5.4引入的可观察偏移。报告仍为已登记的无头系统材质 `report-only`：materially changed ratio `0.03574777`、mean absolute channel difference `6.159037`、exact changed ratio `0.50733445`；该差异不构成welcome像素验收通过，亦未被T5.4错误豁免。

## 2026-08-19 — T5.5 limited accessible custom glass controls review

证据：macOS-26 [run 32226837259](https://github.com/NewbieXvwu/deepseek-harness-glass/actions/runs/32226837259)，commit `002f4743ffb4bb0c3a511d71896506dddc6cb419`，工件 `native-ui-002f4743ffb4bb0c3a511d71896506dddc6cb419` 的官方 PNG、`welcome-light.png`、comparison、amplified diff 与报告 JSON。该run通过完整静态/module/transport/material/GlassPolicy gates、SwiftPM、真实rc.7 Host smoke、`GlassAppTests`（新增Reduce Transparency、Increase Contrast、Reduce Motion policy regression）、应用装配、快照与官方配对。

人工检查对照确认：仅互斥的官方sidebar打开/收起导航操作置于 `GlassEffectContainer`，共用稳定 `glassEffectID`，保持既有官方尺寸、图标和accessibility label；不新增第二个同时存在的custom glass控件，正文、composer、list row、modal和系统sidebar/inspector结构材质均未被覆盖。Reduce Transparency或Increase Contrast会使批准glass效果降级为清晰的官方图标按钮，Reduce Motion会去除sidebar形变及pressed动画。欢迎页文本与三栏布局未出现T5.5可归因回归。报告仍为T5.3已限定的无头系统材质 `report-only`：materially changed ratio `0.03569754`、mean absolute channel difference `6.06478`、exact changed ratio `0.50733445`，不构成welcome像素验收通过。
