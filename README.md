# DeepSeek Harness Glass

A native macOS shell for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) —
**the dsh you know, in a real Liquid Glass window.**

DeepSeek Harness Glass wraps the official `dsh` engine and its web UI into a
self-contained macOS app. Instead of an Electron or Tauri wrapper, the shell is
a small SwiftUI program that puts the entire window on Apple's public
[`glassEffect`](https://developer.apple.com/documentation/swiftui/glasseffect(_:in:))
material. The result is the same edge refraction, lensing, and layered
materials Apple's own macOS 26 apps use — not a CSS approximation.

- **Chinese README:** [README.zh.md](README.zh.md)

## Requirements

- macOS 26 or later (Liquid Glass is a Tahoe-era API)
- Apple Silicon (arm64)

## Installation

Download `DeepSeek Harness Glass-<version>.dmg` from
[Releases](https://github.com/qniequn-boop/deepseek-harness-glass/releases),
open it, and drag the app into **Applications**.

The build is ad-hoc signed and not notarized. On first launch, macOS shows an
"unidentified developer" prompt: **right-click the app → Open**, then confirm.
This is required once.

On first run, open **Settings** in the app and enter your own DeepSeek API
key. The app stores its data in `~/.dsh`, the same home directory the dsh CLI
uses, so existing sessions, profiles, and `cordis.patch.yml` patches are
picked up automatically.

## Features

- **Real Liquid Glass** — the window background is the native `glassEffect`
  material. Edge optics, corner treatment, and refraction are rendered by the
  system, identically to first-party macOS 26 applications.
- **Full-window glass** — the glass extends into the title bar area
  (`fullSizeContentView` + a zero-safe-area hosting view), so there is no
  unglazed strip at the top.
- **Self-contained** — Node.js v24 and the complete dsh backend payload
  (`@deepseek-ai/dsh`, `@deepseek-ai/dsh-web-frontend`, pinned by exact
  version) are bundled. No Node.js installation and no runtime downloads.
- **Shared harness state** — `DSH_HOME` defaults to `~/.dsh`; credentials,
  sessions, settings, and installed plugins are identical to the CLI.
  An explicit `DSH_HOME` environment variable overrides it.
- **Dynamic text contrast** — the shell samples the desktop wallpaper's
  average luminance at launch and on wallpaper change, and chooses a light or
  dark text palette with hysteresis. Dragging the window never flips the
  colors (Apple's own guidance: large surfaces should not flip).
- **Layered frosting** — the composer, popovers, menus, and hover cards carry
  per-layer translucent tints and a `backdrop-filter` sweep, so elevated
  surfaces read as glass stacked on glass.
- **Clean lifecycle** — quitting, closing the window, or killing the process
  all terminate the embedded backend; no orphan processes.

## How it works

```
DeepSeek Harness.app
└── Contents/
    ├── MacOS/DeepSeek Harness        ← Swift shell (glass/Sources/main.swift)
    └── Resources/
        ├── node/node                 ← bundled Node.js v24 (official binary)
        └── backend/node_modules/     ← pinned dsh engine + web frontend
```

1. The shell spawns the bundled Node:
   `node --expose-internals …/@deepseek-ai/dsh/lib/bin.js web --port 0`
   (`--expose-internals` is required by the dsh web profile's HMR service).
2. It parses the `dsh web: http://127.0.0.1:<port>` line from stdout and loads
   that URL into a transparent `WKWebView`. The port is ephemeral and bound to
   loopback only; nothing is exposed to the network.
3. A `WKUserScript` injects `GLASS_CSS`, which re-tints the dsh design tokens
   (`--dsw-alias-*`) — the frontend's own theming extension point — so the
   whole UI becomes translucent without touching dsh source.
4. The native glass material sits behind the transparent web content.

## Building from source

Prerequisites: Xcode Command Line Tools (`swiftc`), `npm`, and an internet
connection for the two downloads below.

```sh
# 1. Bundled Node runtime (official binary, pinned)
mkdir -p glass/build/node
curl -fsSL https://nodejs.org/dist/v24.19.0/node-v24.19.0-darwin-arm64.tar.gz -o /tmp/node.tgz
tar -xzf /tmp/node.tgz -C /tmp
cp /tmp/node-v24.19.0-darwin-arm64/bin/node glass/build/node/node

# 2. Backend payload (pinned npm packages) + smoke test + assemble
cd glass
./repair-backend.sh
```

The app is written to `/Applications/DeepSeek Harness.app` by default.
Set `APP_PATH` to build elsewhere:

```sh
APP_PATH="$PWD/dist/DeepSeek Harness.app" ./assemble.sh
```

Create the installer image:

```sh
mkdir -p dmg-stage && cp -R "/Applications/DeepSeek Harness.app" dmg-stage/
ln -s /Applications dmg-stage/Applications
hdiutil create -volname "DeepSeek Harness Glass" -srcfolder dmg-stage \
  -ov -format UDZO "dist/DeepSeek Harness Glass-0.3.0.dmg"
```

A `v*` tag pushed to GitHub triggers `.github/workflows/release.yml`, which
performs all of the above and attaches the DMG to a Release.

## Troubleshooting

**"DeepSeek Harness 启动失败（code 1）"** — the embedded backend payload is
missing packages. Run:

```sh
cd glass && ./repair-backend.sh
```

This reinstalls the payload from npm with exact pins, smoke-tests the backend,
and repackages the app.

**App and CLI cannot run at the same time** — both use `~/.dsh`. Point the
app at a different `DSH_HOME` if you need both.

## Project layout

```
glass/
  Sources/main.swift     the entire shell (~700 lines, the only custom code)
  assemble.sh            build + ad-hoc sign + atomic replace
  repair-backend.sh      one-shot payload reinstall + smoke test + repackage
  Info.plist             bundle metadata (LSMinimumSystemVersion 26.0)
build/icon.icns          app icon, derived from the dsh whale favicon
```

## Design notes

The window is `isOpaque = false` with a clear background so the glass material
can refract the desktop behind it. Web content deliberately cannot sample
what is behind a window (a platform privacy boundary), so the elevated
surfaces use layered tints plus `backdrop-filter` over the page's own content
rather than a second native blur pass. Text tokens are kept solid to avoid
backdrop color bleeding through glyphs, with a 0.5% white underlay and
antialiased font smoothing.

## Disclaimer

This is an independent, unofficial wrapper around the open-source
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) project.
It is not affiliated with or endorsed by DeepSeek. "DeepSeek" and related
marks belong to their respective owners.

## License

MIT — see [LICENSE](LICENSE). Bundled components are covered separately in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
