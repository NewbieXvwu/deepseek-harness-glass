#!/bin/bash
# 一键重装后端 payload + 冒烟验证 + 重新打包
# 场景：app 报"启动失败 code 1"、后端 ERR_MODULE_NOT_FOUND 时，运行本脚本即可修复。
# 用法: ./repair-backend.sh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

IFS=$'\t' read -r DEFAULT_DSH_VERSION DEFAULT_FRONTEND_VERSION < <(python3 ../tools/emit-build-manifest.py --repo .. --payload-versions)
DSH_VERSION="${DSH_VERSION:-$DEFAULT_DSH_VERSION}"
FRONTEND_VERSION="${FRONTEND_VERSION:-$DEFAULT_FRONTEND_VERSION}"

echo "== 1/3 重建后端 payload（npm 精确 pin）=="
mkdir -p build/backend
cd build/backend
cat > package.json <<EOF
{
  "name": "dsh-backend-payload",
  "private": true,
  "description": "DeepSeek Harness 玻璃版内置后端依赖（精确 pin，勿用 ^ 范围）",
  "dependencies": {
    "@deepseek-ai/dsh": "${DSH_VERSION}",
    "@deepseek-ai/dsh-web-frontend": "${FRONTEND_VERSION}"
  }
}
EOF
rm -rf node_modules package-lock.json
npm install --no-audit --no-fund 2>&1 | tail -3

echo "== 2/3 校验关键入口 =="
BIN="node_modules/@deepseek-ai/dsh/lib/bin.js"
test -f "$BIN" || { echo "❌ dsh bin.js 缺失，安装不完整"; exit 1; }
echo "✅ bin.js 存在，@deepseek-ai 包数: $(ls node_modules/@deepseek-ai | wc -l | tr -d ' ')"

echo "== 3/3 冒烟测试后端启动 =="
TMP_HOME=$(mktemp -d)
DSH_HOME="$TMP_HOME" ../node/node --expose-internals \
  "$BIN" web --port 0 > /tmp/dsh-smoke.log 2>&1 &
BACKEND_PID=$!

URL=""
for i in {1..15}; do
  if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
    echo "❌ 后端未能启动（进程异常退出），日志:"
    tail -15 /tmp/dsh-smoke.log
    exit 1
  fi
  URL=$(grep -o 'http://127\.0\.0\.1:[0-9]*' /tmp/dsh-smoke.log | head -1 || true)
  if [ -n "$URL" ]; then
    break
  fi
  sleep 1
done

if [ -z "$URL" ]; then
  echo "❌ 后端启动超时或未输出有效 URL，日志:"
  tail -15 /tmp/dsh-smoke.log
  kill "$BACKEND_PID" 2>/dev/null || true
  exit 1
fi

if command -v curl >/dev/null 2>&1; then
  if ! curl -fsS -m 5 "$URL" > /dev/null 2>&1; then
    echo "❌ 后端 HTTP 请求探测失败 ($URL)，日志:"
    tail -15 /tmp/dsh-smoke.log
    kill "$BACKEND_PID" 2>/dev/null || true
    exit 1
  fi
fi

echo "✅ 后端冒烟通过: $URL"
kill "$BACKEND_PID" 2>/dev/null || true

cd "$ROOT"
echo "== 完成校验，重新打包 =="
./assemble.sh 2>&1 | tail -3
echo "✅ 全部完成：app 已重新打包，可正常启动"
