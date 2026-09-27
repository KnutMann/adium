#!/bin/bash -eu
#
# Photographs Adium's contact list without starting Adium.
#
# Why this exists: rebuilding the way the list draws itself needs before
# pictures to compare against, and the user's running Adium shows real
# contacts. This program builds a made up list out of real AIListGroup and
# AIListContact objects, hands it to a real AIAbstractListController with a
# real AIListOutlineView, and photographs every window style as well as every
# layout and theme that ships with Adium, light and dark.
#
# Usage:  Testing/ui/contactlist/list-shots.sh [output directory]
#
# Notes:
#  - The pictures come from the window server (screencapture), because today's
#    controls hang their looks in layers that a cacheDisplayInRect: never sees.
#    Screen recording must therefore be permitted for the terminal.
#  - The windows appear on screen for a moment.
#  - The running Adium is left alone: nothing is built into its bundle, and no
#    preference is read or written.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="${1:-$ROOT/build/list-shots}"
FWROOT="$ROOT/build/list-shots-fw"

mkdir -p "$OUT"

# Build only the framework, not the application: build/Debug/Adium.app is what
# the symlink in /Applications points at, and the user's Adium may be running
# from there right now.
xcodebuild -project "$ROOT/Adium.xcodeproj" -target Adium.Framework -configuration Debug \
	SYMROOT="$FWROOT" OBJROOT="$FWROOT/Intermediates" build > "$FWROOT.log" 2>&1 || {
		echo "Building the framework failed, see $FWROOT.log" >&2
		tail -20 "$FWROOT.log" >&2
		exit 1
	}

# The bundle lives in the build directory, not in /tmp: LaunchServices refuses
# to start a program out of a throwaway directory (error -10810), and without
# LaunchServices it never becomes the frontmost program.
APP="$FWROOT/ListShots.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>listshots</string>
	<key>CFBundleIdentifier</key><string>com.adium.harness.listshots</string>
	<key>CFBundleName</key><string>ListShots</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

# The frameworks carry @executable_path/../Frameworks as their load name, so
# that is exactly where they have to sit. A link is enough, nothing is copied.
mkdir -p "$APP/Contents/Frameworks"
for fw in Adium AIUtilities AutoHyperlinks MMTabBarView; do
	[ -d "$FWROOT/Debug/$fw.framework" ] && ln -sf "$FWROOT/Debug/$fw.framework" "$APP/Contents/Frameworks/$fw.framework"
done

clang -fobjc-arc -fmodules -framework Cocoa \
	-F"$FWROOT/Debug" -framework Adium -framework AIUtilities \
	-Wl,-rpath,@executable_path/../Frameworks \
	-o "$APP/Contents/MacOS/listshots" \
	"$ROOT/Testing/ui/contactlist/main.m"

codesign -f -s - "$APP" >/dev/null 2>&1 || true

LIST_ROOT="$ROOT" LIST_OUT="$OUT" "$APP/Contents/MacOS/listshots"

echo
echo "Pictures and the list of what was built are in $OUT"
