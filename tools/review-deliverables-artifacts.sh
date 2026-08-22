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
candidates=()
while IFS= read -r file; do
  [[ -n "$file" ]] && candidates+=("$file")
done < <(find "$root" -type f \( -iname '*deliverables*' -o -iname '*comparison*' -o -iname '*report*' \) | sort)
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
try:
    from PIL import Image
    with Image.open(sys.argv[1]) as image:
        print(f"{image.width}x{image.height}")
except Exception:
    print("unknown")
PY
)
      (command -v sha256sum >/dev/null 2>&1 && sha256sum "$file" || shasum -a 256 "$file") | awk -v dimensions="$dimensions" '{print dimensions "  " $1 "  " $2}'
      ;;
  esac
done

printf '%s\n' '=== verifying required review categories ==='
missing=0

# 1. native Deliverables PNG
if find "$root" -type f \( -iname '*deliverables*.png' -o -iname '*deliverables*.PNG' \) | grep -q .; then
  printf '✅ Category 1: native Deliverables PNG found\n'
else
  printf '❌ Category 1 missing: no native Deliverables PNG found under %s\n' "$root" >&2
  missing=$((missing + 1))
fi

# 2. native accessibility/ARIA export
if find "$root" -type f \( -iname '*deliverables*.json' -o -iname '*deliverables*.aria.json' -o -iname '*deliverables*.md' -o -iname '*aria*.json' \) | grep -q .; then
  printf '✅ Category 2: native accessibility/ARIA export found\n'
else
  printf '❌ Category 2 missing: no native accessibility/ARIA export found under %s\n' "$root" >&2
  missing=$((missing + 1))
fi

# 3. official/native diff PNG
if find "$root" -type f \( -iname '*diff*.png' -o -iname '*comparison*.png' \) | grep -q .; then
  printf '✅ Category 3: official/native diff PNG found\n'
else
  printf '❌ Category 3 missing: no official/native diff PNG found under %s\n' "$root" >&2
  missing=$((missing + 1))
fi

# 4. comparison report JSON
if find "$root" -type f \( -iname '*report*.json' -o -iname '*comparison*.json' \) | grep -q .; then
  printf '✅ Category 4: comparison report JSON found\n'
else
  printf '❌ Category 4 missing: no comparison report JSON found under %s\n' "$root" >&2
  missing=$((missing + 1))
fi

if [[ $missing -ne 0 ]]; then
  printf 'Review deliverables validation failed: %d category(ies) missing\n' "$missing" >&2
  exit 1
fi
printf 'All required deliverables review categories verified successfully.\n'
