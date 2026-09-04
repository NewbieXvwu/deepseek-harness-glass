# DeepSeek Harness Glass：0.1.2-rc.1 Clean-cut 迁移 TODO

**目标分支：** `main`

**建议实施分支：** `migration/dsh-0.1.2-rc.1`。迁移分支允许中间提交暂时不可运行，但不得为了维持中间态可运行而引入双协议、shim、fallback 或版本分支；最终只做一次 clean cut 合入 `main`。

**目标系统：** macOS 26+、Xcode 26+、Apple Silicon、Swift 6。

**已验证官方基线：** `deepseek-ai/deepseek-harness@a66e4702047846cdaa10c66c9d3df3951f5ea70d`（tag `dsh-v0.1.2-rc.1`）。所有“已验证”协议、状态机、UI 规格、fixture 和视觉证据都必须精确回链到该 SHA。

**历史归档：** 迁移前的 `0.1.1-rc.2` TODO 与历史验收记录原样保存在 [`TODO_LEGACY_RC2.md`](TODO_LEGACY_RC2.md)。该文件只用于追溯，不再是执行入口，也不能作为 rc.1 任务的完成证据。

> **Clean-cut 原则：** 不接受任何 shim，不维护主动的向后兼容或向前兼容实现，不做旧 endpoint fallback，不做新旧 DTO 双解码，不保留旧 transport 作为备用通道，不根据 Host 版本选择不同协议路径，不用旧 fixture 维持测试通过。旧实现只有两种处置：经 rc.1 来源重新认证后保留，或删除。

> **Best-effort 前向宽容：** “不写兼容层”不等于“拒绝未知 Host”。`0.1.2-rc.1` 是唯一可宣称已验证的基线；任何非精确匹配的本地 Host，只要能够完成当前 rc.1 的认证与 Remote handshake，就允许以 **Best-effort / Unverified** 状态继续使用**同一套 rc.1 实现**。版本匹配只决定保证等级与诊断文案，不决定业务 API 的授权，也不触发另一套 endpoint、DTO、状态机或 feature branch。某个未知 Host 后续若在具体 method、stream 或 schema 上不兼容，则按该真实协议错误失败并暴露诊断，不回退到旧实现。

> **关于 CI：** 本迁移不新增“扫描旧符号 / 旧 endpoint / 旧 SHA”的专用 CI gate。旧协议的消失通过实际删除生产代码、fixture 和双路径 composition 来实现。现有构建、XCTest、官方规格校验、视觉与无障碍工作流可以继续使用，也可以为新架构增加正常的单元/集成测试，但不要建立一套专门的 legacy-ban 静态门禁。

## 0. 新完成定义与架构不变量

| 编号 | 完成定义 | 可验证事实 |
|---|---|---|
| N0 | 核心 UI 完全原生。 | Conversation、Sidebar、Workspace、Settings、Models、Credentials、Tooling 不使用 WebView；WebKit 只允许位于 Ghost Plane 插件运行时。 |
| N1 | 单一已验证官方规格。 | 所有 locale、token、layout、Remote contract、Session contract、插件 contract、视觉场景都回链到 `a66e4702047846cdaa10c66c9d3df3951f5ea70d`。 |
| N2 | 单一协议实现。 | 无论 exact baseline 还是 unknown Best-effort Host，运行时只有一套 rc.1 Remote/Session/Workspace/Plugin 实现。 |
| N3 | 版本验证是保证等级，不是权限层。 | exact SHA/build 标记 `verified`；其他能完成认证和 Remote handshake 的 Host 标记 `bestEffort`，业务调用仍走同一 controller；不因版本未知而锁死输入或写操作。 |
| N4 | Host ready 必须已经认证。 | `ready` 不再只表示有 loopback URL；它必须表示 Cookie bootstrap 完成、Remote connection 建立、Host facts 已读取并完成 verified/best-effort 分类。 |
| N5 | Remote 是唯一线协议边界。 | Feature、Store、reducer 不认识 HTTP URL、WebSocket frame、rpcId envelope 或旧 SSE 类型。 |
| N6 | Session 以 journal/control 双平面复制。 | durable history 只来自 `session.follow` + `session.page`；transient control 只来自 `session.control`；不存在 `session.history` 或旧 `session/event` / `session/projection` ingest。 |
| N7 | Tool presentation 由 Client 从 raw Session events 派生。 | journal 不携带旧 `ToolEventViewDTO`；native renderer 从 raw `tool/call`、`tool/result` 等事件建立 presentation。 |
| N8 | Workspace 以 `workspace.follow` 为实时权威。 | baseline 后只接受 rc.1 closed union 的 `upsert`、`remove`、`order`、`archived` 增量。 |
| N9 | Plugin Plane 使用 rc.1 module graph/combo bundle。 | 不存在旧单插件 `client.js` fallback loader；Ghost Plane 只接受 rc.1 module/slot/bundle contract。 |
| N10 | UI 重新认证。 | 任何从 rc.2 继承的可见页面都必须经过 rc.1 同状态来源审计、视觉配对、键盘和 AX 复核后才算完成。 |

### 0.1 目标架构

```text
SwiftUI / AppKit Feature
        │
        ▼
Native Stores / View State
        │
        ▼
Domain Runtime / Repository
        │
        ├── SessionRuntime
        ├── WorkspaceRuntime
        ├── SettingsRepository
        ├── CredentialRepository
        ├── ModelCatalogRepository
        └── PluginRuntime
        │
        ▼
HarnessControllers
        │
        ▼
RemoteConnection
        │
        ├── typed unary Remote calls
        ├── logical Remote streams
        ├── connection generation
        └── /api/remote.mux
        │
        ▼
AuthenticatedHostSession
        │
        ▼
HostAuthBootstrap
        │
        ▼
HarnessHostProcess
```

### 0.2 当前组件处置表

| 当前组件/概念 | 处置 | rc.1 最终形态 |
|---|---|---|
| `DSHClientTransport` | 删除 | `RemoteConnection` |
| `DSHAPIClient` | 删除 | typed controller APIs |
| `RPCClientRequest` / `RPCServerResponse` / `RPCServerRequest` | 删除 | rc.1 Remote wire models |
| `SSEClient` / `DSHSSEEndpoint` / `SSEReplayFence` | 删除 | `RemoteMuxConnection` + connection generation + domain cursor |
| `session.history` | 删除 | `session.follow` + `session.page` |
| `session/event` / `session/projection` 旧实时入口 | 删除 | addressed Session journal stream |
| queue/jobs 的旧混合 ingest | 删除 | `session.control` snapshot stream |
| `SessionHistoryPager` | 删除 | `SessionJournal.loadOlder()` |
| 巨型 `NativeSessionStore` | 拆分 | `SessionRuntime` + `SessionProjectionEngine` + 薄 `NativeSessionStore` |
| `ToolEventViewDTO` / `callView` / `resultView` | 删除 | raw-event `ToolInvocationProjector` |
| 裸 `HostConnection(endpoint)` | 重定义 | `HostConnectionContext` with authenticated Remote |
| 裸 loopback external probe | 重做 | rc.1 auth/bootstrap 后 exact build 或 Best-effort connection |
| `Core/Transport` 目录 | 删除 | `Core/Remote` |
| 旧单插件 Web bundle loader | 删除 | rc.1 module graph + combo bundle resolver |
| rc.2 runtime fixtures/spec | 从当前执行面删除 | rc.1 exact-SHA fixtures/spec |

