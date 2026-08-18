#!/bin/bash
set -euo pipefail

OFFICIAL_SOURCE="${1:?official FishLogo.tsx path is required}"
OUTPUT="${2:?output SVG path is required}"

{
  printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="23.16" height="17.04" viewBox="0 0 23.16 17.04" fill="none">'
  sed -n '24p' "$OFFICIAL_SOURCE" | sed 's/ fill="currentColor"/ fill="#0F1115"/g'
  printf '%s\n' '</svg>'
} > "$OUTPUT"
