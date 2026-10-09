#!/bin/bash
# Builds Feather.app into ./build. Usage: scripts/build-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/Feather.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Feather" "$APP/Contents/MacOS/Feather"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature with sandbox + hardened runtime. Use a Developer ID to distribute.
codesign --force --options runtime --entitlements Support/Feather.entitlements --sign - "$APP"

echo "Built $APP ($(du -sh "$APP" | cut -f1))"
if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Feather.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Feather.app"
fi
