# rc.1 source-of-truth ledger

Verified upstream baseline:
`deepseek-ai/deepseek-harness@a66e4702047846cdaa10c66c9d3df3951f5ea70d`
(`dsh-v0.1.2-rc.1`). Every path below is read at that commit.
Historical rc.2 notes may explain prior Glass behavior, but they are not inputs for new contracts.

| Surface | Canonical upstream paths | Glass responsibility |
|---|---|---|
| Browser connection and auth | `packages/client/connection/src/browser-auth.ts`, `src/rpc-host.ts`, `src/client/rpc.ts`, `src/client/connection.ts`, `README.md` | Launch-token bootstrap, persistent authority-bound cookie, generic HTTP RPC envelope, connection generation semantics. |
| API Gateway / Remote | `packages/api/gateway/src/index.ts`, `src/types.ts`, `src/stream-protocol.ts`, `src/stream-server.ts`, `src/client/remote-stream.ts`, `src/client/journal-stream.ts`, `src/client/snapshot-stream.ts` | `/api/<endpoint>` unary dispatch, `/api/remote.mux` logical streams, `$events` ready generation, stable Remote failures. |
| Session controller | `packages/api/session-controller/src/index.ts`, `src/types.ts`, `src/history.ts`, `src/control.ts`, `src/list.ts`, `src/commands.ts`, `src/client/transport.ts`, `src/client/contract/`, `src/client/sessions/` | Session list/search/create, page/follow/control, addressing, commands, packed history and client-side session projection rules. |
| Workspace controller | `packages/api/workspace-controller/src/index.ts`, `src/types.ts`, `src/feed.ts`, `src/commands.ts`, `src/client/model.ts` | Workspace commands and reconnect-safe `workspace.follow` baseline/delta stream. |
| Settings and credentials | `packages/api/settings-controller/src/index.ts`, `src/credentials.ts`, `src/types.ts`; `packages/client/ui-settings/src/client/` | Settings revision/schema/value contract, credential describe/set/unset and client settings mirror behavior. |
| Models and onboarding | `packages/client/ui-settings-models/src/client/`, `packages/client/ui-model-selection/src/client/`, `packages/core/agent-default-model/`, Remote owners referenced by generated client descriptors | Provider configuration, catalog/discovery, model selection, onboarding readiness and visible model UI behavior. |
| Tool presentation | `packages/core/agent-tool-presentation/`, `packages/client/ui-tool/src/client/`, tool-specific client packages and their tests | Raw tool-event interpretation and native presentation. No rc.2 presenter-view DTO is authoritative. |
| Conversation assembly | `packages/client/ui-conversation/src/client/`, especially `service.ts`, `stores.ts`, `view-selection.ts`, `skeleton/`, `input/`, `queue/` | Conversation shell, composer, queue/steer behavior, context meter and view ownership. |
| Chat transcript | `packages/client/ui-chat/src/client/`, especially `transcript-view.ts`, `stores.ts`, `chat/`, `settings/` | User/assistant rows, process/system folding, turn metrics/navigation, content width, font and Markdown behavior. |
| Plugin module graph and bundles | `packages/client/modules/`, loader/module graph code reached from client web bootstrap, Host web-server plugin bundle routes, package tests containing `/plugins/??` | Enabled module graph, dependency ordering, combo bundle URL semantics and bootstrap/app bundle sets. |
| Plugin slots / Ghost Plane contract | Slot registry declarations in client UI packages, `packages/client/ui-conversation/`, `packages/client/ui-chat/`, plugin package entry metadata and tests | Slot ownership, native red/green boundary, skeleton anchors and compatible plugin mounting. |
| Locales | Every `packages/client/**/locales.ts` plus locale package resources; extraction entrypoints already listed in generated locale provenance | All visible product text and locale identifiers. |
| Theme | `packages/client/ui-theme/src/styles/`, `src/theme-settings.ts`, component `*.module.css` files | Semantic color/type/material tokens. Generated Glass tokens record exact source paths and hashes. |
| Layout | `packages/client/ui-layout/src/client/`, `packages/client/ui-sidebar/`, `packages/client/ui-conversation/src/client/skeleton/`, `packages/client/ui-chat/src/client/chat/`, component CSS modules | Window/column/sidebar/conversation geometry and responsive rules. |
| Official assets | Source SVG/icon components referenced by `tools/spec-generation/extract_official_assets.ts` and `extract_official_icon_ast.mjs` | Wordmark, fish logo and registered icons with source hash provenance. |

## Remote wire invariants

The browser auth contract allows the process token only on `GET /` during bootstrap.
Successful exchange sets the Host's signed browser cookie and redirects to a clean root URL.
RPC and WebSocket requests then rely on that authenticated cookie context.
Query-token and Authorization-token reuse are not rc.1 protocol paths.

Unary calls POST a `client-request` envelope to `/api/<endpoint>`.
The endpoint string in the path and envelope must match. Success and business failure return the correlated `server-response` envelope.
Remote stream traffic uses the single `/api/remote.mux` WebSocket. Logical streams send `open` / `cancel` messages keyed by `streamId`.
Host frames are `item` / `error` / `end`. The Gateway-owned `$events` logical stream must yield its `ready` item before Glass publishes a connection generation.

Session durable history and transient control are separate authorities.
`session.follow` owns the opening journal cut plus live durable append. `session.page` reads older history relative to the frozen cut.
`session.control` owns queue/jobs/transient state. Workspace realtime state comes from `workspace.follow`, whose replacement baseline begins each new generation.

## Update rule

A Glass contract, fixture, source note, generated spec or visual baseline is current only when its provenance points to the commit above
and one of the canonical paths in this ledger. If upstream ownership moves, update this ledger first, then regenerate or rewrite the dependent Glass artifact.
Do not bridge a path move with an rc.2 fallback.
