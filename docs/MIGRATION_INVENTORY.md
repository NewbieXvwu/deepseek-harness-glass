# rc.1 clean-cut 迁移清单

本文件同时承担 CUT0.4 的上游 source-of-truth 清单与 CUT0.5 的当前树迁移盘点。唯一 verified 上游为 `deepseek-ai/deepseek-harness@a66e4702047846cdaa10c66c9d3df3951f5ea70d`（`dsh-v0.1.2-rc.1`）。历史 rc.2 实现和 fixture 只能提供历史线索，任何当前协议、状态机或 UI 结论都必须回链到 rc.1 源码或由 rc.1 生成的仓库资产。

迁移状态只使用三种终态：`retain-after-reaudit` 表示代码可保留，但必须由 rc.1 来源和当前行为证据重新认证；`rewrite` 表示职责仍需要，但接口、数据流或 ownership 必须按 rc.1 改写；`delete` 表示当前 production/test 默认执行面不再保留该旧实现。尚未完成的 `rewrite` 会明确写出剩余 CUT，不使用模糊的“以后再看”。

## rc.1 source-of-truth

| 领域 | rc.1 权威路径 | Glass 当前落点 | 约束 |
| --- | --- | --- | --- |
| Client connection / Host ready | `packages/client/connection/` | `glass/Sources/Core/Host/`、`glass/Sources/Core/Remote/RemoteEventRuntime.swift` | launch token 只参与 root bootstrap；后续连接使用独立 authenticated session；`$events` ready 建立 generation。 |
| Remote Gateway / mux | `packages/api/gateway/`、`packages/api/remotes/src/` | `glass/Sources/Core/Remote/` | unary 与 logical stream 共用 rc.1 Remote contract；物理流入口为 `/api/remote.mux`。 |
| Session controller | `packages/api/session-controller/` | `glass/Sources/Core/Controllers/`、`glass/Sources/Core/Session/` | follow-first journal、page frozen cut、control transient state 与 command 分离。 |
| Workspace controller | `packages/api/workspace-controller/` | `glass/Sources/Core/Controllers/`、`glass/Sources/Core/Workspace/` | `workspace.follow` opening baseline 是实时 authority，后续只接受 closed-union delta。 |
| Settings | `packages/api/settings-controller/` | `glass/Sources/Core/Controllers/`、`glass/Sources/Core/Settings/` | describe/mutate 与 revision fence 采用 rc.1 contract。 |
| Credentials | `packages/credentials/credentials/`、`packages/api/remotes/src/index.ts` | `glass/Sources/Core/Remote/DomainAPIs.swift`、Settings repositories | observable readback 只保留 configured/source/writable 等安全事实；secret 只作为瞬时写参数。 |
| LLM / provider directory | `packages/llm/llm/`、`packages/api/remotes/src/index.ts` | `glass/Sources/Core/Controllers/`、Settings model repositories | catalog 是 Host-wide state，provider discovery 由 rc.1 Remote 暴露。 |
| Conversation shell | `packages/client/ui-conversation/` | `glass/Sources/UI/Conversation/` | resident composer、pending interaction、header/slot ownership以 rc.1 当前组件为准。 |
| Chat visible renderer | `packages/client/ui-chat/` 与 `packages/client/ui-conversation/` 的当前调用边界 | `glass/Sources/UI/Conversation/`、Session projection | node assembler、消息行、running/settled 与 history navigation 必须分别回链当前 owner。 |
| Workspace UI | `packages/client/ui-workspace/` | `glass/Sources/UI/Workspace/`、`glass/Sources/UI/Sidebar/` | search、rename、archive、order、narrow rail 等行为使用 rc.1 locale/CSS/组件。 |
| Settings UI / onboarding | `packages/client/ui-settings-*` | `glass/Sources/UI/Settings/`、Settings repositories | section、provider editor、credentials、Models、Plugins、Agent Presets 与 onboarding 逐场景重新认证。 |
| Locale / theme / layout | `packages/client/locale/`、`packages/client/ui-theme/`、`packages/client/ui-layout/` | `glass/Sources/Spec/OfficialLocaleCatalog.swift`、`OfficialThemeCatalog.swift`、`OfficialUISpec.swift` | 生成器 fresh-extract，View 不新增未登记产品常量。 |
| Tool presentation | rc.1 tool owner packages及其 client-side presentation，连同 `ui-conversation` / `ui-chat` renderer | Session raw-event projector、`glass/Sources/UI/Tooling/` | typed presentation 只从 raw validated Session events 派生，旧 presenter `view` carrier 不进入当前 DTO。 |
| Plugin module graph / bundles | `packages/client/modules/`、`packages/extensions/cordis-client-runner/`、Gateway plugin bundle route | `glass/Sources/Core/Plugin/`、PluginWebHost | module graph 与 combo bundle 路径按 rc.1 profile 生成；核心原生红区不让渡渲染权。 |

