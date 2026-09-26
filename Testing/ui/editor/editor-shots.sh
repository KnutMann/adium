#!/bin/bash -eu
#
# Photographs the contact list appearance editor without running Adium.
#
# Der Editor fragt das Programm nur nach einer Sache, dem Einstellungsspeicher.
# Ein Stellvertreter, der die Werte in einem Woerterbuch haelt, genuegt also,
# um das ganze Fenster auf den Schirm zu bringen. Nichts an den echten
# Einstellungen wird gelesen oder geschrieben.
#
# Aufruf:  Testing/ui/editor/editor-shots.sh [Zielordner]

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="${1:-$ROOT/build/editor-shots}"
FWROOT="$ROOT/build/editor-shots-fw"

mkdir -p "$OUT"

# Nur das Geruest bauen, nicht die Anwendung: build/Debug/Adium.app ist das Ziel
# des Symlinks in /Applications und laeuft womoeglich gerade.
xcodebuild -project "$ROOT/Adium.xcodeproj" -target Adium.Framework -configuration Debug \
	SYMROOT="$FWROOT" OBJROOT="$FWROOT/Intermediates" build > "$FWROOT.log" 2>&1 || {
		echo "Bau des Geruests fehlgeschlagen, siehe $FWROOT.log" >&2
		tail -20 "$FWROOT.log" >&2
		exit 1
	}

APP="$FWROOT/EditorShots.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>editorshots</string>
	<key>CFBundleIdentifier</key><string>com.adium.harness.editorshots</string>
	<key>CFBundleName</key><string>EditorShots</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

for fw in Adium AIUtilities AutoHyperlinks MMTabBarView; do
	[ -d "$FWROOT/Debug/$fw.framework" ] && ln -sf "$FWROOT/Debug/$fw.framework" "$APP/Contents/Frameworks/$fw.framework"
done

clang -fobjc-arc -fmodules -framework Cocoa \
	-F"$FWROOT/Debug" -framework Adium -framework AIUtilities \
	-Wl,-rpath,@executable_path/../Frameworks \
	-I"$ROOT/Source" -I"$ROOT/Frameworks/Adium/Source" \
	-o "$APP/Contents/MacOS/editorshots" \
	"$ROOT/Testing/ui/editor/main.m" \
	"$ROOT/Source/AIContactListAppearancePage.m"

codesign -f -s - "$APP" >/dev/null 2>&1 || true

EDITOR_ROOT="$ROOT" EDITOR_OUT="$OUT" "$APP/Contents/MacOS/editorshots"

echo
echo "Bilder liegen in $OUT"
