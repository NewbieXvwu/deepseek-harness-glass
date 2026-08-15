#!/bin/bash
# 组装原生玻璃壳 .app：编译 Swift + 内置 Node + 复用 dsh 后端 payload + 图标 + 签名
# 构建进暂存目录后原子替换，避免运行中的实例读到半成品文件。
# 输出位置：/Applications（唯一安装位置，避免 Spotlight 出现多个副本）。
set -e
cd "$(dirname "$0")"

# 输出位置：默认 /Applications（本机安装）；CI 可用 APP_PATH 覆盖
APP="${APP_PATH:-/Applications/DeepSeek Harness.app}"
STAGE="$(dirname "$APP")/.app-staging"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

echo "== 1/4 编译 Swift 壳 =="
swiftc -O -parse-as-library -target arm64-apple-macosx26.0 \
  Sources/main.swift \
  -o "$STAGE/Contents/MacOS/DeepSeek Harness"

echo "== 2/4 内置 Node 运行时 =="
mkdir -p "$STAGE/Contents/Resources/node"
cp build/node/node "$STAGE/Contents/Resources/node/node"
chmod +x "$STAGE/Contents/Resources/node/node"

echo "== 3/4 复用 dsh 后端 payload（node_modules）=="
mkdir -p "$STAGE/Contents/Resources/backend"
cp -RL "build/backend/node_modules" \
  "$STAGE/Contents/Resources/backend/node_modules"

echo "== 4/4 Info.plist / 图标 / 签名 / 原子替换 =="
cp Info.plist "$STAGE/Contents/Info.plist"
cp ../build/icon.icns "$STAGE/Contents/Resources/icon.icns"
codesign --force --deep -s - "$STAGE"

rm -rf "$APP"
mv "$STAGE" "$APP"

echo "== 完成 =="
du -sh "$APP"
