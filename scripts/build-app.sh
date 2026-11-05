#!/bin/bash
# Builds a minimal .app bundle around the SwiftPM executable so TodayFlow gets
# a real Dock icon, an Info.plist, and Finder "Open With" support.
#
#   ./scripts/build-app.sh            # release
#   ./scripts/build-app.sh debug      # debug
#
# This is an ad-hoc signed local bundle; distribution still needs a Developer ID
# certificate, hardened runtime, and notarization (driver.md Phase 4).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="build/TodayFlow.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/TodayFlowApp" "$APP_DIR/Contents/MacOS/TodayFlowApp"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# Ad-hoc signature: enough for local launch on Apple silicon.
if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Built $APP_DIR"
echo "Open it with: open \"$APP_DIR\""