## 1. CUT0：锁定迁移边界与上游来源

- [ ] **CUT0.1：将 `dsh-v0.1.2-rc.1` 设为唯一 verified baseline。** 更新 `SupportedHostBuilds.json`、Host build metadata、bundled payload lock、Node/payload manifest 和 app build manifest，使唯一 verified 条目精确指向 `a66e4702047846cdaa10c66c9d3df3951f5ea70d`。
  - 依赖：无。
  - 验收：项目不再宣称 rc.2 已验证；bundled payload、OfficialUISpec 与 verified build 三者 SHA 一致。

- [ ] **CUT0.2：重新定义 Host compatibility classification。** 将版本状态收敛为 `verified` 与 `bestEffort`：exact build/SHA 为 `verified`；非 exact build 在成功完成当前认证和 Remote handshake 后为 `bestEffort`。删除旧“unknown = 默认写保护 / 需要 developer override”语义。
  - 依赖：CUT0.1。
  - 验收：版本未知只改变诊断/兼容提示，不改变同一 Remote controller 是否可被调用；不存在第二套协议实现。

- [ ] **CUT0.3：明确 Best-effort 的失败语义。** 未知 Host 不做版本协商和主动 capability shim；若某个 rc.1 method/stream/schema 不被支持，保留 Host/Remote 的真实失败分类并呈现兼容提示，不尝试旧 endpoint、旧 DTO 或另一种状态机。
  - 依赖：CUT0.2。
  - 验收：任何“为了未知版本再试一次旧 API”的代码设计都被拒绝；正常的 transport reconnect 不属于协议 fallback。

- [ ] **CUT0.4：建立 rc.1 source-of-truth 清单。** 对 `packages/client/connection`、`packages/api/gateway`、`packages/api/session-controller`、`packages/api/workspace-controller`、Settings/Credentials/LLM controllers、Tool presentation、Conversation/UI Chat、Plugin graph/bundle、locale/theme/layout 建立精确路径、commit、输入 SHA 和职责说明。
  - 依赖：CUT0.1。
  - 验收：每一个后续 DTO、状态机、UI task 都能回链到该清单，禁止以 rc.2 注释或历史 notes 作为新实现依据。

- [ ] **CUT0.5：完成一次全树迁移盘点。** 对 `glass/Sources`、`glass/Tests`、`glass/ci`、`glass/tools`、fixtures、docs 中所有 rc.2 contract 逐项标为 `retain-after-reaudit`、`rewrite`、`delete`；重点覆盖 `DSHClientTransport`、`SSEClient`、`RPCModels`、`DomainAPIs`、`NativeSessionStore`、`SessionHistoryPager`、Ghost Plane loader。
  - 依赖：CUT0.4。
  - 验收：没有“暂时保留以后再看”的协议组件；每个旧组件都有明确终态。

- [ ] **CUT0.6：冻结 clean-cut 实施规则。** 新实现只表达 rc.1 语义，不允许 `if version`、old/new decoder fallback、404 fallback、legacy endpoint retry、旧 fixture decode、compatibility typealias 或 deprecated wrapper。
  - 依赖：CUT0.2。
  - 验收：需要回滚时回滚 Git commit/发行版本，而不是在当前二进制里切换旧 runtime。

## 2. CUT1：重建 Official Spec 与 rc.1 fixtures

- [ ] **CUT1.1：重生成 `OfficialUISpec.Build`。** 以 rc.1 commit 为唯一 source commit，重新计算 locale/token/layout/fixture revisions、generator input hashes、build ID 和 generated metadata。
  - 依赖：CUT0.4。
  - 验收：current spec 不再引用 rc.2 source commit 或历史 revision。

- [ ] **CUT1.2：重生成 locale、theme、layout 和官方资产。** 从 rc.1 TypeScript/TSX/CSS AST fresh-extract 所有可见文本、主题 token、布局常量、SVG/图标；不得因输出“看起来相同”而跳过生成。
  - 依赖：CUT1.1。
  - 验收：新增/删除 key、token、asset 均有 drift 记录并绑定 source hash。

- [ ] **CUT1.3：重做 Remote contract manifest。** 放弃旧 APIProxy/RPC envelope manifest，按 rc.1 Gateway/Remote namespace 建模 unary procedure、stream procedure、输入、输出、closed error union 与非 JSON route。
  - 依赖：CUT0.4。
  - 验收：覆盖 Glass 实际使用的 Session、Workspace、Settings、Credentials、LLM、Subagent、Feedback、Host、Downloads 等 namespace；不含旧 `session.history` / `events.mux` / `events.host`。

- [ ] **CUT1.4：重新捕获 rc.1 authenticated Host fixtures。** 使用隔离 `DSH_HOME` 与 exact bundled payload 生成 Remote unary、stream opening、stream delta、business error、download 等真实 fixture。
  - 依赖：CUT1.3、CUT2.3、CUT3.4。
  - 验收：fixture 不依赖用户凭据和真实工作目录；launch token、Cookie、secret 不落盘。

- [ ] **CUT1.5：重新生成 Session journal fixtures。** 覆盖 packed history record、follow opening snapshot、live append、page prepend、`hasMore`、projection baseline、ordinary/direct-subagent address、空 Session、超长未完成 assistant tail。
  - 依赖：CUT1.3。
  - 验收：fixture 能验证 packed record 展开边界和 sequence 连续性，不再保存旧 SSE frame。

- [ ] **CUT1.6：重新生成 `session.control` fixtures。** 覆盖 opening baseline、queue/jobs 等 transient state、后续 delta、stream restart 和空 baseline。
  - 依赖：CUT1.3。
  - 验收：durable journal fixture 与 control fixture 完全分离。

- [ ] **CUT1.7：重新生成 Workspace follow fixtures。** 对 rc.1 `workspace.follow` 建立 baseline 与 closed union 增量：`upsert`、`remove`、`order`、`archived`。
  - 依赖：CUT1.3。
  - 验收：任何 list/poll 推导不作为实时 Workspace fixture。

- [ ] **CUT1.8：重做 interaction / visual / AX scene catalog。** 对 rc.1 已变化的 Conversation、Settings、Models、Plugins、connection recovery、queue、image、字体和 Markdown table scaling 等场景重新采集官方基线。
  - 依赖：CUT1.1、CUT1.2。
  - 验收：rc.2 screenshot/ARIA 只留历史，不再给新任务提供完成证据。

