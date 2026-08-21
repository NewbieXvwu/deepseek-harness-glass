#!/usr/bin/env bash
# Audit an already-downloaded native-ui artifact directory for the T6.6
# Deliverables pairing review. This script never executes artifact contents.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <downloaded-native-ui-artifact-dir>\n' "$0" >&2
  exit 64
fi

root=$1
if [[ ! -d "$root" ]]; then
  printf 'artifact directory does not exist: %s\n' "$root" >&2
  exit 66
fi

printf '%s\n' '=== deliverables candidate files ==='
mapfile -t candidates < <(find "$root" -type f \( -iname '*deliverables*' -o -iname '*comparison*' -o -iname '*report*' \) -print | sort)
printf '%s\n' "${candidates[@]:-}"

if [[ ${#candidates[@]} -eq 0 ]]; then
  printf '%s\n' 'no Deliverables/comparison/report files found' >&2
  exit 65
fi

printf '%s\n' '=== PNG dimensions and SHA-256 ==='
for file in "${candidates[@]}"; do
  case "$file" in
    *.png|*.PNG)
      dimensions=$(python3 - "$file" <<'PY'
import sys
from PIL import Image
with Image.open(sys.argv[1]) as image:
    print(f"{image.width}x{image.height}")
PY
)
      sha256sum "$file" | awk -v dimensions="$dimensions" '{print dimensions "  " $1 "  " $2}'
      ;;
  esac
done

printf '%s\n' '=== required review categories ==='
printf '%s\n' '1. native Deliverables PNG at 780x900'
printf '%s\n' '2. native accessibility/ARIA export'
printf '%s\n' '3. official/native diff PNG'
printf '%s\n' '4. comparison report JSON'
