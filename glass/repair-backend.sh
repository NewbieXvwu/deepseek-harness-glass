#!/bin/bash
# 一键重装后端 payload + 冒烟验证 + 重新打包
# 场景：app 报"启动失败 code 1"、后端 ERR_MODULE_NOT_FOUND 时，运行本脚本即可修复。
# 用法: ./repair-backend.sh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

DSH_VERSION="${DSH_VERSION:-0.1.0-rc.7}"
FRONTEND_VERSION="${FRONTEND_VERSION:-0.1.0-rc.7}"

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
sleep 8
if kill -0 "$BACKEND_PID" 2>/dev/null; then
  echo "✅ 后端冒烟通过: $(grep -o 'dsh web: http://[0-9.:]*' /tmp/dsh-smoke.log | head -1)"
  kill "$BACKEND_PID" 2>/dev/null
else
  echo "❌ 后端未能启动，日志:"
  tail -15 /tmp/dsh-smoke.log
  exit 1
fi

cd "$ROOT"
echo "== 完成校验，重新打包 =="
./assemble.sh 2>&1 | tail -3
echo "✅ 全部完成：app 已重新打包，可正常启动"
