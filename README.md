# DeepSeek Harness Glass

A native macOS client for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) — the dsh you know, in a real glass window.

This repository is a fork of [qniequn-boop/deepseek-harness-glass](https://github.com/qniequn-boop/deepseek-harness-glass). The upstream project wrapped the official web UI in a glass window; this fork replaces the browser client entirely, reimplementing it in Swift 6 with SwiftUI and AppKit while keeping the official Host as the backend. Core native surfaces are checked in macOS CI by mounting real views and recursively asserting that their `NSView` trees contain no `WKWebView`; the test includes a real injected-WebView negative control. Third-party plugins are targeted for full compatibility via the Ghost Plane runtime (a transparent shared Web plane carrying the official module table, slot registry, and a geometry-exact ghost DOM, so unmodified plugin clients mount at their intended anchors) with native Manifest/Adapter as an opt-in fast lane; see [docs/PLUGIN_COMPATIBILITY_PROPOSAL.md](docs/PLUGIN_COMPATIBILITY_PROPOSAL.md).

- **中文文档：** [README.zh.md](README.zh.md)

## Status

Work in progress. Done so far: the app shell (window, menu bar, and a split layout matching the official column algorithm), Host lifecycle with build verification and diagnostics, typed RPC/SSE transport with fixtures recorded from the locked official build, session state (history pager, projection store, queue/jobs), workspace management dialogs, the welcome screen, and an accessibility baseline. Still ahead: the full conversation surface, tooling details, settings pages, and plugin support.

Progress is tracked task by task in [TODO.md](TODO.md); the working rules are in [CONTRIBUTING.md](CONTRIBUTING.md).

## Baseline

| Item | Value |
|---|---|
| Official source | [`deepseek-ai/deepseek-harness@b150a55`](https://github.com/deepseek-ai/deepseek-harness/tree/b150a551b8d465e31e418e1b2eaf5e79bbb7d28e) |
| DSH packages | `@deepseek-ai/dsh` / `@deepseek-ai/dsh-web-frontend` `0.1.1-rc.2` |
| Runtime | Node `24.19.0`, bundled with the app |
| Platform | macOS 26+, Apple Silicon; Xcode 26+ and Swift 6 to build |

The app verifies the Host build against `glass/Sources/Spec/SupportedHostBuilds.json` at launch. An unknown build is shown as unverified and stays read-only until it is verified.

## How it works

The app bundles the pinned Node runtime and the locked DSH payload, starts `dsh web --port 0` on loopback, and talks to it over typed HTTP RPC and SSE. All durable state — sessions, workspaces, settings, credentials, models — lives in the Host; the native side renders it and sends user intent back.

Visible text, colors, spacing, and column geometry come from `OfficialUISpec`, which is generated from the locked official source (locales, theme tokens, `columns.ts` fixtures, interaction scenes, RPC contracts) and regenerated in CI to catch drift. Liquid Glass stays on the navigation and control layer; content surfaces use system materials.

```text
glass/
├── Sources/
│   ├── App/        lifecycle, window, menu bar
│   ├── Core/       Host process, transport, session state, settings
│   ├── Spec/       generated official spec and fixtures
│   ├── UI/         native shell, sidebar, workspace, conversation
│   └── Snapshot/   CI snapshot exporter
└── Tests/          contract, reducer, snapshot, accessibility tests
```

## Visual verification

Every migrated UI state is compared against the official WebUI captured from the locked source under the same fixture, viewport, DPR, locale, and color mode. CI on `macos-26` builds the app, captures native snapshots, runs `glass/ci/compare_visual_pair.py` against the official captures, and uploads both images plus a metrics report as artifacts. The system-material bands (sidebar/inspector) are excluded from pixel diffing via `--column-fixtures` and verified structurally instead; scenes graduate from `report-only` to `enforce` in `visual-validation-policy.json` after a human review of the measured numbers.

## Building

Prerequisites: Xcode 26+ command line tools, npm, and network access for the two downloads below.

```sh
# 1. Bundled Node runtime (pinned)
mkdir -p glass/build/node
curl -fsSL https://nodejs.org/dist/v24.19.0/node-v24.19.0-darwin-arm64.tar.gz -o /tmp/node.tgz
tar -xzf /tmp/node.tgz -C /tmp
cp /tmp/node-v24.19.0-darwin-arm64/bin/node glass/build/node/node

# 2. Backend payload + assemble
cd glass
./repair-backend.sh        # installs the pinned dsh payload and smoke-tests it
./assemble.sh              # builds, ad-hoc signs, installs the .app
```

`assemble.sh` writes to `/Applications/DeepSeek Harness.app` by default; set `APP_PATH` to build elsewhere. The authoritative recipe is the CI workflow [`.github/workflows/native-ui.yml`](.github/workflows/native-ui.yml), which also runs the full gate suite: spec/locale/token/layout/contract checks, `swift build`, the XCTest suites, app assembly, snapshot capture, and the official/native visual comparison.

## Signing and distribution

Local and open-source builds use a valid **Ad-hoc signature** by default and do not require an Apple Developer certificate. To build with an installed Developer ID Application identity, set `CODESIGN_IDENTITY` before running `assemble.sh`; that path enables Hardened Runtime and a trusted timestamp. The release workflow can use the same identity on a provisioned macOS runner and publishes both DMG and ZIP artifacts.

An Ad-hoc community build may be quarantined by Gatekeeper. After verifying the download and repository provenance, open it from Finder with **Control-click → Open**, then confirm the system prompt. Do not disable Gatekeeper globally, and do not use this instruction to bypass warnings for an unverified download.

Useful local checks before changing official-facing behavior:

```bash
python3 glass/ci/check-official-spec.py
python3 glass/ci/test-package-target-graph.py
```

## License and attribution

MIT — see [LICENSE](LICENSE). Bundled components are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). This is an independent client for the open-source DeepSeek Harness project and is not affiliated with or endorsed by DeepSeek.
