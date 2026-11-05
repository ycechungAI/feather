#!/bin/bash
# Builds FeatherA.app into ./build. Usage: scripts/build-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

# -Osize: optimize for size, not speed. The app's own code is UI glue (pages run inside WebKit),
# so this costs nothing noticeable and makes the binary ~12% smaller.
FLAGS=(-c release --build-system native -Xswiftc -Osize -Xlinker -dead_strip)
swift build "${FLAGS[@]}"
APP=build/FeatherA.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# -X skips extended attributes: on ExFAT/FAT disks they become "._*" files that break the signature.
cp -X "$(swift build "${FLAGS[@]}" --show-bin-path)/FeatherA" "$APP/Contents/MacOS/FeatherA"
strip -x "$APP/Contents/MacOS/FeatherA"
cp -X Support/Info.plist "$APP/Contents/Info.plist"
cp -X Support/FeatherA.icns "$APP/Contents/Resources/FeatherA.icns"
find "$APP" -name '._*' -delete
# Ad-hoc signature with sandbox + hardened runtime. Use a Developer ID to distribute.
codesign --force --options runtime --entitlements Support/FeatherA.entitlements --sign - "$APP"
find "$APP" -name '._*' -delete
codesign --verify --strict "$APP"

echo "Built $APP ($(du -sh "$APP" | cut -f1))"
if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/FeatherA.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/FeatherA.app"
fi
