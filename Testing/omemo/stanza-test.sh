#!/bin/zsh
# Build and run the check on the OMEMO stanza itself, against the real xmlnode from libpurple.
#
# That last part needs explaining, because it was a blocker for a long time. The frameworks in
# this tree are not signed at all, and arm64 will not load unsigned code, so a test binary that
# links them is killed outright with no message. Copying them next to the binary and signing the
# copies ad hoc gets around it, and touches nothing in the tree.
set -e
cd "$(dirname "$0")"

PICO=../../Dependencies/picomemo
"$PICO/fetch-picomemo.sh"

ROOT="$(cd ../.. && pwd)"
HARNESS="${TMPDIR:-/tmp}/adium-omemo-harness"

# The frameworks, copied and signed so that dyld will load them outside the application bundle
if [ ! -d "$HARNESS/Frameworks" ] || [ "$ROOT/Frameworks" -nt "$HARNESS/Frameworks" ]; then
	rm -rf "$HARNESS"
	mkdir -p "$HARNESS/bin" "$HARNESS/Frameworks"
	cp -R "$ROOT/Frameworks/"*.framework "$HARNESS/Frameworks/"
	cp "$ROOT/Frameworks/"*.dylib "$HARNESS/Frameworks/" 2>/dev/null || true
	for one in "$HARNESS/Frameworks/"*; do codesign -f -s - "$one" >/dev/null 2>&1 || true; done
fi
mkdir -p "$HARNESS/bin"

SSL="$(brew --prefix openssl@3 2>/dev/null || echo /opt/homebrew/opt/openssl@3)"
xcrun clang -fobjc-arc -framework Foundation \
	-I"$PICO/picomemo/gen" -I"$ROOT/Plugins/Purple Service" -I"$SSL/include" \
	-I"$ROOT/Frameworks/libpurple.framework/Headers" \
	-I"$ROOT/Frameworks/libglib.framework/Headers" \
	-F"$ROOT/Frameworks" -framework libpurple -framework libglib \
	stanza-test.m \
	"$ROOT/Plugins/Purple Service/AIOMEMOStore.m" \
	"$ROOT/Plugins/Purple Service/AIOMEMOMessage.m" \
	"$ROOT/Plugins/Purple Service/AIOMEMOStanza.m" \
	"$PICO/picomemo/o/libpicomemo.a" -L"$SSL/lib" -lcrypto \
	-o "$HARNESS/bin/stanza-test"

exec "$HARNESS/bin/stanza-test"
