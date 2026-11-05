#!/bin/bash
# Renders the TodayFlow app icon and builds Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER="build/icon-master-1024.png"
ICONSET="build/AppIcon.iconset"
ICNS="Resources/AppIcon.icns"

mkdir -p build Resources
swift scripts/make-icon.swift "$MASTER"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
# The 512@2x slot is the 1024 master.
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ICNS"
rm -rf "$ICONSET"
echo "Wrote $ICNS"
