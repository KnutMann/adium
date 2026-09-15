#!/bin/zsh
# Build and run the XEP-0392 check: does our nickname colour land on the same hue angle
# every other client computes? Needs AIUtilities.framework, so build the app first.
set -e
cd "$(dirname "$0")"

BUILT="$(cd ../.. && pwd)/build/Debug"
[ -d "$BUILT/AIUtilities.framework" ] || {
	echo "AIUtilities.framework fehlt, bitte zuerst das Projekt bauen."; exit 1; }

clang -fobjc-arc -framework Foundation -framework AppKit \
	-F "$BUILT" -framework AIUtilities \
	nickcolor-test.m -o "$BUILT/nickcolor-test" -Wl,-rpath,"$BUILT"
exec "$BUILT/nickcolor-test"
