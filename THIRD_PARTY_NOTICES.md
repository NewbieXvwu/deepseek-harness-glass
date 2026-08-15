# Third-Party Notices

DeepSeek Harness Glass bundles or derives from the following third-party works.
All of them are distributed under permissive licenses; the full license texts
are available at the linked sources.

## DeepSeek Harness

- Project: <https://github.com/deepseek-ai/deepseek-harness>
- License: MIT
- Usage: the dsh backend engine (`@deepseek-ai/dsh`) and web frontend
  (`@deepseek-ai/dsh-web-frontend`) are bundled unmodified from the official
  npm releases, pinned to exact versions. The whale favicon in `build/icon.icns`
  is derived from the dsh repository's `apps/web/public/favicon.svg`.

## Node.js

- Project: <https://nodejs.org/>
- License: MIT (with bundled dependencies under their own permissive licenses)
- Usage: the official Node.js v24 darwin-arm64 binary is bundled to run the
  dsh backend, so end users do not need a Node.js installation.

## Apple platform APIs

- The Liquid Glass window uses public SwiftUI/AppKit APIs
  (`glassEffect`, `NSVisualEffectView`, transparency and full-size-content
  window options) available on macOS 26 and later. No private APIs are used.

## Fonts

- The user interface uses fonts shipped with the dsh web frontend and macOS
  system fonts.
