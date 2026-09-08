# rc.1 source-of-truth ledger

Verified upstream baseline:
`deepseek-ai/deepseek-harness@a66e4702047846cdaa10c66c9d3df3951f5ea70d`
(`dsh-v0.1.2-rc.1`). Every path below is read at that commit.
Historical rc.2 notes may explain prior Glass behavior, but they are not inputs for new contracts.

| Surface | Canonical upstream paths | Glass responsibility |
|---|---|---|
| Browser connection and auth | `packages/client/connection/src/browser-auth.ts`, `src/api-request-trust.ts`, `src/http-bridge.ts`, `src/rpc-host.ts`, `src/client/index.ts`, `src/client/rpc.ts`, `src/client/connection.ts`, `README.md` | Launch-token bootstrap, authority-bound browser cookie, HTTP RPC carrier and connection-generation semantics. |
| API Gateway / Remote | `packages/api/gateway/src/index.ts`, `src/types.ts`, `src/stream-protocol.ts`, `src/stream-server.ts`, `src/client/index.ts`, `src/client/remote-events.ts`, `src/client/remote-stream.ts`, `src/client/journal-stream.ts`, `src/client/snapshot-stream.ts`; `packages/api/remotes/src/index.ts`, `src/client/index.ts`, `src/remote-events.ts`, `src/types.ts` | `/api/<endpoint>` unary dispatch, `/api/remote.mux` logical streams, `$events` ready generation, `$host` facts and stable Remote failures. |
| Session controller | `packages/api/session-controller/src/index.ts`, `src/types.ts`, `src/history.ts`, `src/control.ts`, `src/list.ts`, `src/commands.ts`, `src/file-references.ts`, `src/skill-catalog.ts`, `src/client/transport.ts`, `src/client/contract/`, `src/client/sessions/` | Session list/search/create, page/follow/control, addressing, commands, packed history and client-side session projection rules. |
| Workspace controller | `packages/api/workspace-controller/src/index.ts`, `src/types.ts`, `src/feed.ts`, `src/commands.ts`, `src/directory-picker.ts`, `src/client/index.ts`, `src/client/model.ts`, `src/client/service.ts` | Workspace commands and reconnect-safe `workspace.follow` baseline/delta stream. |
| Settings and credentials | `packages/api/settings-controller/src/index.ts`, `src/credentials.ts`, `src/types.ts`; `packages/client/ui-settings/src/client/`, `packages/client/ui-settings-general/src/client/` | Settings revision/schema/value contract, credential describe/set/unset, settings shell and client mirror behavior. |
| LLM, models and onboarding | `packages/llm/llm/src/index.ts`; `packages/core/agent-default-model/src/index.ts`; `packages/client/ui-settings-models/src/client/`; `packages/client/ui-model-selection/src/client/` | LLM Remote owner, provider configuration, model catalog/selection and onboarding readiness. |
| Commands, subagents and feedback | `packages/interaction/commands/src/index.ts`; `packages/subagent/subagent/src/index.ts`; `packages/feedback/message-feedback/src/index.ts` | Current Remote owners for command, subagent and message-feedback surfaces consumed by Glass. |
| Tool presentation | `packages/core/agent-tool-presentation/src/index.ts`; `packages/client/ui-tool/src/client/tool/`, especially `models/`, `toolviews/`, `ToolCallTree.tsx`, `ToolDetails.tsx` | Raw tool-event interpretation and native presentation. No rc.2 presenter-view DTO is authoritative. |
| Conversation assembly | `packages/client/ui-conversation/src/client/apply.ts`, `service.ts`, `stores.ts`, `view-selection.ts`, `contract/`, `conversation/`, `skeleton/`, `input/`, `queue/` | Conversation shell, composer, queue/steer behavior, context meter, definitions and view ownership. |
| Chat transcript | `packages/client/ui-chat/src/client/apply.ts`, `transcript-view.ts`, `stores.ts`, `contract/`, `conversation-nodes/`, `chat/`, `details/`, `settings/` | User/assistant rows, process/system folding, turn metrics/navigation, tool seating, content width, font and Markdown behavior. |
| Client module graph and combo bundles | `packages/client/modules/src/index.ts`, `src/invariant.ts`, `src/client/index.ts`, `src/client/manifest.ts`, `src/client/system.ts`, `README.md`; `packages/host/webserver/src/index.ts`, `src/injections.ts`; `apps/web/src/`, `apps/web/vite.config.ts` | Enabled module graph, dependency ordering, `/plugins/??...&rev=...` combo URLs, immutable bundle responses, bootstrap injections and app bundle sets. |
| Plugin slots / Ghost Plane contract | Slot declarations under `packages/client/ui-conversation/src/client/contract/slots.ts`, `packages/client/ui-chat/src/client/contract/slots.ts`, `packages/client/ui-tool/src/client/contract/slots.ts`, `packages/client/ui-workspace/src/client/contract/slots.ts`, plus package `dsh.client` manifests | Slot ownership, native red/green boundary, skeleton anchors and compatible plugin mounting. |
| Locales | `packages/client/locale/src/locales/en.ts`, `src/locales/zh.ts`, `src/locales/index.ts`, plus feature-owned `src/client/locales.ts` / `src/client/locale.ts` files | All visible product text and locale identifiers. |
| Theme | `packages/client/ui-theme/src/styles/`, `src/theme-settings.ts`, `src/client/styles.ts`, component `*.module.css` files | Semantic color/type/material tokens and component styling. Generated Glass tokens record exact source provenance. |
| Layout | `packages/client/ui-layout/src/client/AppFrame.tsx`, `columns.ts`, `service.ts`, `stores.ts`, `theme-presenter.ts`; `packages/client/ui-sidebar/src/client/SidebarRoot.tsx`; `packages/client/ui-conversation/src/client/skeleton/`; `packages/client/ui-chat/src/client/chat/` | Window/column/sidebar/conversation geometry, material ownership and responsive rules. |
| Official assets | Source SVG/icon components reached by `tools/spec-generation/extract_official_assets.ts` and `extract_official_icon_ast.mjs` | Wordmark, fish logo and registered icons with source provenance. |

