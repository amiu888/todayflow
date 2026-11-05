#!/bin/bash
# Builds a signed DMG for distribution.
#
# Notarization requires an Apple Developer account and a notarytool keychain
# profile. To notarize, first run once:
#   xcrun notarytool store-credentials todayflow \
#     --apple-id "you@example.com" --team-id XC9C9QZ6W8
# then:
#   NOTARY_PROFILE=todayflow ./scripts/package-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh release

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/TodayFlow-${VERSION}.dmg"
STAGE="build/dmg-stage"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/TodayFlow.app "$STAGE/TodayFlow.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "TodayFlow" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/Developer ID Application/ {print $2; exit}')"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" && -n "$IDENTITY" ]]; then
    echo "Submitting for notarization…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "Notarized and stapled."
else
    echo "DMG is signed but not notarized."
    echo "See the notarization instructions at the top of this script."
fi

# The checksum must be written after notarization/stapling: the staple
# modifies the DMG, so an earlier hash no longer matches the shipped file.
shasum -a 256 "$DMG" > "$DMG.sha256"

echo "Built $DMG"
