#!/bin/zsh
# Build and run the wire watcher: what goes out and what comes back while signing on.
#
# Links this application's own libpurple, from ad hoc signed copies, because Apple Silicon
# refuses to load the unsigned frameworks in the tree. Needs the test server running:
# Testing/xmpp/server.sh start
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

# The framework copies are made once and kept; refresh libpurple every time, since the whole
# point is to watch a libpurple that was just changed.
cp "$ROOT/Frameworks/libpurple.framework/Versions/0/libpurple" \
   "$HARNESS/Frameworks/libpurple.framework/Versions/0/libpurple"
codesign -f -s - "$HARNESS/Frameworks/libpurple.framework" >/dev/null 2>&1 || true

xcrun clang -o "$HARNESS/bin/smwire" smwire.c \
	-I "$ROOT/Frameworks/libpurple.framework/Headers" \
	-I "$ROOT/Frameworks/libglib.framework/Headers" \
	-F"$ROOT/Frameworks" -framework libpurple -framework libglib

exec "$HARNESS/bin/smwire" "$@"
