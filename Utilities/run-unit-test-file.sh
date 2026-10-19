#!/bin/bash
# Build one or more unit test files into a throwaway bundle and run them, without xcodebuild.
#
# Usage:  Utilities/run-unit-test-file.sh UnitTests/TestFoo.m [UnitTests/TestBar.m ...]
#         Utilities/run-unit-test-file.sh --products DIR UnitTests/TestFoo.m ...
#
# With --products, a framework found in DIR (a build products directory such as the
# Release folder of a private SYMROOT) is taken from there instead of from the built
# application, headers included. That is how a fix to AIUtilities, Adium.framework or
# AutoHyperlinks is tested before it goes anywhere near build/: build the one target
# into a directory of your own and point the runner at it.
#
# For iterating on a single test file, and for several people or agents doing so at once:
# xcodebuild writes to build/ and two of them collide, while this compiles only the files
# named, against the frameworks a previous ./install.sh --build-only left in build/Release,
# into a bundle under a temporary directory of its own. What xcrun xctest says is the result,
# and its exit status is this script's. The files see the same prefix header, helpers and
# resources the real bundle gives them, and may import <Adium/...> and <AutoHyperlinks/...>
# as well as <AIUtilities/...>.
#
# Not a substitute for the whole bundle: the project file decides what ships, so a new test
# file still has to be added to the "Unit tests" target there.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP_FRAMEWORKS="$REPO/build/Release/Adium.app/Contents/Frameworks"
PRODUCTS=""
if [ "${1:-}" = "--products" ]; then
	PRODUCTS="$(cd "$2" && pwd)"; shift 2
fi
[ $# -ge 1 ] || { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }
[ -d "$APP_FRAMEWORKS/Adium.framework" ] \
	|| { echo "No built application in build/Release; run ./install.sh --build-only first." >&2; exit 1; }

PLATFORM="$(xcrun --show-sdk-platform-path)"
SDK="$(xcrun --show-sdk-path)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/adium-unit-test.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT
BUNDLE="$OUT/OneFile.xctest"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>OneFile</string>
	<key>CFBundleIdentifier</key><string>com.adiumX.unit-tests.one-file</string>
	<key>CFBundlePackageType</key><string>BNDL</string>
	<key>CFBundleName</key><string>OneFile</string>
	<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST

# What the real bundle's Resources phase carries: the sample files beside the tests, the
# scripting definition the coercion tests load, and the Fixtures folder as a folder.
cp "$REPO"/UnitTests/*.txt "$REPO/Resources/Adium.sdef" "$BUNDLE/Contents/Resources/"
[ -d "$REPO/UnitTests/Fixtures" ] && cp -R "$REPO/UnitTests/Fixtures" "$BUNDLE/Contents/Resources/"

# Headers come from the frameworks in build/Release, which still have theirs; the copies in
# the application lost them on the way in. Two links under a private include directory let
# <AIUtilities/X.h> and <Adium/X.h> resolve without showing the linker build/Release, whose
# frameworks carry the names that do not load here.
# headers_of NAME answers the directory whose NAME.framework carries headers: the products
# directory when it has that framework, build/Release otherwise.
headers_of() {
	if [ -n "$PRODUCTS" ] && [ -d "$PRODUCTS/$1.framework/Versions/A/Headers" ]; then
		echo "$PRODUCTS/$1.framework/Versions/A/Headers"
	else
		echo "$REPO/build/Release/$1.framework/Versions/A/Headers"
	fi
}
mkdir -p "$OUT/include"
for one in AIUtilities Adium AutoHyperlinks; do
	ln -s "$(headers_of "$one")" "$OUT/include/$one"
done

# The frameworks travel with the bundle, as the real one carries AIUtilities: xctest ignores
# DYLD_FRAMEWORK_PATH, and Adium.framework names its neighbours relative to the application's
# executable, which here is xctest itself. So the application's own signed copies are taken,
# the names in the Adium copy are pointed at the run path, and the copies are signed ad hoc
# again, because changing a name voids a signature and arm64 loads nothing unsigned.
FW="$BUNDLE/Contents/Frameworks"
mkdir -p "$FW"
for one in Adium AIUtilities AutoHyperlinks MMTabBarView; do
	if [ -n "$PRODUCTS" ] && [ -d "$PRODUCTS/$one.framework" ]; then
		echo "taking $one.framework from $PRODUCTS"
		cp -R "$PRODUCTS/$one.framework" "$FW/"
	else
		cp -R "$APP_FRAMEWORKS/$one.framework" "$FW/"
	fi
done
adium="$FW/Adium.framework/Versions/A/Adium"
install_name_tool -id "@rpath/Adium.framework/Versions/A/Adium" \
	-change "@executable_path/../Frameworks/Adium.framework/Versions/A/Adium" "@rpath/Adium.framework/Versions/A/Adium" \
	-change "@executable_path/../Frameworks/AutoHyperlinks.framework/Versions/A/AutoHyperlinks" "@rpath/AutoHyperlinks.framework/Versions/A/AutoHyperlinks" \
	"$adium" 2>/dev/null
install_name_tool -id "@rpath/AutoHyperlinks.framework/Versions/A/AutoHyperlinks" \
	"$FW/AutoHyperlinks.framework/Versions/A/AutoHyperlinks" 2>/dev/null
for one in "$FW"/*.framework; do codesign --force --sign - "$one" 2>/dev/null; done

clang -arch arm64 -isysroot "$SDK" -mmacosx-version-min=13.0 -fobjc-arc -bundle \
	-Wall -Wno-unused-variable \
	-include "$REPO/UnitTests/UnitTests_Prefix.pch" -I "$REPO/UnitTests" \
	-I "$OUT/include" -F "$FW" -F "$PLATFORM/Developer/Library/Frameworks" \
	-framework Cocoa -framework XCTest -framework AIUtilities -framework Adium -framework AutoHyperlinks \
	-Wl,-rpath,"$PLATFORM/Developer/Library/Frameworks" \
	-Wl,-rpath,"$PLATFORM/Developer/usr/lib" \
	-Wl,-rpath,@loader_path/../Frameworks \
	-o "$BUNDLE/Contents/MacOS/OneFile" "$@"

codesign --force --sign - "$BUNDLE" 2>/dev/null

xcrun xctest "$BUNDLE"
