#!/bin/bash
set -euo pipefail

OFFICIAL_SOURCE="${1:?official BrandWordmark.tsx path is required}"
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
  printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="182" height="24" viewBox="0 0 182 24" fill="none">'
  "$NODE_BIN" "$EXTRACTOR" "$OFFICIAL_ROOT" "$OFFICIAL_SOURCE" "BrandWordmark" --inner \
    | sed -E \
      -e 's/ fill="currentColor"/ fill="#0F1115"/g' \
      -e 's/ fill="var\(--dsw-alias-label-primary-inverted\)"/ fill="#FFFFFF"/g'
  printf '%s\n' '</svg>'
} > "$OUTPUT"