## 当前树迁移盘点

| 旧/当前组件 | 状态 | 当前终态或目标归属 | 当前事实 / 剩余工作 |
| --- | --- | --- | --- |
| `DSHClientTransport` / `Core/Transport` | `delete` | `Core/Remote` | 已从 production target 删除；HTTP、mux 与 download 的认证上下文由 Remote/Host ownership 承担。 |
| `SSEClient`、旧 `events.mux` / `events.host` | `delete` | `RemoteMuxConnection` / `$events` | 旧 SSE 和旧 event endpoints 已移除。 |
| `RPCModels`、旧 `server-response` envelope | `delete` | rc.1 Remote wire models | 当前 contract 使用 rc.1 result/error 与 typed procedure。 |
| `DomainAPIs.swift` 的旧 facade 职责 | `rewrite` | `Core/Controllers` + 仅保留共享 DTO/protocol | production controller 已拆到 `Core/Controllers`；该文件仍含共享 DTO/protocol，后续 CUT4 继续收窄 ownership。 |
| protocol default `invalidEndpoint` fallback | `rewrite` | required capability 显式实现 | CUT4.6 继续清除剩余默认实现；可选能力使用真实可选类型。 |
| `SessionHistoryPager` / history→subscribe ingest | `delete` | `SessionRuntime` + `SessionJournal` | 旧 pager、旧 SSE ingest 和 `session.history` 路径已删除。 |
| Session seq / page / follow merge | `rewrite` | `Core/Session/Runtime` | follow-first、packed history、page prepend、generation ownership 已落地；CUT5/CUT13 继续完成 chaos 与真实 Host 集成验收。 |
| queue/jobs 从 durable history 推导 | `delete` | `SessionControlRuntime` | transient control fixture 与 journal fixture 已分离；可见 authority 来自 control baseline/delta。 |
| `NativeSessionStore` 持有 transport/JSON/reconnect | `rewrite` | Runtime snapshot + MainActor local UI state | transport ownership 已移出；CUT6.6/CUT6.7 继续核对 store 中剩余 Host authority 与 local draft/image 生命周期。 |
| 旧 Workspace list polling 实时性 | `delete` | `WorkspaceRuntime` + `workspace.follow` | opening baseline、`upsert/remove/order/archived` 与 generation replacement 已实现；当前 fixture replay 直接驱动 Runtime。 |
| `NativeWorkspaceStore` transport ownership | `rewrite` | WorkspaceRuntime snapshot + UI selection/dialog | CUT7.4 继续完成最终瘦身与真实 integration 认证。 |
| rc.2 Settings/Credentials/Model API shape | `rewrite` | rc.1 controllers/repositories | 当前 tree 已有 Settings、credential 与 Host-wide model repository；CUT8 继续完成 provider/onboarding/UI 全面认证。 |
| `ToolEventViewDTO`、`view`、`callView`、`resultView` | `delete` | raw-event typed projector | 已从 tracked production/tests 清除；terminal/read/diff/search/web 已 rc.1 重新认证，CUT10.6 处理剩余工具族。 |
| 旧单插件 bundle loader | `delete` | rc.1 combo bundle resolver | 已删除 `/plugins/<pluginId>/client.js` fallback；当前 resolver 按 module graph 构造 combo bundle。 |
| 旧 Ghost Plane permission/profile seam | `delete` | rc.1 module graph + 原生 broker | rc.2 虚构 adapter/profile 已清除；external-navigation 等 rc.1 实际边界保留。 |
| Attach/Adopt/Install 旧生命周期 | `rewrite` | rc.1 plugin module/bundle lifecycle | selector/scanner 可复用；真实第三方插件 zero-modification 路径仍由 CUT11.9 完成。 |
| 裸 `127.0.0.1:port` 未认证 Host probe | `delete` | authenticated launch-URL attach | 旧 loopback endpoint discovery/probe 已删除；外部 launch URL 的 auth/bootstrap/adopt 仍由 CUT2.7 完成。 |
| Host version override / unknown 写保护 | `delete` | `verified` / `bestEffort` classification | classification 只影响保证等级和诊断；同一 controller graph 不按版本分叉。 |
| rc.2 runtime fixtures / active spec | `rewrite` | rc.1 generated spec/fixtures | locale/theme/layout、Remote、Session、control、Workspace fixture 已切 rc.1；CUT1.8 与 CUT15.2 继续清理视觉/AX和默认资源中的历史证据。 |
| `glass/Sources/Spec` 手写产品常量 | `rewrite` | generated catalogs + 有来源的少量语义 alias | fresh generation 是 token/locale/layout/asset 的权威入口；手写 alias 只能消费生成结果。 |
| `glass/Tests` rc.2 行为断言 | `rewrite` | rc.1 fixture replay / behavior tests | 历史测试不能单独证明 rc.1 parity；受 contract 影响的 suite 逐项以 rc.1 fixture/真实 Host 重建。 |
| `glass/ci` 与 `.github/workflows` | `retain-after-reaudit` | contract、architecture、native-ui、release gates | 当前 macOS 26 lane fresh-build 官方基线、Release 编译、XCTest、原生架构、WindowServer snapshot 与 review bundle；不新增专用 legacy-ban gate。 |
| `glass/tools` spec/fixture generators | `retain-after-reaudit` | rc.1 fresh generators | 生成器输入锁到 exact upstream SHA；输出 drift 可回链输入路径。 |
| `glass/Sources/Spec/Fixtures` | `rewrite` | rc.1 authenticated Host / raw-event fixtures | 当前 Remote、journal、control、Workspace fixture 已重捕获；后续新增证据必须继续从隔离 Host/锁定源码生成。 |
| `docs/` 中 rc.2 当前态描述 | `rewrite` | rc.1 architecture / review docs | 本文件已清除旧 528c682/rc.8 当前态；其它文档随各 CUT 只更新其真实 owner，历史事实保留时必须标明历史身份。 |
| 核心 WebView/DOM/CSS 注入 | `delete` | 原生 SwiftUI/AppKit | WebKit 只允许存在于隔离 PluginWebHost / Ghost Plane 绿区；D0 运行态隔离测试持续约束核心 view tree。 |

## clean-cut 执行规则

当前二进制只表达 rc.1 语义。禁止按 Host 版本选择另一套 endpoint、DTO、decoder 或状态机；禁止 404 后尝试旧 API；禁止为历史 fixture 保留 compatibility typealias/deprecated wrapper；Remote carrier 重连可以重建 physical connection 和 generation，但不会自动重放业务 mutation。回滚通过 Git commit/release 完成。

`SupportedHostBuilds.json` 的唯一 exact rc.1 条目在 macOS 26 fresh spec/fixture、Release build、全量 XCTest、架构门禁和 WindowServer snapshot 流程通过后标为 `verified`。未知本地 Harness 只有在完成当前 rc.1 认证与 Remote handshake 后才进入 `bestEffort`，其真实 method/schema failure 保持原始分类。
