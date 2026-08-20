#!/bin/bash
# Enforces D0: all core DeepSeek Harness Glass surfaces are native Swift/AppKit.
# Third-party plugin Web fallback is encapsulated within the isolated Plugins/PluginWebHost
# target to provide an auto-sandboxed card container without leaking WebKit APIs into core modules.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAN_PATHS=(
  "$ROOT/Sources/App"
  "$ROOT/Sources/Core"
  "$ROOT/Sources/UI"
  "$ROOT/Sources/Features"
  "$ROOT/Sources/Snapshot"
)
PATTERN='WebKit|WKWebView|WKUserScript|WKNavigationDelegate|evaluateJavaScript|MutationObserver|document\.querySelector|document\.getElementById|injectedJavaScript|addUserScript'

existing=()
for path in "${SCAN_PATHS[@]}"; do
  [[ -d "$path" ]] && existing+=("$path")
done

if [[ ${#existing[@]} -eq 0 ]]; then
  echo "No native source paths found to scan." >&2
  exit 1
fi

if rg -n --glob '*.swift' --glob '*.m' --glob '*.mm' --glob '*.h' "$PATTERN" "${existing[@]}"; then
  echo "D0 violation: core application paths may not contain direct WebView, web script, or DOM access APIs." >&2
  exit 1
fi

if rg -n --glob '*.swift' --glob '*.m' --glob '*.mm' --glob '*.h' 'import[[:space:]]+WebKit' "$ROOT/Sources/Plugins" \
  --glob '!PluginWebHost/**' 2>/dev/null; then
  echo "D0 violation: WebKit is only permitted within the isolated PluginWebHost target." >&2
  exit 1
fi

echo "D0 native-only gate passed."
