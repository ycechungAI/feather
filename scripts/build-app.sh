#!/bin/bash
# Builds Feather.app into ./build. Usage: scripts/build-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --build-system native
APP=build/Feather.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# -X skips extended attributes: on ExFAT/FAT disks they become "._*" files that break the signature.
cp -X "$(swift build -c release --build-system native --show-bin-path)/Feather" "$APP/Contents/MacOS/Feather"
strip -x "$APP/Contents/MacOS/Feather"
cp -X Support/Info.plist "$APP/Contents/Info.plist"
cp -X Support/Feather.icns "$APP/Contents/Resources/Feather.icns"
find "$APP" -name '._*' -delete
# Ad-hoc signature with sandbox + hardened runtime. Use a Developer ID to distribute.
codesign --force --options runtime --entitlements Support/Feather.entitlements --sign - "$APP"
find "$APP" -name '._*' -delete
codesign --verify --strict "$APP"

echo "Built $APP ($(du -sh "$APP" | cut -f1))"
if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Feather.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Feather.app"
fi
