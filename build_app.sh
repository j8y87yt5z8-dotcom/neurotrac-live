#!/bin/bash
# Builds "NeuroTrac Live.app" (once, or after each new version of the code).
# Usage: open Terminal, go to this folder, then:   ./build_app.sh
set -e
cd "$(dirname "$0")"

APP="NeuroTrac Live.app"
NAME="NeuroTracLive"

echo "1/4  Compiling (first time: 1 to 3 minutes)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$NAME"
if [ ! -f "$BIN" ]; then echo "Error: compiled program not found."; exit 1; fi

echo "2/4  Creating the app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "3/4  Icon…"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2))
  sips -z $d $d Resources/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "4/4  Local ad-hoc signature…"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP"

echo
echo "Done: $(pwd)/$APP"
echo "Drag it to the Applications folder. First launch: right-click > Open."
echo "macOS will ask for Bluetooth permission: allow it."
if [ -z "$NTL_NO_FINDER" ]; then open -R "$APP" || true; fi
