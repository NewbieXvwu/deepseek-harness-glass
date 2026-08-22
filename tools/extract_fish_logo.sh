#!/bin/bash
set -euo pipefail

OFFICIAL_SOURCE="${1:?official FishLogo.tsx path is required}"
OUTPUT="${2:?output SVG path is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTOR="${SCRIPT_DIR}/spec-generation/extract_official_icon_ast.mjs"

OFFICIAL_SOURCE_DIR="$(cd "$(dirname "$OFFICIAL_SOURCE")" && pwd)"
CURRENT="$OFFICIAL_SOURCE_DIR"
OFFICIAL_ROOT=""
while [ "$CURRENT" != "/" ] && [ -n "$CURRENT" ]; do
  if [ -f "$CURRENT/package.json" ] && [ -d "$CURRENT/packages" ]; then
    OFFICIAL_ROOT="$CURRENT"
    break
  fi
  CURRENT="$(dirname "$CURRENT")"
done

if [ -z "$OFFICIAL_ROOT" ]; then
  OFFICIAL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

NODE_BIN="${NODE:-node}"

mkdir -p "$(dirname "$OUTPUT")"

{
  printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="23.16" height="17.04" viewBox="0 0 23.16 17.04" fill="none">'
  "$NODE_BIN" "$EXTRACTOR" "$OFFICIAL_ROOT" "$OFFICIAL_SOURCE" "FishLogo" --inner \
    | sed 's/ fill="currentColor"/ fill="#0F1115"/g'
  printf '%s\n' '</svg>'
} > "$OUTPUT"
