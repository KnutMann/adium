#!/bin/bash -eu
#
# Photographs Adiums Kontaktliste, ohne Adium zu starten.
#
# Warum es das gibt: der Neubau der Listenzeichnung braucht Vorher-Bilder zum
# Vergleichen, und die laufende Adium des Nutzers zeigt echte Kontakte. Dieses
# Programm baut eine erfundene Liste aus echten AIListGroup- und
# AIListContact-Objekten, uebergibt sie einem echten AIAbstractListController
# mit einer echten AIListOutlineView und fotografiert jeden Fensterstil sowie
# jede mitgelieferte Gestaltung und jedes Motiv, hell und dunkel.
#
# Aufruf:  Testing/ui/contactlist/list-shots.sh [Zielordner]
#
# Hinweise:
#  - Die Bilder kommen vom Fensterserver (screencapture), weil die heutigen
#    Bedienelemente ihr Aussehen in Schichten haengen, die ein
#    cacheDisplayInRect: nicht sieht. Der Bildschirmaufnahme muss also fuer das
#    Terminal erlaubt sein.
#  - Die Fenster erscheinen kurz auf dem Bildschirm.
#  - Die laufende Adium wird nicht angefasst: kein Bauen ins Programmbuendel,
#    keine Einstellung gelesen oder geschrieben.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="${1:-$ROOT/build/list-shots}"
FWROOT="$ROOT/build/list-shots-fw"

mkdir -p "$OUT"

# Nur das Gerüst bauen, nicht die Anwendung: build/Debug/Adium.app ist das
# Ziel des Symlinks in /Applications, und dort laeuft womoeglich gerade die
# Adium des Nutzers.
xcodebuild -project "$ROOT/Adium.xcodeproj" -target Adium.Framework -configuration Debug \
	SYMROOT="$FWROOT" OBJROOT="$FWROOT/Intermediates" build > "$FWROOT.log" 2>&1 || {
		echo "Bau des Geruests fehlgeschlagen, siehe $FWROOT.log" >&2
		tail -20 "$FWROOT.log" >&2
		exit 1
	}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

APP="$WORK/ListShots.app"
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

# Die Gerueste tragen als Ladenamen @executable_path/../Frameworks, also
# muessen sie genau dort liegen. Ein Verweis genuegt, kopiert wird nichts.
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
echo "Bilder und Aufbauliste liegen in $OUT"
