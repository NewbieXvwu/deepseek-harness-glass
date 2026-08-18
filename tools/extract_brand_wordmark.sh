#!/bin/bash
set -euo pipefail

OFFICIAL_SOURCE="${1:?official BrandWordmark.tsx path is required}"
OUTPUT="${2:?output SVG path is required}"

{
  printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="182" height="24" viewBox="0 0 182 24" fill="none">'
  sed -n '24,53p' "$OFFICIAL_SOURCE" \
    | sed -E \
      -e 's/ fill="currentColor"/ fill="#0F1115"/g' \
      -e 's/ fill="var\(--dsw-alias-label-primary-inverted\)"/ fill="#FFFFFF"/g'
  printf '%s\n' '</svg>'
} > "$OUTPUT"
