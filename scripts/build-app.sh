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
# Orcastrator (Research) — bundled web UI/source for Swift native bridge (no runtime Python).
if [ -d "Resources/Orcastrator" ]; then
  mkdir -p "$APP/Contents/Resources/Orcastrator"
  rsync -a --exclude '__pycache__' --exclude '*.pyc' --exclude '.DS_Store' Resources/Orcastrator/ "$APP/Contents/Resources/Orcastrator/"
fi
# Default agent tasks — seeded on first run (user can delete any).
if [ -d "Resources/DefaultTasks" ]; then
  mkdir -p "$APP/Contents/Resources/DefaultTasks"
  rsync -a --exclude '.DS_Store' Resources/DefaultTasks/ "$APP/Contents/Resources/DefaultTasks/"
fi
# setup.sh (Ollama + auto-pull default models) for toolbar/setup actions.
if [ -f "scripts/setup.sh" ]; then
  cp -X scripts/setup.sh "$APP/Contents/Resources/setup.sh"
  chmod +x "$APP/Contents/Resources/setup.sh"
fi
# In-browser pull progress page (opened by toolbar "Pull Models").
if [ -f "Resources/pull-models.html" ]; then
  cp -X Resources/pull-models.html "$APP/Contents/Resources/pull-models.html"
fi
find "$APP" -name '._*' -delete
# Ad-hoc signature with sandbox + hardened runtime. Use a Developer ID to distribute.
codesign --force --options runtime --entitlements Support/FeatherA.entitlements --sign - "$APP"
find "$APP" -name '._*' -delete
codesign --verify --strict "$APP"

echo "Built $APP ($(du -sh "$APP" | cut -f1))"
if [[ "${1:-}" == "--install" ]]; then
  DEST="${HOME}/Applications/FeatherA.app"
  mkdir -p "${HOME}/Applications"
  pkill -f "FeatherA.app/Contents/MacOS/FeatherA" 2>/dev/null || true
  sleep 1
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  xattr -cr "$DEST" 2>/dev/null || true
  open "$DEST" || true
  echo "Installed to $DEST (quarantine cleared, relaunched)"
fi
