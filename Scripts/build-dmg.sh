#!/bin/zsh
# Builds the app and the screensaver and packs both into the release disk
# image dist/Rosettica-<version>-macos-arm64.dmg (version from
# Resources/Info.plist): a window with a backdrop, the
# app next to an Applications shortcut, and the screensaver below.
#
# Finder itself lays the window out (it is scripted via osascript), so this
# briefly opens a Finder window, and macOS may ask once for permission to
# control Finder.
#
# Adapted from Polymandala's script, including its Finder workarounds.
set -euo pipefail
cd "$(dirname "$0")/.."

VOLUME="Rosettica"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="dist/Rosettica-${VERSION}-macos-arm64.dmg"
APP="Rosettica.app"
SAVER="Rosettica.saver"
# Window content size; Tools/dmgbackground.swift draws the backdrop for it and
# around the icon positions used further down. The window is a little taller
# than the layout needs, in case Finder's title bar (or a tab bar) is taller
# than the 28 points assumed here.
WIDTH=680
HEIGHT=460
TITLEBAR=28

Scripts/build-app.sh
Scripts/build-saver.sh

# Under /tmp, not the per-user temporary folder: Finder's alias to the
# backdrop records the path of the writable image, and that path ships.
WORK=$(mktemp -d /tmp/rosettica-dmg.XXXXXX)
MOUNT=""
cleanup() {
    [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

# Backdrop at 1x and 2x in one TIFF, so it is sharp on Retina displays.
swift Tools/dmgbackground.swift "$WORK/background.png" 1
swift Tools/dmgbackground.swift "$WORK/background@2x.png" 2
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" \
    -out "$WORK/background.tiff" 2>/dev/null

STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
cp -R "dist/$APP" "dist/$SAVER" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$WORK/background.tiff" "$STAGE/.background/background.tiff"

# A writable image first: Finder stores the window layout inside the volume.
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ \
    -format UDRW -size 32m "$WORK/rw.dmg"
MOUNT=$(hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen \
    | awk -F'\t' '/\/Volumes\// { print $NF }')
DISK=$(basename "$MOUNT") # differs from $VOLUME if that name is already mounted

# Order matters. The first time the window is reopened after its settings
# changed, Finder (seen on macOS 27) moves every icon 36 points down. So the
# window is set up and reopened *before* the icons are placed, and the script
# fails if a final reopen still finds them somewhere else.
#
# The app and the screensaver share the name "Rosettica"; the screensaver
# keeps its visible .saver extension so the two labels differ.
osascript <<OSA
on place(itemName, x, y)
    tell application "Finder" to set position of item itemName of container window of disk "$DISK" to {x, y}
end place
on check(itemName, x, y)
    tell application "Finder" to set p to position of item itemName of container window of disk "$DISK"
    if (item 1 of p) is not x or (item 2 of p) is not y then
        error "Finder moved " & itemName & " to " & (item 1 of p) & "," & (item 2 of p)
    end if
end check
tell application "Finder"
    tell disk "$DISK"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, $((200 + WIDTH)), $((120 + HEIGHT + TITLEBAR))}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set label position of viewOptions to bottom
        set background picture of viewOptions to file ".background:background.tiff"
        close
        open
        delay 1
    end tell
end tell
place("$APP", 180, 150)
place("Applications", 500, 150)
place("$SAVER", 180, 330)
tell application "Finder"
    tell disk "$DISK"
        set extension hidden of item "$SAVER" to false
        close
        open
        delay 1
    end tell
end tell
check("$APP", 180, 150)
check("Applications", 500, 150)
check("$SAVER", 180, 330)
tell application "Finder"
    tell disk "$DISK"
        update without registering applications
        delay 2
        close
    end tell
end tell
OSA

# Finder writes the layout lazily; do not unmount before it is on disk.
for _ in {1..20}; do
    [ -s "$MOUNT/.DS_Store" ] && break
    sleep 0.5
done
[ -s "$MOUNT/.DS_Store" ] || { echo "error: Finder did not save the window layout" >&2; exit 1; }

# The volume shows the app's icon on the desktop and in Finder's sidebar.
cp "dist/$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
rm -rf "$MOUNT/.fseventsd" "$MOUNT/.Trashes"
sync
hdiutil detach "$MOUNT" -quiet
MOUNT=""

rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
hdiutil verify -quiet "$DMG"
echo "Built $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
