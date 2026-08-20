#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/glass/dist/DeepSeek Harness.app"
SNAPSHOT_DIR="$ROOT/artifacts/native-shell"
DIFF_DIR="$ROOT/artifacts/visual-diff"
OFFICIAL_DIR="$ROOT/artifacts/official-webui"

# Usage: ./local-visual-test.sh [--skip-assemble] [--scene <name>] [--official-dir <path>] [--native-dir <path>] [--out-dir <path>]
SKIP_ASSEMBLE=0
SCENE_FILTER=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-assemble)
      SKIP_ASSEMBLE=1
      shift
      ;;
    --scene)
      SCENE_FILTER="$2"
      shift 2
      ;;
    --official-dir)
      OFFICIAL_DIR="$2"
      shift 2
      ;;
    --native-dir)
      SNAPSHOT_DIR="$2"
      shift 2
      ;;
    --out-dir)
      DIFF_DIR="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--skip-assemble] [--scene <name>] [--official-dir <path>] [--native-dir <path>] [--out-dir <path>]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ $SKIP_ASSEMBLE -eq 0 ]]; then
  echo "== Assembling native app =="
  cd "$ROOT/glass"
  export APP_PATH="$APP"
  ./assemble.sh
fi

if [[ ! -x "$APP/Contents/MacOS/DeepSeek Harness" ]]; then
  echo "Error: Native app not found at $APP. Run without --skip-assemble first." >&2
  exit 1
fi

if [[ ! -d "$OFFICIAL_DIR" ]]; then
  echo "Error: Official baseline not found at $OFFICIAL_DIR." >&2
  echo "You must download the 'official-webui-baseline' artifact from a recent prepare-baseline CI run and extract it there." >&2
  exit 1
fi

echo "== Capturing native snapshots =="
export DSH_GLASS_SNAPSHOT_DIR="$SNAPSHOT_DIR"
"$ROOT/glass/scripts/verify-native-shell.sh" "$APP"

echo "== Comparing scenes =="
cd "$ROOT"
if [[ ! -d /tmp/dsh-visual-venv ]]; then
  python3 -m venv /tmp/dsh-visual-venv
  /tmp/dsh-visual-venv/bin/python -m pip install --disable-pip-version-check --no-input Pillow numpy
fi
source /tmp/dsh-visual-venv/bin/activate

mkdir -p "$DIFF_DIR"
python3 glass/ci/test_visual_policy.py

SCENES=(
  "welcome-no-workspace-light"
  "welcome-no-workspace-dark"
  "sidebar-rail-narrow-light"
  "sidebar-rail-narrow-dark"
  "jobs-expanded-light"
  "jobs-expanded-dark"
  "workspace-search-light"
  "workspace-search-dark"
  "workspace-rename-light"
  "workspace-rename-dark"
  "session-rename-light"
  "session-rename-dark"
  "workspace-delete-light"
  "workspace-delete-dark"
)

for scene in "${SCENES[@]}"; do
  if [[ -n "$SCENE_FILTER" && "$scene" != *"$SCENE_FILTER"* ]]; then
    continue
  fi
  
  case "$scene" in
    welcome-no-workspace-light) native="welcome-light.png" ;;
    welcome-no-workspace-dark) native="welcome-dark.png" ;;
    sidebar-rail-narrow-light) native="sidebar-rail-narrow-light.png" ;;
    sidebar-rail-narrow-dark) native="sidebar-rail-narrow-dark.png" ;;
    jobs-expanded-light) native="jobs-expanded-light.png" ;;
    jobs-expanded-dark) native="jobs-expanded-dark.png" ;;
    workspace-search-light) native="workspace-search-official-viewport.png" ;;
    workspace-search-dark) native="workspace-search-official-viewport-dark.png" ;;
    workspace-rename-light) native="workspace-rename-official-viewport.png" ;;
    workspace-rename-dark) native="workspace-rename-official-viewport-dark.png" ;;
    session-rename-light) native="session-rename-official-viewport.png" ;;
    session-rename-dark) native="session-rename-official-viewport-dark.png" ;;
    workspace-delete-light) native="workspace-delete-official-viewport.png" ;;
    workspace-delete-dark) native="workspace-delete-official-viewport-dark.png" ;;
    *) echo "Unknown mapping for $scene" >&2; exit 1 ;;
  esac

  echo "Comparing $scene..."
  python3 glass/ci/compare_visual_pair.py \
    --official "$OFFICIAL_DIR/${scene}.png" \
    --native "$SNAPSHOT_DIR/${native}" \
    --out-dir "$DIFF_DIR" \
    --scene "$scene" \
    --policy glass/Sources/Spec/Fixtures/visual-validation-policy.json \
    --column-fixtures glass/Sources/Spec/Fixtures/official-column-layout-fixtures.json
done

echo "== Local visual test complete =="
echo "Check $DIFF_DIR for reports and diff images."
