#!/bin/bash
# Builds the real app bundle and runs the XCUITest target against it.
#
# Prerequisites (one-time):
#   - Xcode installed and selected: sudo xcode-select -s /Applications/Xcode.app
#   - XcodeGen: brew install xcodegen
#   - Accessibility permission for the process running xcodebuild
#     (System Settings → Privacy & Security → Accessibility).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh release

# Register the freshly built bundle with LaunchServices so
# XCUIApplication(bundleIdentifier:) can find it.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$PWD/build/TodayFlow.app"
fi

# XCUITest can time out enabling automation if a previous test runner or
# testmanagerd is stuck. Clear both before xcodebuild starts.
pkill -f TodayFlowUITests-Runner 2>/dev/null || true
pkill -f testmanagerd 2>/dev/null || true

if ! DevToolsSecurity -status 2>&1 | grep -qi "enabled"; then
    echo "⚠️  macOS developer mode is disabled."
    echo "   If XCUITest asks to Enable UI Automation, enter your Mac login password,"
    echo "   or run once: sudo DevToolsSecurity -enable"
fi

# XCUIApplication.launch() must start the app itself; an existing instance
# would make it attach to a stale process with no test-controlled launch.
pkill -x TodayFlowApp 2>/dev/null || true

cd UITests
xcodegen generate

DERIVED_DATA="$PWD/../build/uitest-derived"
xcodebuild test \
    -project TodayFlowUITests.xcodeproj \
    -scheme TodayFlowUITests \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    "$@"
