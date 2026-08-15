# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-08-15

### Added

- Port reuse: if a dsh instance is already serving on 127.0.0.1:3080, the
  app attaches to it instead of spawning a second backend.
- Crash recovery: the embedded backend is restarted once automatically
  (0.6 s delay); a second consecutive failure shows a retry page with the
  log path.
- Menu-bar tray with show / open-in-browser / restart-backend / open-home /
  open-log / quit actions; closing the window hides it instead of quitting.
- Harness menu: restart backend and open-in-browser entries.

### Changed

- The shell only terminates a backend it spawned itself; an externally
  reused instance is never killed on quit.
## [0.3.0] - 2026-08-15

### Added

- Native SwiftUI shell with a real Liquid Glass window
  (public `glassEffect` API, macOS 26+).
- Full-window glass: `fullSizeContentView` plus a zero-safe-area hosting view,
  so the glass reaches the window's top edge.
- Dynamic text contrast: the shell samples the desktop wallpaper's average
  luminance once at launch (and on wallpaper change) and flips text between a
  light and a dark palette with 0.45/0.55 hysteresis. Window movement never
  triggers a flip.
- Layered frosting: elevated surfaces (composer, popovers, menus, hover cards)
  get per-layer translucent tints plus a `backdrop-filter` sweep.
- Self-contained distribution: bundled Node.js v24 binary and a pinned,
  npm-installed dsh backend payload; no runtime downloads.
- `repair-backend.sh` — one-shot backend payload reinstall with a smoke test.
- DMG installer with an Applications shortcut and Chinese install notes.

### Fixed

- Missing backend packages after relocating the payload (24 `@deepseek-ai`
  packages): payload installation now goes through `npm` with exact pins.
- DMG creation losing symlinks and invalidating the ad-hoc signature:
  `assemble.sh` now dereferences symlinks (`cp -RL`) before signing.
- Inline-code and citation chips rendering as solid color blocks in the wrong
  theme (they are background tokens, not text tokens).
- Text tokens leaking backdrop color at glyph edges: a 0.5% white underlay
  plus `-webkit-font-smoothing: antialiased`.

### Removed

- Electron-based prototype (private-API glass bridge) and its build pipeline.

## [0.2.0] - 2026-08-15

### Added

- Electron shell prototype (superseded by 0.3.0).

[0.4.0]: https://github.com/qniequn-boop/deepseek-harness-glass/releases/tag/v0.4.0
[0.3.0]: https://github.com/qniequn-boop/deepseek-harness-glass/releases/tag/v0.3.0
