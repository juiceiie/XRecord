#!/bin/bash

set -euo pipefail

APP_PATH="${1:?Usage: create-dmg.sh /path/to/XRecord.app /path/to/output.dmg}"
OUTPUT_PATH="${2:?Usage: create-dmg.sh /path/to/XRecord.app /path/to/output.dmg}"
VOLUME_NAME="XRecord"
WORK_DIR="$(mktemp -d /tmp/xrecord-dmg.XXXXXX)"
RW_DMG="$WORK_DIR/XRecord-rw.dmg"
MOUNT_DIR="/Volumes/$VOLUME_NAME"

cleanup() {
    hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR/source"
ditto "$APP_PATH" "$WORK_DIR/source/XRecord.app"
ln -s /Applications "$WORK_DIR/source/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$WORK_DIR/source" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$RW_DMG" >/dev/null

hdiutil attach "$RW_DMG" \
    -readwrite \
    -noverify \
    -noautoopen \
    -nobrowse >/dev/null

sleep 1
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {200, 200, 860, 600}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set text size of theViewOptions to 14
        set position of item "XRecord.app" of container window to {165, 190}
        set position of item "Applications" of container window to {495, 190}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" -quiet
mkdir -p "$(dirname "$OUTPUT_PATH")"
hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$OUTPUT_PATH" >/dev/null

echo "Created $OUTPUT_PATH"