- [ ] **CUT1.9：重做 Ghost Plane 官方 contract。** 从 rc.1 module graph、slot ownership、combo bundle 路径重新生成 `OfficialGhostPlaneContract`、slot map、module source ledger 和测试输入。
  - 依赖：CUT0.4。
  - 验收：不保留旧单插件 bundle URL 作为 fallback contract。

## 3. CUT2：Host Launch → Authenticate → Classify → Ready

- [ ] **CUT2.1：将 Host 启动输出解析从 endpoint 升级为 `HostLaunchDescriptor`。** 解析 rc.1 `dsh web:` 输出里的完整 process-token URL，校验 scheme、loopback authority、port、root path 和 token query；token 不拆散到多个长期状态字段。
  - 依赖：CUT0.1。
  - 验收：malformed、非 loopback、缺 token announcement 失败关闭；日志不记录 token 明文。

- [ ] **CUT2.2：实现 `HostAuthBootstrap`。** 对 launch URL 执行唯一允许的 root token exchange，接受官方 redirect / `Set-Cookie` 语义，得到 clean base URL 与 authenticated cookie jar。
  - 依赖：CUT2.1。
  - 验收：token 只用于 bootstrap `GET /`；后续 API 不携带 query token 或 Authorization token。

- [ ] **CUT2.3：实现独立 `AuthenticatedHostSession`。** 每个 Host 生命周期创建独立 `URLSessionConfiguration.ephemeral`、独立 `HTTPCookieStorage`；HTTP Remote、WebSocket mux、download 共用同一认证上下文；不得依赖 `.shared` 全局 Cookie。
  - 依赖：CUT2.2。
  - 验收：Host restart 后旧 cookie/session 不被复用；新进程必须重新 bootstrap。

- [ ] **CUT2.4：重做 Host lifecycle state。** 目标主路径为 `idle → starting → authenticating → connecting → classifying → ready`，并保留 `recovering` / `failed` / `stopping`；删除旧 `probingExternal` 与把 unverified 当半失败状态的结构。
  - 依赖：CUT2.2、CUT3.4。
  - 验收：`ready` 一定携带可工作的 Remote 与 `verified`/`bestEffort` classification。

- [ ] **CUT2.5：定义 `HostConnectionContext`。** 至少包含 clean baseURL、authenticated session、`RemoteConnection`、Host facts、compatibility classification、connection generation 和 diagnostics identity；不得暴露 launch token。
  - 依赖：CUT2.3、CUT3.4。
  - 验收：业务 composition root 只能从 context 创建 Controllers。

- [ ] **CUT2.6：将版本验证改为认证后的 compatibility classification。** 读取 rc.1 Remote 可获得的 Host/build facts；精确匹配 catalog 为 `verified`，否则为 `bestEffort`。classification 不能改变 controller graph，也不能禁用写操作。
  - 依赖：CUT2.5、CUT4.1。
  - 验收：同一 Host 在 exact build 与未知 build 情况下得到相同 API surface，只是保证等级/诊断不同。

- [ ] **CUT2.7：重做外部 Host 复用。** 外部本地 Host 必须提供或发现能够完成 rc.1 auth bootstrap 的 launch URL；认证成功后按 CUT2.6 分类。删除“裸 `127.0.0.1:port` + 未认证 probe”作为正式连接方式。
  - 依赖：CUT2.2、CUT2.6。
  - 验收：exact baseline 外部 Host 可为 verified；相邻未知版本若 handshake 成功则可 Best-effort 使用；无法通过当前 auth/Remote handshake 的旧 Host 自然失败。

- [ ] **CUT2.8：重做 Host restart/recovery。** owned Host 退出后完整丢弃 `AuthenticatedHostSession`、Remote connection 与所有 stream generation，重启后重新 launch-token exchange、Remote connect、classify，再发布新的 `HostConnectionContext`。
  - 依赖：CUT2.4、CUT3.6。
  - 验收：无旧 cookie、旧 WebSocket、旧 logical stream、旧 Session generation 穿越进程边界。

- [ ] **CUT2.9：更新诊断与日志脱敏。** 新增 auth phase、compatibility classification、Remote generation、stream recovery 状态；继续隐藏 token、Cookie、credential、payload。
  - 依赖：CUT2.4、CUT3.6。
  - 验收：诊断可区分 verified 与 Best-effort，但不泄露认证材料。

## 4. CUT3：从零实现 `RemoteConnection`

- [ ] **CUT3.1：删除 `DSHClientTransport` 的演化路径并新建 `Core/Remote`。** 不从旧 transport 继承 public API；建立 `RemoteConnection.swift`、`RemoteMuxConnection.swift`、`RemoteProcedure.swift`、`RemoteStreamProcedure.swift`、`RemoteError.swift`、`RemoteConnectionGeneration.swift`、`RemoteTrace.swift`、`RemoteWireModels.swift`。
  - 依赖：CUT1.3。
  - 验收：Feature/Runtime 不再 import 或引用 `Core/Transport`。

- [ ] **CUT3.2：定义强类型 unary procedure。** 用 `RemoteProcedure<Input, Output>` 表达方法名、输入、输出和 error contract；字符串 method name 只允许存在于 Remote/API contract 定义边界。
  - 依赖：CUT3.1。
  - 验收：Feature 代码中不存在 `call("session.foo", JSONValue)`。

- [ ] **CUT3.3：定义强类型 stream procedure。** 用 `RemoteStreamProcedure<Input, Frame>` 表达 rc.1 logical streams，stream 生命周期由 `RemoteConnection`/`RemoteMuxConnection` 管理，domain runtime 只收到 typed frames。
  - 依赖：CUT3.1。
  - 验收：Session/Workspace 不解析 WebSocket message 或 mux envelope。

- [ ] **CUT3.4：实现 rc.1 HTTP Remote unary carrier。** 使用 authenticated session POST 官方 Remote gateway 所需请求，完整实现 request correlation、closed result/error decode、取消、timeout、HTTP/codec 错误分类。
  - 依赖：CUT2.3、CUT3.2。
  - 验收：真实 authenticated Host 上基础 unary request round-trip 通过；旧 `server-response` envelope 不参与。

- [ ] **CUT3.5：实现 `/api/remote.mux` 物理 WebSocket。** 一个 physical socket 承载多个 logical stream；实现 stream registration、frame routing、terminal frame、dispose、backpressure/ordering 的官方语义。
  - 依赖：CUT2.3、CUT3.3。
  - 验收：不再打开 `/api/events.mux` 或 `/api/events.host`。

- [ ] **CUT3.6：实现 connection generation。** `$events` / ready 语义建立新 generation；physical connection 丢失立即使旧 generation 失效，新 generation ready 后再允许 domain runtime 建立 authoritative baselines。
  - 依赖：CUT3.5。
  - 验收：底层只发布 generation/connectivity，不维护 SessionSeq 或 Workspace revision。

