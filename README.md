# DeepSeek Harness Glass

A **native macOS client** for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness). This repository preserves the DeepSeek Harness Host and replaces the official Browser Client with a Swift 6 implementation built from **SwiftUI and AppKit**.

> **Project direction.** This is not a CSS restyle and not a webpage wrapper. The locked official WebUI is the product specification for text, ordering, layout, state transitions, errors, and interaction semantics. Liquid Glass is restricted to the macOS navigation and control layer; it must not invent product content or conceal a mismatch with the official client.

- **中文文档：** [README.zh.md](README.zh.md)
- **贡献规则与验收协议：** [CONTRIBUTING.md](CONTRIBUTING.md)
- **Authoritative implementation checklist:** [TODO.md](TODO.md)

## Supported baseline

| Item | Fixed support value |
|---|---|
| Official source | [`deepseek-ai/deepseek-harness@99f6f02fecdb7dff40c3fbc9470f5907c29f74ca`](https://github.com/deepseek-ai/deepseek-harness/tree/99f6f02fecdb7dff40c3fbc9470f5907c29f74ca) |
| Supported DSH package | `@deepseek-ai/dsh` and `@deepseek-ai/dsh-web-frontend` `0.1.0-rc.6` |
| Runtime | Node `24.19.0` bundled with the application |
| Client platform | macOS 26+, Xcode 26+, Apple Silicon, Swift 6 |
| Support record | `glass/Sources/Spec/SupportedHostBuilds.json` |

The supported Host build is verified at launch. A Host not present in the support record is **unverified** and must not be treated as a compatible write target. A Host update follows the upgrade gate in `TODO.md`; it is never accepted solely because it starts on a loopback port.

## D0–D5: non-negotiable completion rules

| Rule | Requirement | Verifiable fact |
|---|---|---|
| **D0 — native core UI** | Conversation, sidebar, workspace, official settings, models, credentials, tools, approvals, questions, commands, and plugin configuration are native. | Core targets contain no `WebKit`, `WKWebView`, web JavaScript, CSS injection, or DOM inspection. CI runs `glass/ci/check-no-webview.sh`. |
| **D1 — official UI reproduction** | Official locale text, structure, spacing, state and interaction scenarios are the specification. | Every SwiftUI surface maps to `OfficialUISpec`, a locked source location, and a same-state official/native visual record. |
| **D2 — Host is the source of truth** | Durable sessions, workspaces, settings, credentials, models, commands, and plugin configuration belong to the Host. | Native state uses typed loopback RPC/SSE DTOs and does not create a conflicting business database. |
| **D3 — system-respecting Liquid Glass** | Glass belongs to navigation, split structure, toolbars, sheets, popovers, inspectors, and necessary official controls. | Content layers are not covered with custom glass; accessibility and system appearance preferences are exercised in CI. |
| **D4 — explicit plugin compatibility** | Every plugin has a declared native-manifest, Swift-adapter, web-fallback, host-only, or unsupported status. | The diagnostics/compatibility matrix records support level, Host range, and any fallback reason. |
| **D5 — verified Host writes only** | An unverified Host must not masquerade as compatible. | Unsupported builds are visibly unverified and have writes blocked unless an explicit developer policy permits them. |

`WebKit` may exist only in the future, separately built `Plugins/PluginWebHost` exception for a specifically audited, technically non-nativeable third-party plugin. The main application target and every core renderer may never import or link it.

## Architecture

```text
DeepSeek Harness.app
├── App/                   application lifecycle, window and menu-bar coordination
├── Core/
│   ├── Host/              bundled Node/DSH lifecycle and build verification
│   ├── Transport/         typed HTTP RPC, SSE, DTOs, cancellation and tracing
│   ├── Session/           history, projections, reducers and reconnect authority
│   └── Settings/          Host-backed drafts, revisions and credentials boundary
├── Spec/                  official locale, token, layout, asset and fixture provenance
├── UI/                    native shell, sidebar, workspace, conversation, tooling and settings
├── Plugins/               native manifest/adapters; isolated fallback only when approved
└── Tests/                 contract, reducer, snapshot, accessibility and performance evidence
```

The client layers flow one way: **Host → typed transport → domain facade/store/reducer → native UI**. A View never starts Node, constructs a URL, parses untyped JSON, or interprets raw SSE business events.

## Visual and interaction fidelity protocol

For every UI state, contributors first inspect the locked official source and capture the official WebUI under the same fixture, viewport, device-pixel ratio, locale, color mode, and accessibility options. The native view is then rendered under the same conditions. Both screenshots, layout/tree measurements, token differences, enlarged critical regions, and the resolution of every observable difference are retained as CI artifacts.

This project does not hide differences behind a full-window blur, a different viewport, a different state, or an anti-aliasing explanation. The application uses macOS system material for its dynamic optical behavior; that system effect is reviewed by hierarchy, position, contrast, and accessibility rather than by pretending to reproduce browser CSS refraction pixel-for-pixel.

## Current verified status

The authoritative state is maintained in the **“current progress”** section of [TODO.md](TODO.md). At the time of this document revision, only items whose source mapping, implementation, tests, visual evidence, and applicable macOS GitHub Actions evidence are complete may be checked. A compiled screen, a static fixture, or a partial DTO is not sufficient.

## Development and verification

The macOS application is assembled from `glass/assemble.sh`. The CI workflow runs on `macos-26`, downloads the pinned Node runtime and DSH payload, verifies the D0 rule and official specification provenance, builds the application, captures native GUI snapshots, and uploads review artifacts. Full development requirements, source mapping conventions, test gates, screenshot pairings, and the only permitted TODO update process are documented in [CONTRIBUTING.md](CONTRIBUTING.md).

Before changing any official-facing behavior, run the applicable local checks:

```bash
python3 glass/ci/check-official-spec.py
bash glass/ci/check-no-webview.sh
```

The required acceptance evidence remains the GitHub Actions run for the **current commit**, including the native screenshot bundle and its official comparison record.

## License and attribution

This is an independent client for the open-source [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) project. It is not affiliated with or endorsed by DeepSeek. The project is licensed under [MIT](LICENSE); bundled components are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
