#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="${1:-$ROOT/glass/dist/DeepSeek Harness.app}"
BINARY="$APP/Contents/MacOS/DeepSeek Harness"
OUTPUT_DIR="${DSH_GLASS_SNAPSHOT_DIR:-$ROOT/artifacts/native-shell}"

if [[ ! -x "$BINARY" ]]; then
  echo "native app binary is missing or not executable: $BINARY" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/welcome-dark.png" \
DSH_GLASS_SNAPSHOT_MODE="welcome" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/conversation-dark.png" \
DSH_GLASS_SNAPSHOT_MODE="conversation" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/tooling-inspector-dark.png" \
DSH_GLASS_SNAPSHOT_MODE="tooling" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/approval-panel-light.png" \
DSH_GLASS_SNAPSHOT_MODE="approval" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/question-composer-light.png" \
DSH_GLASS_SNAPSHOT_MODE="question" \
"$BINARY"

for image in "$OUTPUT_DIR/welcome-dark.png" "$OUTPUT_DIR/conversation-dark.png" "$OUTPUT_DIR/tooling-inspector-dark.png" "$OUTPUT_DIR/approval-panel-light.png" "$OUTPUT_DIR/question-composer-light.png"; do
  test -s "$image"
  sips -g pixelWidth -g pixelHeight "$image"
done

# D0: 核心 native 源码禁止回归到网页容器、脚本注入或 DOM 扫描。
if rg -n --glob '*.swift' 'WKWebView|WKUserScript|evaluateJavaScript|MutationObserver' \
  "$ROOT/glass/Sources/App" "$ROOT/glass/Sources/Core" "$ROOT/glass/Sources/Spec" "$ROOT/glass/Sources/UI" 2>/dev/null; then
  echo "core native sources must not reintroduce WebView or webpage injection" >&2
  exit 1
fi

echo "native shell snapshots written to: $OUTPUT_DIR"