- [ ] **CUT3.7：实现 Remote stream reconnect 基元。** carrier failure 与 protocol/business terminal failure分开；carrier reconnect 创建新 physical mux/generation，logical domain stream由其 Runtime 按新 generation 重新 open。
  - 依赖：CUT3.6。
  - 验收：Remote 层不跨 reconnect 维护旧 `rpcId`/session seq replay fence。

- [ ] **CUT3.8：禁止 transport 层自动重放业务 mutation。** in-flight unary 在 carrier failure 时明确失败；是否重试由 domain command 语义决定。`session.prompt` 等业务 request identity 不由 transport 偷偷生成。
  - 依赖：CUT3.4。
  - 验收：没有“网络断开后自动再 POST 一次 mutation”的通用机制。

- [ ] **CUT3.9：重做 Remote errors 与 diagnostics taxonomy。** 区分 authentication、transport、carrier lost、remote business error、protocol/codec error、unsupported/unavailable method；Best-effort Host 的 method/schema failure 仍保持真实分类。
  - 依赖：CUT3.4、CUT3.5。
  - 验收：未知 Host 不兼容时不会被伪装成“版本不支持”然后回退旧协议。

- [ ] **CUT3.10：重做下载/非 JSON route。** Session export 等 route 使用同一 `AuthenticatedHostSession` 与 Host trust context，不再依赖旧 `DSHClientTransport.downloadURL`。
  - 依赖：CUT2.3、CUT1.3。
  - 验收：download 认证、取消、文件落盘和脱敏保持原有安全属性。

## 5. CUT4：Typed Controllers 与 composition root

- [ ] **CUT4.1：将 `HarnessAPIs` 重构为 `HarnessControllers`。** 保留“Feature 不认识 wire”的原则，但所有实现改为依赖 `RemoteConnection`，不依赖 `DSHAPIClient`。
  - 依赖：CUT3.4、CUT3.5。
  - 验收：composition root 只从 `HostConnectionContext.remote` 建立 controllers。

- [ ] **CUT4.2：实现 `SessionControllerAPI`。** 精确覆盖当前 Glass 所需的 rc.1 session list/search/create/prompt/cancel/select model/fork/rename/addressing/page/follow/control 等能力；方法签名采用 rc.1 typed request/response。
  - 依赖：CUT4.1、CUT1.3。
  - 验收：不存在 `history()`、旧 queue snapshot endpoint 或旧 events API。

- [ ] **CUT4.3：实现 `WorkspaceControllerAPI`。** unary command 与 `workspace.follow` 分开；follow 为 typed snapshot stream。
  - 依赖：CUT4.1。
  - 验收：Workspace UI 不通过定时 list 维持实时状态。

- [ ] **CUT4.4：实现 Settings/Credentials/Model Catalog controllers。** Settings revision、Credentials describe/set/unset、Host 级 model catalog/provider discovery 均按 rc.1 Remote namespace重新建模。
  - 依赖：CUT4.1。
  - 验收：secret 仍不进入 observable readback；Models 不再从旧 `session.models` 获取 Host 全局目录。

- [ ] **CUT4.5：实现 Subagent/Feedback/Agent Preset/Skill/Command controllers。** 对 rc.1 namespace 逐个核对 method ownership 与输入输出，不机械平移旧 method string。
  - 依赖：CUT4.1。
  - 验收：每个 facade 有精确上游 source path 与 fixture。

- [ ] **CUT4.6：删除 protocol default implementation 中的“未实现则 invalidEndpoint”便捷行为。** production/test fake 对 required capability 都必须显式实现；可选能力用真实类型建模，不用默认 throw 伪装。
  - 依赖：CUT4.2–CUT4.5。
  - 验收：测试 fake 缺 required API 时编译期暴露，而不是运行时才发现。

## 6. CUT5：重建 Session Runtime

- [ ] **CUT5.1：定义 Session 基础强类型。** 至少建立 `SessionSeq`、`SessionLogOffset`（若当前 rc.1 contract需要）、`ConnectionGeneration`、`SessionRequestID`、`SessionAddress`；禁止在 journal merge API 中混用裸 `Int`。
  - 依赖：CUT4.2。
  - 验收：sequence、offset、connection generation 在类型系统中不能互换。

- [ ] **CUT5.2：实现 `SessionJournal`。** 它只接受 follow opening snapshot、follow live append 和 page prepend，维护 current cut、records、oldest/newest seq、`hasMore` 与 generation ownership。
  - 依赖：CUT5.1、CUT4.2。
  - 验收：同一 `SessionSeq` 只能对应同一 durable event；旧 generation frame 无修改权限。

- [ ] **CUT5.3：实现 follow-first open 顺序。** `SessionRuntime.open` 先建立 `session.follow`，接收 opening snapshot + cursor，再将该 authoritative cut 安装为当前 journal；不允许先 page/history 后补订阅。
  - 依赖：CUT5.2。
  - 验收：不存在 history→subscribe race window。

- [ ] **CUT5.4：实现 `SessionJournal.loadOlder()`。** `session.page` 自动绑定当前 follow opening cut 的 `throughSeq`，只向该 frozen cut 以前 prepend；支持 `maxMessages`、`hasMore` 和 packed history record 展开。
  - 依赖：CUT5.3。
  - 验收：新 live append 不改变正在执行的历史 page 的 `throughSeq`。

- [ ] **CUT5.5：实现 journal gap/repair 语义。** 按 rc.1 `RemoteJournalStream` 的 sequence 连续规则处理 overlap、duplicate、gap、carrier recovery；repair 重新取得 authoritative follow cut，而不是跨代猜测缺失事件。
  - 依赖：CUT5.2、CUT3.7。
  - 验收：随机断线/重连下最终 journal 与 fresh open 一致。

- [ ] **CUT5.6：实现 `SessionControlRuntime`。** 单独消费 Host-wide `session.control` opening baseline 与 delta，维护 queue、jobs 和其他 rc.1 transient projections；generation 切换时旧 transient authority 立即失效。
  - 依赖：CUT4.2、CUT3.7。
  - 验收：queue/jobs 不通过 durable history reducer 重建。

- [ ] **CUT5.7：定义 `SessionRuntime`。** 组合一个 addressed `SessionJournal`、Host-wide control view、commands 和 projection engine；Runtime 是 actor/并发边界，不绑定 MainActor。
  - 依赖：CUT5.2–CUT5.6。
  - 验收：网络/JSON/reconnect merge 不在 SwiftUI MainActor执行。

- [ ] **CUT5.8：实现 `SessionCommandService`。** prompt、cancel、queue mutation、approval/question response、model selection 等 command 与 observation 分开；成功 mutation 不直接篡改 authoritative snapshot，等待 Host stream 回来确认。
  - 依赖：CUT5.7、CUT4.2。
  - 验收：没有“RPC 200 后本地假装 Host state 已变化”的路径。

