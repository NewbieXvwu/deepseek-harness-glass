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

# Stage 3: the same 1280×1100 logical viewport as the locked official browser fixture.
DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/workspace-search-official-viewport.png" \
DSH_GLASS_SNAPSHOT_MODE="workspace-search" \
DSH_GLASS_SNAPSHOT_WIDTH="1280" \
DSH_GLASS_SNAPSHOT_HEIGHT="1100" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/workspace-rename-official-viewport.png" \
DSH_GLASS_SNAPSHOT_MODE="workspace-rename" \
DSH_GLASS_SNAPSHOT_WIDTH="1280" \
DSH_GLASS_SNAPSHOT_HEIGHT="1100" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/session-rename-official-viewport.png" \
DSH_GLASS_SNAPSHOT_MODE="session-rename" \
DSH_GLASS_SNAPSHOT_WIDTH="1280" \
DSH_GLASS_SNAPSHOT_HEIGHT="1100" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/workspace-delete-official-viewport.png" \
DSH_GLASS_SNAPSHOT_MODE="workspace-delete" \
DSH_GLASS_SNAPSHOT_WIDTH="1280" \
DSH_GLASS_SNAPSHOT_HEIGHT="1100" \
"$BINARY"

# Same CSS viewport measured in the locked official WebUI browser capture.
DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/approval-panel-official-viewport.png" \
DSH_GLASS_SNAPSHOT_MODE="approval" \
DSH_GLASS_SNAPSHOT_WIDTH="1280" \
DSH_GLASS_SNAPSHOT_HEIGHT="1100" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/question-composer-official-viewport.png" \
DSH_GLASS_SNAPSHOT_MODE="question" \
DSH_GLASS_SNAPSHOT_WIDTH="1280" \
DSH_GLASS_SNAPSHOT_HEIGHT="1100" \
"$BINARY"

for image in "$OUTPUT_DIR/welcome-dark.png" "$OUTPUT_DIR/conversation-dark.png" "$OUTPUT_DIR/tooling-inspector-dark.png" "$OUTPUT_DIR/approval-panel-light.png" "$OUTPUT_DIR/question-composer-light.png" "$OUTPUT_DIR/workspace-search-official-viewport.png" "$OUTPUT_DIR/workspace-rename-official-viewport.png" "$OUTPUT_DIR/session-rename-official-viewport.png" "$OUTPUT_DIR/workspace-delete-official-viewport.png" "$OUTPUT_DIR/approval-panel-official-viewport.png" "$OUTPUT_DIR/question-composer-official-viewport.png"; do
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
