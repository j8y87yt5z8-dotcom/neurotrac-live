#!/bin/bash
# Updates NeuroTrac Live in one command.
# Usage: unzip / pull the new version, open Terminal in its folder, then:   ./update_app.sh
# - rebuilds the app
# - quits the old one if it is running, keeps a backup copy, then installs the new one
# - your data (Documents/NeuroTracLive) is never touched
# To roll back: ./update_app.sh --undo
set -e
cd "$(dirname "$0")"

APP="NeuroTrac Live.app"
BACKUPS="$HOME/Documents/NeuroTracLive/Anciennes_versions"

# install folder: /Applications if writable, otherwise ~/Applications
if [ -w /Applications ]; then DEST="/Applications"; else DEST="$HOME/Applications"; fi
mkdir -p "$DEST" "$BACKUPS"

quit_app() {
  if pgrep -x NeuroTracLive >/dev/null 2>&1; then
    echo "Quitting the running app…"
    osascript -e 'tell application "NeuroTrac Live" to quit' >/dev/null 2>&1 || true
    for i in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -x NeuroTracLive >/dev/null 2>&1 || break
      sleep 1
    done
    pkill -x NeuroTracLive >/dev/null 2>&1 || true
  fi
}

if [ "$1" = "--undo" ]; then
  LAST="$(ls -1d "$BACKUPS"/*.app 2>/dev/null | tail -1)"
  if [ -z "$LAST" ]; then echo "No previous version found in $BACKUPS"; exit 1; fi
  quit_app
  rm -rf "$DEST/$APP"
  ditto "$LAST" "$DEST/$APP"
  echo "Previous version restored: $LAST"
  open "$DEST/$APP"
  exit 0
fi

echo "Building the new version…"
NTL_NO_FINDER=1 ./build_app.sh

quit_app
if [ -d "$DEST/$APP" ]; then
  STAMP="$(date +%Y%m%d_%H%M%S)"
  echo "Backing up the old version: $BACKUPS/NeuroTrac Live_$STAMP.app"
  ditto "$DEST/$APP" "$BACKUPS/NeuroTrac Live_$STAMP.app"
  rm -rf "$DEST/$APP"
fi
ditto "$APP" "$DEST/$APP"

echo
echo "Installed: $DEST/$APP"
echo "Your data has not moved. To go back to the previous version: ./update_app.sh --undo"
open "$DEST/$APP"