- [ ] **CUT5.9：把 `requestId` 提升为 prompt domain identity。** 用户按 Send 时在 command layer 创建 `SessionRequestID`，贯穿 pending intent、Remote request、重试诊断和后续 Host event correlation；transport 不生成它。
  - 依赖：CUT5.8。
  - 验收：重复点击/失败重试能区分同一用户 intent 与新 intent。

- [ ] **CUT5.10：实现 session switching/resident-state 新语义。** resident cache 只缓存 UI/projection snapshot；重新选中 Session 时 authoritative durable/control state 必须来自当前 generation 的 Runtime，不复用旧 transport generation。
  - 依赖：CUT5.7。
  - 验收：Host restart 后切回旧 Session 不会展示被当成 authoritative 的旧 queue/jobs。

- [ ] **CUT5.11：实现 direct-subagent SessionAddress。** 不从普通 session summary 猜测 child route，按 rc.1 address union 打开 journal/control/command。
  - 依赖：CUT5.3、CUT4.5。
  - 验收：ordinary 与 direct-subagent fixtures 都能完成 open/page/follow。

- [ ] **CUT5.12：删除 `SessionHistoryPager` 和旧 ingest 状态机。** 在新 Runtime 通过相同功能测试后删除旧 pager、旧 subscribed generation 清理、旧 SSE reducer 和任何 `session.history` 调用。
  - 依赖：CUT5.3–CUT5.11。
  - 验收：新 Session Runtime 不引用旧类型。

## 7. CUT6：Projection Engine 与薄 `NativeSessionStore`

- [ ] **CUT6.1：建立 `SessionProjectionEngine`。** 输入只接受 `SessionJournalState` + `SessionControlState`，输出 Conversation、Tool、Approval、Question、Queue、Jobs、running/model 等 Host-authoritative projections。
  - 依赖：CUT5.7。
  - 验收：Projection 不认识 Remote frame、HTTP、WebSocket 或 cookie。

- [ ] **CUT6.2：迁移并重新认证 Conversation reducer。** 保留与 raw durable events 兼容的已有 reducer 思路，改掉任何依赖 rc.2 `view` carrier/旧 projection event 的输入。
  - 依赖：CUT6.1、CUT1.5。
  - 验收：opening snapshot + live append 与同样完整历史 fresh fold 生成相同 nodes。

- [ ] **CUT6.3：实现 raw-event `ToolInvocationProjector`。** 从 rc.1 `tool/call`、`tool/result`、failure/meta 等原始事件派生 terminal/read/diff/search/web/todo/question/workflow 等 typed presentation。
  - 依赖：CUT6.1、CUT1.5。
  - 验收：不使用 `ToolEventViewDTO`、`callView`、`resultView`。

- [ ] **CUT6.4：重新连接 Approval/Question。** 如果 rc.1 correlation/response ownership 已变化，按新 Remote/session contract 重新建 pending model 与 answer command；不沿用旧 `/api/respond` carrier 假设。
  - 依赖：CUT5.8、CUT6.1。
  - 验收：approval/question 的可见状态完全来自 Host-authoritative event/control evidence。

- [ ] **CUT6.5：重新连接 Queue/Jobs。** UI projection 只读 `SessionControlState`，command 成功后等待 control delta/baseline确认。
  - 依赖：CUT5.6、CUT6.1。
  - 验收：断线后旧 queue/jobs 立即失去 authority；新 baseline 原子替换。

- [ ] **CUT6.6：瘦身 `NativeSessionStore`。** Store 只承担 MainActor UI 编排与 local view state：draft、selection、pending local images、scroll/focus；Host-authoritative snapshot 由 `SessionRuntime` AsyncStream/observation 发布。
  - 依赖：CUT6.1–CUT6.5。
  - 验收：Store 不 decode JSON、不解析 Remote frame、不实现 journal pagination 或 reconnect fence。

- [ ] **CUT6.7：清理 resident/local authority 混杂。** 明确 local draft/image 与 Host snapshot 的生命周期；Host reconnect 不应清掉合法 local draft，但必须清除旧 Host authority。
  - 依赖：CUT6.6。
  - 验收：断线/重连/切 Session 的 local-vs-remote 测试覆盖完整。

## 8. CUT7：Workspace Runtime

- [ ] **CUT7.1：实现 `WorkspaceRuntime`。** 打开 `workspace.follow`，opening baseline 原子替换当前 Workspace state，后续只接受 `upsert`、`remove`、`order`、`archived` closed union。
  - 依赖：CUT4.3、CUT1.7。
  - 验收：runtime 不依赖 list polling 维持实时性。

- [ ] **CUT7.2：实现 Workspace stream generation recovery。** carrier loss 使当前 follow authority 暂时无效/标记 recovering；新 generation 重新获取 opening baseline，而不是把新 delta 接到旧 baseline 后面。
  - 依赖：CUT7.1、CUT3.7。
  - 验收：Host restart 后 Workspace snapshot 与 fresh app launch 一致。

- [ ] **CUT7.3：迁移 Workspace commands。** create/rename/delete/reorder/archive/session insert 等 unary command 按 rc.1 typed controller 发送，visible state 等待 follow stream 确认。
  - 依赖：CUT7.1、CUT4.3。
  - 验收：command response 不直接重排 sidebar authoritative rows。

- [ ] **CUT7.4：瘦身 `NativeWorkspaceStore`。** Store 只投影 Runtime snapshot 与 UI selection/dialog local state，不持有 transport/list polling。
  - 依赖：CUT7.1–CUT7.3。
  - 验收：Workspace UI 与 Remote 完全隔离。

## 9. CUT8：Settings、Credentials、Models 与 Onboarding

- [ ] **CUT8.1：将 Settings 迁到 rc.1 controller。** 保留 draft/revision fence 的领域设计，但 describe/mutate、schema、resolved/base/user values 与 invalidation 来源重新绑定 rc.1 contract。
  - 依赖：CUT4.4、CUT1.3。
  - 验收：旧 `DSHAPIClient.settingsDescribe/settingsMutate` 删除。

- [ ] **CUT8.2：重连 Credentials。** `describe/set/unset` 全部走 rc.1 controller；observable state 继续只保存 configured/source/writable 等安全事实，不保存 secret value。
  - 依赖：CUT4.4。
  - 验收：set/unset 后必须 fresh Host readback 才更新可见状态。

- [ ] **CUT8.3：将 Model Catalog 提升为 Host-wide repository。** 不再由 active Session Store 持有整份模型目录；Settings、Composer、Onboarding 共用一个 `ModelCatalogRepository`。
  - 依赖：CUT4.4。
  - 验收：Session 切换不会重新把 Host 全局 catalog 当 session-private state 获取。

