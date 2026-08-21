#!/usr/bin/env bash
# Exercises the production assembler with a minimal SwiftPM-shaped build tree.
# The test deliberately leaves `.build/release` without resource bundles: a
# regression to that legacy location must fail, while the target-triple path
# emitted by `swift build --show-bin-path` must produce an installable app.
set -euo pipefail

GLASS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

FIXTURE_GLASS="$FIXTURE_ROOT/glass"
TARGET_BIN="$FIXTURE_GLASS/.build/arm64-apple-macosx/release"
FAKE_BIN="$FIXTURE_ROOT/fake-bin"
APP_PATH="$FIXTURE_ROOT/DeepSeek Harness.app"

mkdir -p \
  "$TARGET_BIN/GlassSpec_GlassSpec.bundle/Fixtures" \
  "$FIXTURE_GLASS/.build/release" \
  "$FIXTURE_GLASS/Sources/Spec/Fixtures" \
  "$FIXTURE_GLASS/Sources/Core/Resources" \
  "$FIXTURE_GLASS/build/node" \
  "$FIXTURE_GLASS/build/backend/node_modules" \
  "$FIXTURE_GLASS/assets" \
  "$FAKE_BIN" \
  "$FIXTURE_ROOT/build" \
  "$FIXTURE_ROOT/tools"

cp "$GLASS_ROOT/assemble.sh" "$FIXTURE_GLASS/assemble.sh"
cp "$GLASS_ROOT/../tools/emit-build-manifest.py" "$FIXTURE_ROOT/tools/emit-build-manifest.py"
chmod +x "$FIXTURE_GLASS/assemble.sh"
printf 'fixture plist\n' > "$FIXTURE_GLASS/Info.plist"
cat > "$FIXTURE_GLASS/Sources/Spec/SupportedHostBuilds.json" <<'EOF'
{
  "defaultBuildId": "fixture-build",
  "builds": [{
    "id": "fixture-build",
    "officialSourceCommit": "fixture-commit",
    "dshPackageVersion": "fixture-dsh",
    "webFrontendPackageVersion": "fixture-web",
    "nodeRuntimeVersion": "fixture-node",
    "minimumMacOS": "26.0",
    "supportedArchitectures": ["arm64"]
  }]
}
EOF
cat > "$FIXTURE_GLASS/Sources/Spec/HostUpgradeReport.json" <<'EOF'
{
  "hostBuildId": "fixture-build",
  "officialSourceCommit": "fixture-commit",
  "uiSpecRevision": "fixture-ui-spec",
  "protocolFixtureRevision": "fixture-protocol",
  "rawEventFixtureRevision": "fixture-raw-events"
}
EOF
printf '{}\n' > "$FIXTURE_GLASS/Sources/Spec/Fixtures/official-column-layout-fixtures.json"
printf '{}\n' > "$FIXTURE_GLASS/Sources/Core/Resources/official-host-rpc-fixtures.json"
printf 'fixture svg\n' > "$FIXTURE_GLASS/assets/fixture.svg"
printf 'fixture icon\n' > "$FIXTURE_ROOT/build/icon.icns"
printf 'fixture accessibility baseline\n' > \
  "$TARGET_BIN/GlassSpec_GlassSpec.bundle/Fixtures/official-accessibility-baseline.json"
printf '#!/usr/bin/env bash\necho target-triple executable\n' > "$TARGET_BIN/DeepSeekHarnessGlassApp"
printf '#!/usr/bin/env bash\necho legacy executable\n' > "$FIXTURE_GLASS/.build/release/DeepSeekHarnessGlassApp"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FIXTURE_GLASS/build/node/node"
chmod +x "$TARGET_BIN/DeepSeekHarnessGlassApp" \
  "$FIXTURE_GLASS/.build/release/DeepSeekHarnessGlassApp" \
  "$FIXTURE_GLASS/build/node/node"

cat > "$FAKE_BIN/swift" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *" --show-bin-path "* ]]; then
  printf '%s\n' "$ASSEMBLE_TEST_TARGET_BIN"
  exit 0
fi
exit 0
EOF
cat > "$FAKE_BIN/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$FAKE_BIN/swift" "$FAKE_BIN/codesign"

PATH="$FAKE_BIN:$PATH" \
ASSEMBLE_TEST_TARGET_BIN="$TARGET_BIN" \
APP_PATH="$APP_PATH" \
"$FIXTURE_GLASS/assemble.sh" >/dev/null

test -x "$APP_PATH/Contents/MacOS/DeepSeek Harness"
test "$("$APP_PATH/Contents/MacOS/DeepSeek Harness")" = "target-triple executable"
test -s "$APP_PATH/Contents/Resources/GlassSpec_GlassSpec.bundle/Fixtures/official-accessibility-baseline.json"
test -s "$APP_PATH/Contents/Resources/SupportedHostBuilds.json"
test -s "$APP_PATH/Contents/Resources/HostUpgradeReport.json"
test -s "$APP_PATH/Contents/Resources/official-column-layout-fixtures.json"
test -s "$APP_PATH/Contents/Resources/official-host-rpc-fixtures.json"
test -s "$APP_PATH/Contents/Resources/BuildManifest.json"
grep -F '"hostBuildId": "fixture-build"' "$APP_PATH/Contents/Resources/BuildManifest.json"
grep -F '"appSourceRevision": "unknown"' "$APP_PATH/Contents/Resources/BuildManifest.json"

echo 'assemble resource-bundle fixture passed'