## Remote wire invariants

The browser auth contract allows the process token only on `GET /` during bootstrap.
Successful exchange sets the Host's signed browser cookie and redirects to a clean root URL.
RPC and WebSocket requests then rely on that authenticated cookie context.
Query-token and Authorization-token reuse are not rc.1 protocol paths.

Unary calls POST a `client-request` envelope to `/api/<endpoint>`.
The endpoint string in the path and envelope must match. Success and business failure return the correlated `server-response` envelope.
Remote stream traffic uses the single `/api/remote.mux` WebSocket. Logical streams send `open` / `cancel` messages keyed by `streamId`.
Host frames are `item` / `error` / `end`. The Gateway-owned `$events` logical stream must yield its `ready` item before Glass publishes a connection generation.
The rc.1 `$host` facts are exactly `home` and `isLoopback`; they do not carry package version, source commit or web-frontend version.

Session durable history and transient control are separate authorities.
`session.follow` owns the opening journal cut plus live durable append. `session.page` reads older history relative to the frozen cut.
`session.control` owns queue/jobs/transient state. Workspace realtime state comes from `workspace.follow`, whose replacement baseline begins each new generation.

## Closed-path ledger

At the pinned rc.1 commit, `packages/api/remotes/src/remote-access.ts`, `packages/api/remotes/src/config.ts` and `packages/api/remotes/src/connections.ts` do not exist. They must not appear in new Glass provenance or compatibility code. The Remote assembly is owned by `packages/api/remotes/src/index.ts` and `src/client/index.ts`, with transport and Host facts owned by API Gateway.

## Update rule

A Glass contract, fixture, source note, generated spec or visual baseline is current only when its provenance points to the commit above
and one of the canonical paths in this ledger. If upstream ownership moves, update this ledger first, then regenerate or rewrite the dependent Glass artifact.
Do not bridge a path move with an rc.2 fallback.