- [ ] **CUT8.4：迁移 provider discovery / discovered-model adoption。** 按 rc.1 provider/settings contract 重审 request、candidate、writeback path、revision fence；保留 secret 只作为瞬时参数的原则。
  - 依赖：CUT8.1–CUT8.3。
  - 验收：不存在基于旧 provider schema 的猜测 fallback。

- [ ] **CUT8.5：重新实现 Onboarding atomic readiness snapshot。** 将 provider、settings、credential、welcome acknowledgement/session gate 等 rc.1 Host facts 组合为一次一致快照，淘汰 rc.2 三份独立 refresh 的竞态。
  - 依赖：CUT8.1–CUT8.3。
  - 验收：readiness 不从 provider 名称或单一 credential ref 猜测。

- [ ] **CUT8.6：重新审计 Settings Root / General / Models / Plugins / Agent Presets。** 以 rc.1 source 与 locale 重做 section ledger、顺序、close/focus/Escape、provider login controls、search/filter、plugin grouping、agent preset search等新增行为。
  - 依赖：CUT1.8、CUT8.1–CUT8.5。
  - 验收：rc.2 的 17 项 SettingsRoot 测试只能作为历史参考，不能直接证明 rc.1 parity。

## 10. CUT9：Conversation / ui-chat 重新映射

- [ ] **CUT9.1：重做 Conversation source map。** 明确 rc.1 `ui-conversation` 与独立 `ui-chat` 的职责、slot ownership、node assembler 与 visible renderer 来源；更新所有相关 `OfficialUISpec`/source ledger。
  - 依赖：CUT1.2、CUT1.8。
  - 验收：不再把已经迁入 `ui-chat` 的行为错误回链到旧路径。

- [ ] **CUT9.2：重新认证 Chat 基础结构。** user/assistant rows、process folding、system prompt folding、running/settled states、normal/compact 目标全部对 rc.1 官方场景重新配对。
  - 依赖：CUT9.1、CUT6.2。
  - 验收：现有 SwiftUI 可复用，但必须有 rc.1 source + paired evidence。

- [ ] **CUT9.3：实现 rc.1 token/time footer。** 对 token usage、duration、turn metadata 的显示规则、隐藏规则、locale、geometry 建原生 projection/view。
  - 依赖：CUT9.1、CUT6.2。
  - 验收：数据只能来自 Host/Conversation projection，不由 UI 自算猜测。

- [ ] **CUT9.4：实现 full-history turn navigation。** 按 rc.1 Chat 状态与可见控制复刻向前/向后/末尾定位、disabled state、keyboard/AX。
  - 依赖：CUT9.2、CUT5.4。
  - 验收：加载更旧历史与导航 cursor 协作正确。

- [ ] **CUT9.5：实现 conversation content width / resizing 新行为。** 重审自适应宽度、可拖拽/边界、窄窗口退化、三栏联动。
  - 依赖：CUT1.2、CUT9.2。
  - 验收：官方/原生同视口 geometry 配对。

- [ ] **CUT9.6：实现字体大小与 Markdown table scaling。** 复刻 rc.1 Settings/Chat 对字体和 table scale 的行为，不在 renderer 中硬编码旧 rc.2 尺寸。
  - 依赖：CUT8.6、CUT9.2。
  - 验收：light/dark、不同字号的 snapshot/AX 完整。

- [ ] **CUT9.7：重新审计 Composer。** 对 requestId、queue send behavior、connection status/retry、image attachment/compression、model/agent preset选择等 rc.1 行为逐项映射。
  - 依赖：CUT5.8、CUT8.3、CUT1.8。
  - 验收：Composer 不持有 Remote client；Send intent 进入 `SessionCommandService`。

## 11. CUT10：Tool UI 全面 raw-event 化

- [ ] **CUT10.1：删除旧 presenter-view carrier。** 从 DTO、Session model、fixture、tests、renderer admission 中删除 `ToolEventViewDTO`、`view`、`callView`、`resultView`。
  - 依赖：CUT6.3。
  - 验收：工具卡片的 typed projection 只由 raw validated Session events产生。

- [ ] **CUT10.2：重新认证 terminal/bash renderer。** 保留已实现的 ANSI、cursor、copy、status 等原生能力，但输入和官方 source 全部迁至 rc.1 raw-event presenter逻辑。
  - 依赖：CUT10.1、CUT1.8。
  - 验收：running/completed/failed/stopped、长输出窗口、details、copy均有 rc.1 paired evidence。

- [ ] **CUT10.3：重新认证 read renderer。** 重做路径、range、line cap、copy、plain/syntax-highlight admission；如果 rc.1 仍没有可审计 native token source，则继续诚实 plain，不伪造高亮。
  - 依赖：CUT10.1。
  - 验收：call/result/failure 各状态与官方对应。

- [ ] **CUT10.4：重新认证 diff/file-mutation renderer。** 重审 hunks、added/removed、file paths、collapsed/details、copy 与 error states。
  - 依赖：CUT10.1。
  - 验收：typed projection 不依赖旧 `view` schema。

- [ ] **CUT10.5：重新认证 search/web renderer。** 重审结果 schema、链接安全、scheme admission、empty/failure/truncated 文案和 details。
  - 依赖：CUT10.1。
  - 验收：只允许官方允许的交互链接；未知 scheme 非交互。

- [ ] **CUT10.6：重新认证 todo / ask-question / workflow / subagent / image/attachment renderer。** 按 rc.1 工具注册与 client-side presentation 逐类建立 typed projector 和 native card。
  - 依赖：CUT10.1。
  - 验收：第一方常用工具覆盖达到 rc.1 官方 client 的可见功能面。

## 12. CUT11：Ghost Plane rc.1 重构

- [ ] **CUT11.1：重建 `PluginModuleGraph`。** 以 rc.1 system baseline、enabled plugin client modules、dependency ordering、runtime conflict resolution 为唯一 module graph；旧 graph schema 删除。
  - 依赖：CUT1.9。
  - 验收：module graph 能从真实 rc.1 Host/plugin state确定性生成。

- [ ] **CUT11.2：实现 combo bundle resolver。** 支持 rc.1 `/plugins/??<plugin1>,<plugin2>,...&rev=...` 等当前官方组合 bundle 语义；bootstrap/app 如有不同 bundle set 必须分别建模。
  - 依赖：CUT11.1。
  - 验收：不再请求旧 `/plugins/<pluginId>/client.js?rev=...` 作为 fallback。

- [ ] **CUT11.3：重做 SlotMap 与 Chat/Conversation ownership。** 处理 `ui-chat` 拆分后 slot 的真实 owner、anchor、red/green zone admission；不 patch 旧 map。
  - 依赖：CUT9.1、CUT1.9。
  - 验收：每个允许 Ghost Plane 挂载的 slot 都有 rc.1 source path。

