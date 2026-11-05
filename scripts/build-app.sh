#!/bin/bash
# Builds a distribution-ready TodayFlow.app.
#
#   ./scripts/build-app.sh            # release
#   ./scripts/build-app.sh debug      # debug
#
# Uses the first "Developer ID Application" identity in the keychain when
# available; otherwise falls back to an ad-hoc signature for local testing.
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
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/Developer ID Application/ {print $2; exit}')"

if [[ -n "$IDENTITY" ]]; then
    echo "Signing with: $IDENTITY"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_DIR"
else
    echo "No Developer ID identity found; using an ad-hoc signature."
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>&1 | tail -3
echo "Built $APP_DIR"
echo "Open it with: open \"$APP_DIR\""
