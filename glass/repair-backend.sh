#!/bin/bash
# 一键恢复已锁定的后端 payload + 冒烟验证 + 重新打包
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

echo "== 1/3 从仓库锁文件恢复后端 payload =="
rm -rf build/backend
mkdir -p build/backend
cp ci/dsh-backend-payload/package.json build/backend/package.json
cp ci/dsh-backend-payload/package-lock.json build/backend/package-lock.json
npm ci --no-audit --no-fund --prefix build/backend

echo "== 2/3 校验关键入口 =="
BIN="build/backend/node_modules/@deepseek-ai/dsh/lib/bin.js"
test -f "$BIN" || { echo "dsh bin.js 缺失，安装不完整"; exit 1; }

echo "== 3/3 冒烟测试后端启动 =="
TMP_HOME=$(mktemp -d)
trap 'rm -rf "$TMP_HOME"' EXIT
DSH_HOME="$TMP_HOME" build/node/node --expose-internals \
  "$BIN" web --port 0 > /tmp/dsh-smoke.log 2>&1 &
BACKEND_PID=$!

URL=""
for _ in {1..15}; do
  if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
    echo "后端未能启动，日志:"
    tail -15 /tmp/dsh-smoke.log
    exit 1
  fi
  URL=$(grep -o 'http://127\.0\.0\.1:[0-9]*' /tmp/dsh-smoke.log | head -1 || true)
  [ -n "$URL" ] && break
  sleep 1
done

if [ -z "$URL" ]; then
  echo "后端未在超时前输出 loopback URL，日志:"
  tail -15 /tmp/dsh-smoke.log
  kill "$BACKEND_PID" 2>/dev/null || true
  exit 1
fi

if command -v curl >/dev/null 2>&1; then
  curl -fsS -m 5 "$URL" > /dev/null
fi
kill "$BACKEND_PID" 2>/dev/null || true

./assemble.sh
echo "已按仓库锁文件恢复并重新打包"