- [ ] **CUT11.4：迁移 Skeleton DOM generator。** 对新的官方 column/chat geometry 重新生成透明骨架；保持 Core generator 与 WebKit host 分离。
  - 依赖：CUT11.3、CUT1.2。
  - 验收：官方内容由原生渲染，skeleton 只提供插件预期 anchor/geometry。

- [ ] **CUT11.5：迁移 scroll synchronizer。** 将现有 epoch/sequence/finite-double 设计接到真实 rc.1 transcript scroll，与当前 macOS scroll cadence/ProMotion 验证结合。
  - 依赖：CUT11.4。
  - 验收：不依赖旧 DOM 结构猜测。

- [ ] **CUT11.6：迁移 event bridge。** Keyboard、ImagePaste、Selection、Drag 等 typed contract 按 rc.1 plugin client expectations 重审，并接真实 AppKit keyboard/draft/selection/temp-file lifecycle。
  - 依赖：CUT11.3。
  - 验收：插件无需修改即可收到官方预期事件，核心原生 UI 不向 WebKit 让渡渲染权。

- [ ] **CUT11.7：迁移 PermissionBroker/adapters。** clipboard、notification、external navigation、file picker、download、network、visibility等能力按 rc.1 plugin runtime 重审，并完成 TCC/AppKit runtime。
  - 依赖：CUT11.6。
  - 验收：权限决策不由 plugin JS 绕过原生 broker。

- [ ] **CUT11.8：迁移 profile routing/preferences。** shared/isolated policy、UserDefaults、设置 UI、diagnostics与 marketplace/runtime mount 按 rc.1 模块图重新接线。
  - 依赖：CUT11.1、CUT8.6。
  - 验收：profile 选择立即影响后续 module graph，而非旧 loader 的局部开关。

- [ ] **CUT11.9：迁移 Attach/Adopt/Install ladder。** selector/scanner/loopback discovery继续保留可复用的纯逻辑，但真实 lifecycle execution、download/install、zero-Node runtime proof 必须基于 rc.1 bundle/module contract。
  - 依赖：CUT11.1、CUT11.2。
  - 验收：至少一个 catalog-verified 第三方插件走完整 Ghost Plane zero-modification path。

## 13. CUT12：目录与 ownership 清理

- [ ] **CUT12.1：删除 `Core/Transport` 目录并完成 `Core/Remote` ownership。** HTTP/WebSocket 只作为 Remote 的私有 carrier 细节；上层模块名和 public API 不再围绕 transport组织。
  - 依赖：CUT3.1–CUT3.9、CUT5.12。
  - 验收：package target graph 不再暴露旧 transport types。

- [ ] **CUT12.2：重组 Session 目录。** 推荐 `Session/Runtime`、`Session/Projection`、薄 `NativeSessionStore`；把 journal/control/command/projection职责物理拆开。
  - 依赖：CUT5、CUT6。
  - 验收：单个 Store 文件不再承载网络 + reducer + UI local state。

- [ ] **CUT12.3：重组 Host 目录。** 至少形成 `HarnessHostProcess`、`HarnessHostController`、`HostLaunchDescriptor`、`HostAuthBootstrap`、`HostConnectionContext`、`HostCompatibility`、`HostBuildVerifier/Classifier`。
  - 依赖：CUT2。
  - 验收：process ownership、auth、version assurance、Remote composition职责可独立测试。

- [ ] **CUT12.4：重组 Settings/Models ownership。** `NativeSettingsStore`、Credential repository、ModelCatalog repository与 Onboarding coordinator 分开，Session Store 不持有 Host-wide catalog。
  - 依赖：CUT8。
  - 验收：Settings 与 Composer 可共享同一 catalog authority。

- [ ] **CUT12.5：删除所有已被新路径替代的 rc.2 production code。** 包括旧 RPC envelope carrier、SSE parser/replay fence、history pager、Tool view DTO、old bundle resolver、old version override等。
  - 依赖：CUT12.1–CUT12.4、CUT11。
  - 验收：删除不是注释/Deprecated/unused留存，而是真正从 production target 消失。

## 14. CUT13：测试与正确性验证

- [ ] **CUT13.1：Remote unary contract tests。** 对 authenticated exact rc.1 Host 验证成功、business error、HTTP/auth failure、decode failure、cancel、timeout、并发 correlation。
  - 依赖：CUT3.4、CUT1.4。

- [ ] **CUT13.2：Remote mux/logical stream tests。** 覆盖多 logical stream、dispose、carrier loss、new generation、terminal failure、malformed frame；确保 Remote 层不做 Session-specific replay。
  - 依赖：CUT3.5–CUT3.7。

- [ ] **CUT13.3：Host auth tests。** 覆盖正确 token exchange、缺/错 token、cookie authority、Host restart/new token、cookie jar 隔离、token/cookie 日志脱敏。
  - 依赖：CUT2.1–CUT2.3。

- [ ] **CUT13.4：Verified/Best-effort classification tests。** exact build 得到 verified；修改 build facts 但保持 rc.1 handshake/contract 可用时得到 Best-effort 且同一业务 API 仍可调用；缺 method/schema 时按真实错误失败且不 fallback。
  - 依赖：CUT2.6、CUT3.9。

- [ ] **CUT13.5：Session journal property/chaos tests。** 随机生成 opening cut、packed history、page prepend、live append、disconnect/reconnect/gap，验证最终 journal 与 canonical fresh replay一致。
  - 依赖：CUT5.2–CUT5.5。

- [ ] **CUT13.6：Session control chaos tests。** baseline/delta/reconnect 下 transient state 不泄漏旧 generation；queue/jobs 最终与 fresh baseline一致。
  - 依赖：CUT5.6。

- [ ] **CUT13.7：Session Runtime integration。** 真实 rc.1 Host 上完成 create/open/follow/page/prompt/cancel/queue/reconnect/session switch，验证 Host restart 后 fresh authenticated context 与新 generation。
  - 依赖：CUT5、CUT2.8。

- [ ] **CUT13.8：Workspace Runtime integration。** 真实 follow baseline + command + delta + restart；最终 Sidebar snapshot与 fresh launch一致。
  - 依赖：CUT7。

- [ ] **CUT13.9：Settings/Credentials/Models integration。** revision conflict、secret isolation、provider discovery、catalog refresh、onboarding atomic snapshot在真实 rc.1 Host完成。
  - 依赖：CUT8。

- [ ] **CUT13.10：Tool raw-event replay suite。** 使用 rc.1 raw fixture 对 terminal/read/diff/search/web/todo/question/workflow 等 projector做 deterministic snapshot；删除旧 view-carrier fixtures。
  - 依赖：CUT10。

- [ ] **CUT13.11：Ghost Plane compatibility integration。** 对 module graph、combo bundle、slot mount、scroll/event/permission bridge、profile isolation、一个真实第三方插件做完整运行态验证。
  - 依赖：CUT11。

