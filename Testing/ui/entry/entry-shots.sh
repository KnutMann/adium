#!/bin/bash -eu
#
# Photographs the message field with its accessory buttons, without running Adium.
#
# The field asks the program for one thing, the preference store, and answers
# from a stand-in are enough to put it on screen. Nothing of the real settings
# is read or written. The pictures show the row of buttons at the right edge,
# in both appearances, and that the text ends where the buttons begin.
#
# Usage:  Testing/ui/entry/entry-shots.sh [output folder]
#
# ENTRY_SHOTS_FRAMEWORKS names a folder that already holds a Debug build of the
# frameworks (a build/Debug of some SYMROOT); given it, nothing is built here.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="${1:-$ROOT/build/entry-shots}"
FWROOT="$ROOT/build/entry-shots-fw"
FRAMEWORKS="${ENTRY_SHOTS_FRAMEWORKS:-$FWROOT/Debug}"

mkdir -p "$OUT"

if [ -z "${ENTRY_SHOTS_FRAMEWORKS:-}" ]; then
	# The frameworks only, not the application: build/Debug/Adium.app is what
	# the symlink in /Applications points at, and it may be running right now.
	xcodebuild -project "$ROOT/Adium.xcodeproj" -target Adium.Framework -configuration Debug \
		SYMROOT="$FWROOT" OBJROOT="$FWROOT/Intermediates" build > "$FWROOT.log" 2>&1 || {
			echo "Building the framework failed, see $FWROOT.log" >&2
			tail -20 "$FWROOT.log" >&2
			exit 1
		}
fi

APP="$OUT/EntryShots.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>entryshots</string>
	<key>CFBundleIdentifier</key><string>com.adium.harness.entryshots</string>
	<key>CFBundleName</key><string>EntryShots</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

for fw in Adium AIUtilities AutoHyperlinks MMTabBarView; do
	[ -d "$FRAMEWORKS/$fw.framework" ] && ln -sf "$FRAMEWORKS/$fw.framework" "$APP/Contents/Frameworks/$fw.framework"
done

# The pictures the buttons carry, from the application's own resources, so the
# harness shows the files that ship and not copies of its own.
cp "$ROOT"/Resources/entry_*.png "$APP/Contents/Resources/"

clang -fobjc-arc -fmodules -framework Cocoa \
	-F"$FRAMEWORKS" -framework Adium -framework AIUtilities \
	-Wl,-rpath,@executable_path/../Frameworks \
	-o "$APP/Contents/MacOS/entryshots" \
	"$ROOT/Testing/ui/entry/main.m"

codesign -f -s - "$APP" >/dev/null 2>&1 || true

ENTRY_OUT="$OUT" "$APP/Contents/MacOS/entryshots"

echo
echo "The pictures are in $OUT"
