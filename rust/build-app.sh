#!/bin/bash
# Builds the Rust prototype into rust/build/Feather.app, signed and sandboxed like scripts/build-app.sh.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:$PATH"

cargo build --release
APP=build/Feather.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# -X skips extended attributes: on ExFAT/FAT disks they become "._*" files that break the signature.
cp -X target/release/feather "$APP/Contents/MacOS/Feather"
cp -X ../Support/Info.plist "$APP/Contents/Info.plist"
cp -X ../Support/Feather.icns "$APP/Contents/Resources/Feather.icns"
find "$APP" -name '._*' -delete
# Ad-hoc signature with sandbox + hardened runtime, the same entitlements as the Swift build.
codesign --force --options runtime --entitlements ../Support/Feather.entitlements --sign - "$APP"
find "$APP" -name '._*' -delete
codesign --verify --strict "$APP"

echo "Built $APP ($(du -sh "$APP" | cut -f1))"