- [ ] **CUT13.12：性能回归。** 重新测 1000-turn、10k chunks、packed history、scroll、resize、120Hz、tool output、Ghost Plane memory；关注新 RemoteMux 与 SessionJournal 是否引入 MainActor卡顿。
  - 依赖：CUT5–CUT11。

- [ ] **CUT13.13：安全复核。** launch token/cookie、secret、downloads、plugin permissions、external navigation、temp files、diagnostics、Best-effort Host 文案均重新审计。
  - 依赖：CUT2、CUT8、CUT11。

## 15. CUT14：rc.1 UI 全量重新认证

- [ ] **CUT14.1：Shell / Window / Sidebar / Columns。** 重新生成 rc.1 official/native light+dark evidence；即使代码未变化，也必须确认上游 layout/token 未漂移。
- [ ] **CUT14.2：Workspace / Session browser。** search、rename、delete、fork、archive、order、narrow rail、keyboard focus 全部重新配对。
- [ ] **CUT14.3：Conversation / Composer。** welcome、empty、streaming、process fold、system prompt、turn navigation、width、font、Markdown、images、queue/steer、connection recovery 全部重新配对。
- [ ] **CUT14.4：Tooling。** 常用 Tool Cards、details、copy、error、running/settled状态重新配对。
- [ ] **CUT14.5：Approval / Question。** keyboard、focus、submit/cancel、AX 与 rc.1 official state重新认证。
- [ ] **CUT14.6：Settings。** Root、General、Models、Credentials、Plugins、Agent Presets、Onboarding、close/Escape/focus/AX 全部重新配对。
- [ ] **CUT14.7：Plugin/Ghost Plane visible integration。** 插件 overlay/z-order/scroll/focus/permission UI 与原生红区边界重新配对。
  - 共通依赖：对应 CUT8–CUT11 功能完成、CUT1.8 scene catalog ready。
  - 共通验收：同状态、同视口、同主题、同辅助功能条件；历史 rc.2 配对只能作为回归参考，不算完成证据。

## 16. CUT15：最终 clean cut 与发布边界

- [ ] **CUT15.1：切换 App composition root。** App 启动只创建新 Host auth → Remote → Controllers → Runtimes → Stores 链；旧 transport/session composition从入口完全移除。
  - 依赖：CUT2–CUT12。

- [ ] **CUT15.2：删除 current tree 中所有 rc.2 runtime fixtures 与 active spec。** 历史资料只保存在 `TODO_LEGACY_RC2.md`、Git history 和明确 archive 目录；生产/测试默认资源只指向 rc.1。
  - 依赖：CUT1、CUT13。

- [ ] **CUT15.3：更新 README / Architecture / Plugin docs。** 文档准确描述 rc.1 Remote Gateway、browser-token auth、verified vs Best-effort、Session journal/control、Workspace follow、client-derived tool presentation、Ghost Plane combo bundle。
  - 依赖：CUT15.1。

- [ ] **CUT15.4：更新支持声明。** 明确“已验证：`0.1.2-rc.1 @ a66e470...`；其他本地 Harness 版本：Best-effort，同一协议栈尝试，不保证兼容，不做版本特化”。
  - 依赖：CUT0.2、CUT15.3。

- [ ] **CUT15.5：完成一次全量 macOS 26 release-candidate 审计。** build、XCTest、真实 Host smoke、visual/AX、performance/security、Ghost Plane integration全部在同一 rc.1 candidate上通过。
  - 依赖：CUT13、CUT14、CUT15.1。

- [ ] **CUT15.6：合并迁移分支。** 合并时 `main` 不经历双协议 release；历史版本通过 Git tag/release回滚，不通过当前二进制的兼容层回滚。
  - 依赖：CUT15.1–CUT15.5。

## 17. 迁移后继续推进的产品任务

下列工作不是“迁移税”，但在 rc.1 clean cut 完成后继续作为产品完成面推进；其旧 rc.2 代码可复用多少必须逐项经 rc.1 重新认证。

- [ ] **POST1：完成 Conversation 全官方 node 覆盖。** Markdown、安全链接、attachments/images、stats/todo/goal、subagent/trajectory/deliverables等未完成面继续推进。
- [ ] **POST2：完成 Tool renderer 全覆盖。** 在 CUT10 基础上补齐官方第一方/常见插件工具的所有状态和复杂 details。
- [ ] **POST3：完成 Settings 全页面。** Schema form、General、Models/Credentials、Plugins、Agent Presets、Onboarding达到 rc.1 官方完整功能面。
- [ ] **POST4：完成 Ghost Plane zero-modification compatibility。** 将 CUT11 的基础设施推进到真实第三方插件高覆盖，而非只做单一示例。
- [ ] **POST5：完成 Golden visual / full keyboard / VoiceOver / stress / security 发布门槛。** 继续关闭历史 TODO 中尚未完成的 T12.4–T12.7 类质量工作，但证据全部基于 rc.1。
- [ ] **POST6：发布基础设施与 notarization。** 延续原签名、公证、更新、release workflow 工作，但产品支持声明遵循 CUT15.4。

## 18. 推荐实施顺序

```text
CUT0  边界/来源
  ↓
CUT1  spec/fixtures（可先做不依赖 auth 的部分）
  ↓
CUT2  Host auth + compatibility classification
  ↓
CUT3  RemoteConnection / remote.mux
  ↓
CUT4  typed Controllers
  ↓
CUT5  Session Runtime ──┐
CUT7  Workspace Runtime ├─ 可并行
CUT8  Settings/Models   ┘
  ↓
CUT6  Projection + thin Stores
  ↓
CUT9  Conversation/ui-chat
CUT10 Tool raw projection
CUT11 Ghost Plane
  ↓
CUT12 ownership cleanup / legacy deletion
  ↓
CUT13 correctness/integration/perf/security
  ↓
CUT14 rc.1 UI re-certification
  ↓
CUT15 single cutover
  ↓
POST  remaining product parity
```

### 迁移期间最重要的禁止事项

1. 不为了“先跑起来”保留 `session.history + events.mux` 胶水层。
2. 不在 `RemoteConnection` 中理解 SessionSeq、queue/jobs、Workspace rows 或 Tool UI。
3. 不在 `SessionRuntime` 中解析 WebSocket/mux envelope。
4. 不在 `NativeSessionStore` 中重新塞回 JSON decode、分页或 reconnect merge。
5. 不让版本 classification 变成 API feature gate；Best-effort Host 仍使用同一 controller graph。
6. 不因为未知 Host 某个调用失败而尝试旧 method/旧 DTO。
7. 不让 Tool renderer继续依赖旧 Host-provided view carrier。
8. 不让 Ghost Plane保留旧 single-plugin loader作为备用。
9. 不把 rc.2 screenshot/CI/fixture 直接继承为 rc.1 完成证据。
10. 不新增专门的 legacy-ban CI gate；通过架构删除和正常测试证明 clean cut。
