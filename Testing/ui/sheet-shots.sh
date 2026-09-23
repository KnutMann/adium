#!/bin/bash -eu
#
# Draws a nib's window without running Adium, one picture per tab, in both
# appearances, plus a text listing of every control with its position.
#
# Why this exists: the two contact list editors are sheets deep inside the
# preferences, and judging their layout meant clicking there and squinting.
# This builds a throwaway app that loads the nib with a stand-in owner carrying
# the same outlets, walks the tabs, and photographs each one.
#
# Usage:  Testing/ui/sheet-shots.sh [output directory]
#
# Notes:
#  - The pictures come from the window server, because today's controls hang
#    their appearance in hosted layers: caching the view or printing it comes
#    back with the labels and empty holes where the buttons should be. Screen
#    recording must therefore be allowed for the terminal.
#  - The window is shown for a moment while it is photographed.
#  - Set SHEETS_CLIP=1 to hold every custom preview view inside its own frame,
#    which is how you tell a drawing that escapes its view from one that does not.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/build/sheet-shots}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SHEETS=(ListThemeSheet ListLayoutSheet)
OWNERS=(AIListThemeWindowController AIListLayoutWindowController)
STEMS=(farben layout)

mkdir -p "$OUT" "$WORK/nibs" "$WORK/inc/AIUtilities" "$WORK/inc/Adium"

# Stand-in owner classes, generated from the real headers so they cannot drift.
python3 - "$ROOT" "$WORK" <<'PY'
import re, sys, os
root, work = sys.argv[1], sys.argv[2]
specs = [("AIListThemeWindowController", "Source/AIListThemeWindowController.h",
          ["cancel:", "okay:", "preferenceChanged:", "selectBackgroundImage:"]),
         ("AIListLayoutWindowController", "Source/AIListLayoutWindowController.h",
          ["cancel:", "okay:", "preferenceChanged:", "chooseFontWithFontPanel:"])]
h = ["#import <Cocoa/Cocoa.h>\n", "@class AITextColorPreviewView, JVFontPreviewField;\n"]
m = ['#import "stubs.h"\n']
for cls, path, actions in specs:
    src = open(os.path.join(root, path), encoding="utf-8").read()
    outlets = re.findall(r'IBOutlet\s+([A-Za-z_][A-Za-z0-9_]*)\s*\*\s*([A-Za-z_][A-Za-z0-9_]*)\s*;', src)
    h.append("@interface %s : NSObject {" % cls)
    h.append("\tIBOutlet NSWindow *window;")
    h += ["\tIBOutlet %s *%s;" % (t, n) for t, n in outlets]
    h.append("}")
    h.append("@property (readonly) NSWindow *window;")
    h += ["- (IBAction)%s(id)sender;" % (a[:-1] + ":") for a in actions]
    h.append("@end\n")
    m.append("@implementation %s" % cls)
    m.append("- (NSWindow *)window { return window; }")
    # The nibs bind straight to the preference controller, which is not here.
    m.append("- (void)addObserver:(NSObject *)o forKeyPath:(NSString *)k options:(NSKeyValueObservingOptions)p context:(void *)c { }")
    m.append("- (void)removeObserver:(NSObject *)o forKeyPath:(NSString *)k { }")
    m.append("- (void)removeObserver:(NSObject *)o forKeyPath:(NSString *)k context:(void *)c { }")
    m.append("- (id)valueForUndefinedKey:(NSString *)key { return nil; }")
    m.append("- (void)setValue:(id)value forUndefinedKey:(NSString *)key { }")
    m.append("- (id)valueForKeyPath:(NSString *)keyPath { return nil; }")
    m += ["- (IBAction)%s(id)sender { }" % (a[:-1] + ":") for a in actions]
    m.append("@end\n")
open(os.path.join(work, "stubs.h"), "w").write("\n".join(h))
open(os.path.join(work, "stubs.m"), "w").write("\n".join(m))
PY

# The two headers the borrowed sources ask for, reduced to what they use.
cp "$ROOT/Testing/ui/sheets/shim.h" "$WORK/inc/AIUtilities/AIParagraphStyleAdditions.h"
echo '
#define AILocalizedString(key, comment) (key)' >> "$WORK/inc/AIUtilities/AIParagraphStyleAdditions.h"
cp "$ROOT/Frameworks/Adium/Source/JVFontPreviewField.h" "$WORK/inc/Adium/JVFontPreviewField.h"

for sheet in "${SHEETS[@]}"; do
	ibtool --compile "$WORK/nibs/$sheet.nib" "$ROOT/Resources/$sheet.xib"
done

APP="$WORK/Sheets.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>sheets</string>
	<key>CFBundleIdentifier</key><string>com.adium.harness.sheets</string>
	<key>CFBundleName</key><string>Sheets</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

clang -fobjc-arc -include Cocoa/Cocoa.h -framework Cocoa \
	-I"$WORK" -I"$WORK/inc" -I"$ROOT/Source" -I"$ROOT/Frameworks/Adium/Source" \
	-o "$APP/Contents/MacOS/sheets" \
	"$ROOT/Testing/ui/sheets/main.m" "$WORK/stubs.m" "$ROOT/Testing/ui/sheets/shim.m" \
	"$ROOT/Source/AITextColorPreviewView.m" "$ROOT/Frameworks/Adium/Source/JVFontPreviewField.m"

codesign -f -s - "$APP" >/dev/null 2>&1 || true

SHEETS_NIBS="$WORK/nibs" SHEETS_OUT="$OUT" "$APP/Contents/MacOS/sheets"

echo
echo "Bilder und Aufbaulisten liegen in $OUT"
