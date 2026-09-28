#!/bin/bash -eu
#
# Photographs the formula editor without running Adium.
#
# The editor is built from its own sources against the frameworks, with a
# stand-in for the program that answers the one question the editor asks it,
# the remembered formulas. Typst has to be installed, since the pictures in
# the editor are rendered by it, the way they are in the application.
#
# Usage:  Testing/ui/formula/formula-shots.sh [output folder]
#
# FORMULA_SHOTS_FRAMEWORKS names a folder that already holds a Debug build of
# the frameworks (the Debug folder of some SYMROOT); given it, nothing is built.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="${1:-$ROOT/build/formula-shots}"
FWROOT="$ROOT/build/formula-shots-fw"
FRAMEWORKS="${FORMULA_SHOTS_FRAMEWORKS:-$FWROOT/Debug}"

mkdir -p "$OUT"

if [ -z "${FORMULA_SHOTS_FRAMEWORKS:-}" ]; then
	# The frameworks only, not the application: build/Debug/Adium.app is what
	# the symlink in /Applications points at, and it may be running right now.
	xcodebuild -project "$ROOT/Adium.xcodeproj" -target Adium.Framework -configuration Debug \
		SYMROOT="$FWROOT" OBJROOT="$FWROOT/Intermediates" build > "$FWROOT.log" 2>&1 || {
			echo "Building the framework failed, see $FWROOT.log" >&2
			tail -20 "$FWROOT.log" >&2
			exit 1
		}
fi

APP="$OUT/FormulaShots.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>formulashots</string>
	<key>CFBundleIdentifier</key><string>com.adium.harness.formulashots</string>
	<key>CFBundleName</key><string>FormulaShots</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

for fw in Adium AIUtilities AutoHyperlinks MMTabBarView; do
	[ -d "$FRAMEWORKS/$fw.framework" ] && ln -sf "$FRAMEWORKS/$fw.framework" "$APP/Contents/Frameworks/$fw.framework"
done

clang -fobjc-arc -fmodules -framework Cocoa \
	-F"$FRAMEWORKS" -framework Adium -framework AIUtilities \
	-Wl,-rpath,@executable_path/../Frameworks \
	-I"$ROOT/Source" -I"$ROOT/Frameworks/Adium/Source" \
	-I"$ROOT/Plugins/Typst Formulas" -I"$ROOT/Plugins/Dual Window Interface" \
	-include "$ROOT/Adium.pch" \
	-o "$APP/Contents/MacOS/formulashots" \
	"$ROOT/Testing/ui/formula/main.m" \
	"$ROOT/Plugins/Typst Formulas/AITypstEditorView.m" \
	"$ROOT/Plugins/Typst Formulas/AITypstHistory.m" \
	"$ROOT/Plugins/Typst Formulas/AITypstRenderer.m"

codesign -f -s - "$APP" >/dev/null 2>&1 || true

FORMULA_OUT="$OUT" "$APP/Contents/MacOS/formulashots"

echo
echo "The pictures are in $OUT"
