#!/bin/zsh
# Build and run the check that a stanza survives being written out and read back, which is the
# detour the counted send path requires for the two callers that hold text rather than a tree.
#
# Links this application's own libpurple. The frameworks in the tree are unsigned and arm64 will
# not load unsigned code, so copies are made beside the test binary and signed ad hoc.
set -e
cd "$(dirname "$0")"

ROOT="$(cd ../.. && pwd)"
HARNESS="${TMPDIR:-/tmp}/adium-omemo-harness"

if [ ! -d "$HARNESS/Frameworks" ]; then
	mkdir -p "$HARNESS/bin" "$HARNESS/Frameworks"
	cp -R "$ROOT/Frameworks/"*.framework "$HARNESS/Frameworks/"
	cp "$ROOT/Frameworks/"*.dylib "$HARNESS/Frameworks/" 2>/dev/null || true
	for one in "$HARNESS/Frameworks/"*; do codesign -f -s - "$one" >/dev/null 2>&1 || true; done
fi
mkdir -p "$HARNESS/bin"

xcrun clang -fobjc-arc -framework Foundation \
	-I"$ROOT/Frameworks/libpurple.framework/Headers" \
	-I"$ROOT/Frameworks/libglib.framework/Headers" \
	-F"$ROOT/Frameworks" -framework libpurple -framework libglib \
	sendpath-test.m -o "$HARNESS/bin/sendpath-test"

exec "$HARNESS/bin/sendpath-test"
