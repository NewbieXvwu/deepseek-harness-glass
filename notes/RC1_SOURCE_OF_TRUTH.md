# rc.1 implementation reference

This file is a developer map for the rc.1 behavior implemented by Glass. The current research snapshot is DeepSeek Harness `dsh-v0.1.2-rc.1`; generation and CI scripts may pin an exact upstream revision so results can be reproduced.

That revision is evidence for development work only. Glass does not use repository ownership, Git identity, source commit or a package provenance label to decide whether a Host may connect, read, write or expose plugin capabilities. Runtime compatibility is determined by authentication and the actual Remote/browser contracts exercised at runtime.

## Upstream areas

| Area | Useful upstream paths | Glass responsibility |
| --- | --- | --- |
| Browser connection/auth | `packages/client/connection/src/` | Process-token bootstrap, authority cookie and connection lifecycle. |
| API Gateway / Remote | `packages/api/gateway/src/`, `packages/api/remotes/src/` | Unary Remote calls, `/api/remote.mux`, `$events` readiness and stable Remote failures. |
| Sessions | `packages/api/session-controller/src/` | Session discovery, page/follow/control, commands, addressing and projection behavior. |
| Workspaces | `packages/api/workspace-controller/src/` | Workspace commands and reconnect-safe `workspace.follow`. |
| Settings / credentials | `packages/api/settings-controller/src/` | Settings revision/schema/value operations and write-only credential mutations. |
| Models / providers | `packages/llm/llm/src/`, client model/settings packages | Host model catalog, provider settings and session model selection. |
| Commands / subagents / feedback | interaction, subagent and feedback packages | Typed Remote owners for those product surfaces. |
| Conversation / chat | `packages/client/ui-conversation/src/`, `packages/client/ui-chat/src/` | Conversation state, composer, transcript, tool seating, layout and user-visible interaction semantics. |
| Client modules / plugin bundles | `packages/client/modules/src/`, `packages/host/webserver/src/`, Cordis client runner | Host-provided module graph, combo bundle routes and plugin browser lifecycle. |
| UI reference data | locale, theme, layout and component packages | Product text, semantic tokens, geometry and assets used by the native UI. |

The paths are navigation aids, not a registry that must be kept byte-for-byte synchronized with upstream file organization. When upstream code moves, follow the behavior to its new owner and update a generator or implementation only when the consumed contract changes.

## Remote wire facts

The process token is used for the initial root bootstrap. A successful exchange establishes the Host browser authentication context and redirects to a clean root URL. Subsequent Remote HTTP, mux and download traffic uses the authenticated session; Glass does not turn the launch token into a durable application credential.

Unary calls use the rc.1 Remote request/response envelope. Logical streams share `/api/remote.mux`; `$events` must publish its ready item before Glass exposes a new connection generation.

Session durable history and transient control have separate owners. `session.follow` owns the opening journal cut plus live durable append, while `session.page` reads older history. `session.control` owns queue/jobs/transient state. Workspace realtime state comes from `workspace.follow`, whose opening value replaces the previous generation baseline.

The Host facts available through rc.1 readiness do not provide a meaningful Git/package identity for compatibility decisions. Glass therefore does not infer trust from source provenance.

## Plugin boundary

Third-party client modules are admitted from the actual Host module graph and loopback resource URLs. The native/WebKit boundary is described in `docs/PLUGIN_COMPATIBILITY_PROPOSAL.md`. Git commit equality is not a plugin capability or execution permit.

## How to use this reference

Use upstream source when behavior is ambiguous, and keep reproducible revision information in the generation/test tooling that needs it. Production code should validate external data at the boundary where that data matters. Do not add runtime or CI checks whose only evidence is that one repository-authored metadata value agrees with another repository-authored metadata value.
