#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <node> <dsh-entrypoint> <output-json>" >&2
  exit 64
fi
NODE="$1"
ENTRY="$2"
OUTPUT="$3"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_HOME="$(mktemp -d)"
LOG="$(mktemp)"
PID=""
cleanup() {
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then kill -TERM "$PID" 2>/dev/null || true; fi
  if [[ -n "$PID" ]]; then wait "$PID" 2>/dev/null || true; fi
  rm -rf "$TMP_HOME" "$LOG"
}
trap cleanup EXIT

DSH_HOME="$TMP_HOME" "$NODE" --expose-internals "$ENTRY" web --port 0 >"$LOG" 2>&1 &
PID="$!"
for _ in $(seq 1 100); do
  if grep -qE 'dsh web: http://127\.0\.0\.1:[0-9]+' "$LOG"; then break; fi
  if ! kill -0 "$PID" 2>/dev/null; then cat "$LOG" >&2; exit 1; fi
  sleep 0.1
done
BASE="$(sed -nE 's/^dsh web: (http:\/\/127\.0\.0\.1:[0-9]+).*$/\1/p' "$LOG" | head -n 1)"
[[ -n "$BASE" ]] || { cat "$LOG" >&2; exit 1; }
python3 "$ROOT/tools/spec-generation/capture_official_host_dto_fixtures.py" --base-url "$BASE" --output "$OUTPUT"
