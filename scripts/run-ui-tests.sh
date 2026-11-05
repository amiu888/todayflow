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
