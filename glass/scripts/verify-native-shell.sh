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

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/welcome-light.png" \
DSH_GLASS_SNAPSHOT_MODE="welcome" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/conversation-dark.png" \
DSH_GLASS_SNAPSHOT_MODE="conversation" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="dark" \
"$BINARY"

# RC8 `ProducedFiles` output with an official-equivalent ten-path diff-card
# turn tail. At the 780px lane it validates measured two-chip/+8 overflow and
# the capability-gated folder action posture.
DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/deliverables-light.png" \
DSH_GLASS_SNAPSHOT_MODE="deliverables" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
DSH_GLASS_SNAPSHOT_WIDTH="780" \
DSH_GLASS_SNAPSHOT_HEIGHT="900" \
"$BINARY"

# The locked official capture is a workspace-backed composer with the default
# Host model directory resolved, but its model trigger remains closed. Native
# uses the same 1280×840 viewport and a matching complete `session.models` fact.
DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/model-selector-light.png" \
DSH_GLASS_SNAPSHOT_MODE="model" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
"$BINARY"

# Same 1280×840 viewport and Host-owned job snapshot as the official captures.
DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/jobs-expanded-light.png" \
DSH_GLASS_SNAPSHOT_MODE="jobs" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/jobs-expanded-dark.png" \
DSH_GLASS_SNAPSHOT_MODE="jobs" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="dark" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/tooling-inspector-light.png" \
DSH_GLASS_SNAPSHOT_MODE="tooling" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/tooling-inspector-dark.png" \
DSH_GLASS_SNAPSHOT_MODE="tooling" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="dark" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/approval-panel-light.png" \
DSH_GLASS_SNAPSHOT_MODE="approval" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/question-composer-light.png" \
DSH_GLASS_SNAPSHOT_MODE="question" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
"$BINARY"

# Stage 3: the same 1280×1100 logical viewport as the locked official browser fixture.
DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/workspace-search-official-viewport.png" \
DSH_GLASS_SNAPSHOT_MODE="workspace-search" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
DSH_GLASS_SNAPSHOT_WIDTH="1280" \
DSH_GLASS_SNAPSHOT_HEIGHT="1100" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/workspace-rename-official-viewport.png" \
DSH_GLASS_SNAPSHOT_MODE="workspace-rename" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
DSH_GLASS_SNAPSHOT_WIDTH="1280" \
DSH_GLASS_SNAPSHOT_HEIGHT="1100" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/session-rename-official-viewport.png" \
DSH_GLASS_SNAPSHOT_MODE="session-rename" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
DSH_GLASS_SNAPSHOT_WIDTH="1280" \
DSH_GLASS_SNAPSHOT_HEIGHT="1100" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/workspace-delete-official-viewport.png" \
DSH_GLASS_SNAPSHOT_MODE="workspace-delete" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
DSH_GLASS_SNAPSHOT_WIDTH="1280" \
DSH_GLASS_SNAPSHOT_HEIGHT="1100" \
"$BINARY"

# RC8 management capture must pair the same fixture state in ThemeRuntime dark
# mode with a real `.darkAqua` WindowServer composition; no light artifact may
# stand in for a dark dialog review.
for mode in workspace-search workspace-rename session-rename workspace-delete; do
  DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/${mode}-official-viewport-dark.png" \
  DSH_GLASS_SNAPSHOT_MODE="$mode" \
  DSH_GLASS_SNAPSHOT_COLOR_SCHEME="dark" \
  DSH_GLASS_SNAPSHOT_WIDTH="1280" \
  DSH_GLASS_SNAPSHOT_HEIGHT="1100" \
  "$BINARY"
done

# Same CSS viewport measured in the locked official WebUI browser capture.
DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/approval-panel-official-viewport.png" \
DSH_GLASS_SNAPSHOT_MODE="approval" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
DSH_GLASS_SNAPSHOT_WIDTH="1280" \
DSH_GLASS_SNAPSHOT_HEIGHT="1100" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/question-composer-official-viewport.png" \
DSH_GLASS_SNAPSHOT_MODE="question" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
DSH_GLASS_SNAPSHOT_WIDTH="1280" \
DSH_GLASS_SNAPSHOT_HEIGHT="1100" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/welcome-dark.png" \
DSH_GLASS_SNAPSHOT_MODE="welcome" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="dark" \
"$BINARY"

# RC8 narrow sidebar re-certification uses the exact 1023px auto-collapse
# threshold and captures both ThemeRuntime color schemes against matching
# official browser viewports.
DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/sidebar-rail-narrow-light.png" \
DSH_GLASS_SNAPSHOT_MODE="welcome" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="light" \
DSH_GLASS_SNAPSHOT_WIDTH="1023" \
DSH_GLASS_SNAPSHOT_HEIGHT="840" \
"$BINARY"

DSH_GLASS_SNAPSHOT_PATH="$OUTPUT_DIR/sidebar-rail-narrow-dark.png" \
DSH_GLASS_SNAPSHOT_MODE="welcome" \
DSH_GLASS_SNAPSHOT_COLOR_SCHEME="dark" \
DSH_GLASS_SNAPSHOT_WIDTH="1023" \
DSH_GLASS_SNAPSHOT_HEIGHT="840" \
"$BINARY"

for image in "$OUTPUT_DIR/welcome-light.png" "$OUTPUT_DIR/welcome-dark.png" "$OUTPUT_DIR/sidebar-rail-narrow-light.png" "$OUTPUT_DIR/sidebar-rail-narrow-dark.png" "$OUTPUT_DIR/conversation-dark.png" "$OUTPUT_DIR/deliverables-light.png" "$OUTPUT_DIR/model-selector-light.png" "$OUTPUT_DIR/jobs-expanded-light.png" "$OUTPUT_DIR/jobs-expanded-dark.png" "$OUTPUT_DIR/tooling-inspector-light.png" "$OUTPUT_DIR/tooling-inspector-dark.png" "$OUTPUT_DIR/approval-panel-light.png" "$OUTPUT_DIR/question-composer-light.png" "$OUTPUT_DIR/workspace-search-official-viewport.png" "$OUTPUT_DIR/workspace-rename-official-viewport.png" "$OUTPUT_DIR/session-rename-official-viewport.png" "$OUTPUT_DIR/workspace-delete-official-viewport.png" "$OUTPUT_DIR/workspace-search-official-viewport-dark.png" "$OUTPUT_DIR/workspace-rename-official-viewport-dark.png" "$OUTPUT_DIR/session-rename-official-viewport-dark.png" "$OUTPUT_DIR/workspace-delete-official-viewport-dark.png" "$OUTPUT_DIR/approval-panel-official-viewport.png" "$OUTPUT_DIR/question-composer-official-viewport.png"; do
  test -s "$image"
  sips -g pixelWidth -g pixelHeight "$image"
done

# D0 is intentionally verified by NativeWebViewIsolationRuntimeTests against
# mounted AppKit/SwiftUI surfaces and a real WKWebView injection negative case.
# Do not scan project Swift source here: behavior tests must remain refactor-safe.

echo "native shell snapshots written to: $OUTPUT_DIR"
