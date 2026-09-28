#!/bin/bash -eu
#
# Photographs the voice recorder's shelf without running Adium, and without a
# microphone: the view is shown states it is handed, with a made up loudness.
#
# The view is built from its own sources against the frameworks, with a stand-in
# for the program that answers every question with nothing; the view asks none
# it cannot do without unless something goes wrong. The recorder is linked in,
# since the view speaks to it, but never started.
#
# Usage:  Testing/ui/voice/voice-shots.sh [output folder]
#
# VOICE_SHOTS_FRAMEWORKS names a folder that already holds a Debug build of the
# frameworks (the Debug folder of some SYMROOT); given it, nothing is built.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="${1:-$ROOT/build/voice-shots}"
FWROOT="$ROOT/build/voice-shots-fw"
FRAMEWORKS="${VOICE_SHOTS_FRAMEWORKS:-$FWROOT/Debug}"
OPUS="$ROOT/Frameworks/opus"

mkdir -p "$OUT"

if [ -z "${VOICE_SHOTS_FRAMEWORKS:-}" ]; then
	# The frameworks only, not the application: build/Debug/Adium.app is what
	# the symlink in /Applications points at, and it may be running right now.
	xcodebuild -project "$ROOT/Adium.xcodeproj" -target Adium.Framework -configuration Debug \
		SYMROOT="$FWROOT" OBJROOT="$FWROOT/Intermediates" build > "$FWROOT.log" 2>&1 || {
			echo "Building the framework failed, see $FWROOT.log" >&2
			tail -20 "$FWROOT.log" >&2
			exit 1
		}
fi

APP="$OUT/VoiceShots.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>voiceshots</string>
	<key>CFBundleIdentifier</key><string>com.adium.harness.voiceshots</string>
	<key>CFBundleName</key><string>VoiceShots</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

for fw in Adium AIUtilities AutoHyperlinks MMTabBarView; do
	[ -d "$FRAMEWORKS/$fw.framework" ] && ln -sf "$FRAMEWORKS/$fw.framework" "$APP/Contents/Frameworks/$fw.framework"
done

clang -fobjc-arc -fmodules -framework Cocoa -framework AVFoundation \
	-F"$FRAMEWORKS" -framework Adium -framework AIUtilities \
	-Wl,-rpath,@executable_path/../Frameworks \
	-I"$ROOT/Source" -I"$ROOT/Frameworks/Adium/Source" \
	-I"$ROOT/Plugins/Dual Window Interface" \
	-I"$OPUS/include" -I"$OPUS/include/opus" \
	-include "$ROOT/Adium.pch" \
	-o "$APP/Contents/MacOS/voiceshots" \
	"$ROOT/Testing/ui/voice/main.m" \
	"$ROOT/Source/AIVoiceNoteShelfView.m" \
	"$ROOT/Source/AIVoiceRecorder.m" \
	"$ROOT/Source/AIOpusEncoder.m" \
	"$OPUS/lib/libopus.a" "$OPUS/lib/libogg.a"

codesign -f -s - "$APP" >/dev/null 2>&1 || true

VOICE_OUT="$OUT" "$APP/Contents/MacOS/voiceshots"

echo
echo "The pictures are in $OUT"
