#!/bin/bash
# 组装原生玻璃壳 .app：编译 Swift + 内置 Node + 复用 dsh 后端 payload + 图标 + 签名
# 构建进暂存目录后原子替换，避免运行中的实例读到半成品文件。
# 输出位置：/Applications（唯一安装位置，避免 Spotlight 出现多个副本）。
set -euo pipefail
cd "$(dirname "$0")"

# 输出位置：默认 /Applications（本机安装）；CI 可用 APP_PATH 覆盖
APP="${APP_PATH:-/Applications/DeepSeek Harness.app}"
STAGE="$(dirname "$APP")/.app-staging"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

echo "== 1/4 编译 Swift 壳 =="
swift build -c release --product DeepSeekHarnessGlassApp
# SwiftPM selects a target-triple build directory (for example
# `.build/arm64-apple-macosx/release`) on macOS 26. Never infer this location
# from the legacy `.build/release` symlink: an earlier standalone build can
# leave that path usable for the executable while hiding resource bundles.
SWIFTPM_BIN_PATH="$(swift build -c release --show-bin-path)"
test -x "$SWIFTPM_BIN_PATH/DeepSeekHarnessGlassApp"
cp "$SWIFTPM_BIN_PATH/DeepSeekHarnessGlassApp" "$STAGE/Contents/MacOS/DeepSeek Harness"

# SwiftPM resources live in target-specific bundles beside the executable. The
# executable alone is insufficient in a .app: `Bundle.module` must retain every
# produced bundle so generated locales and accessibility contracts load at runtime.
swiftpm_resource_bundle_count=0
while IFS= read -r bundle; do
  cp -R "$bundle" "$STAGE/Contents/Resources/"
  swiftpm_resource_bundle_count=$((swiftpm_resource_bundle_count + 1))
done < <(find "$SWIFTPM_BIN_PATH" -maxdepth 1 -type d -name '*.bundle' -print | sort)
if [[ "$swiftpm_resource_bundle_count" -eq 0 ]]; then
  echo "error: SwiftPM produced no resource bundles for the native app" >&2
  exit 1
fi
if ! find "$STAGE/Contents/Resources" -type f -name 'official-accessibility-baseline.json' -print -quit | grep -q .; then
  echo "error: packaged app is missing official-accessibility-baseline.json" >&2
  exit 1
fi

echo "== 2/4 内置 Node 运行时 =="
mkdir -p "$STAGE/Contents/Resources/node"
cp build/node/node "$STAGE/Contents/Resources/node/node"
chmod +x "$STAGE/Contents/Resources/node/node"

echo "== 3/4 复用 dsh 后端 payload（node_modules）=="
mkdir -p "$STAGE/Contents/Resources/backend"
cp -RL "build/backend/node_modules" \
  "$STAGE/Contents/Resources/backend/node_modules"

echo "== 4/4 Info.plist / 官方基线 / 图标 / 签名 / 原子替换 =="
cp Info.plist "$STAGE/Contents/Info.plist"
cp Sources/Spec/SupportedHostBuilds.json "$STAGE/Contents/Resources/SupportedHostBuilds.json"
cp Sources/Spec/Fixtures/official-column-layout-fixtures.json "$STAGE/Contents/Resources/official-column-layout-fixtures.json"
cp Sources/Core/Resources/official-host-rpc-fixtures.json "$STAGE/Contents/Resources/official-host-rpc-fixtures.json"
OFFICIAL_SOURCE_COMMIT="141eb6fef83422698aef7a981029e843e8161534"
APP_SOURCE_REVISION="$(git -C .. rev-parse HEAD 2>/dev/null || echo unknown)"
cat > "$STAGE/Contents/Resources/BuildManifest.json" <<EOF
{
  "schemaVersion": 1,
  "appSourceRevision": "$APP_SOURCE_REVISION",
  "officialSourceCommit": "$OFFICIAL_SOURCE_COMMIT",
  "dshPackageVersion": "0.1.0-rc.8",
  "webFrontendPackageVersion": "0.1.0-rc.8",
  "nodeRuntimeVersion": "24.19.0",
  "minimumMacOS": "26.0",
  "supportedArchitectures": ["arm64"]
}
EOF
cp ../build/icon.icns "$STAGE/Contents/Resources/icon.icns"
cp assets/*.svg "$STAGE/Contents/Resources/"
codesign --force --deep -s - "$STAGE"

rm -rf "$APP"
mv "$STAGE" "$APP"

echo "== 完成 =="
du -sh "$APP"
