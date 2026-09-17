#!/bin/zsh
# Build and run the check that the XEP-0198 queue belongs to an account rather than to its name.
#
# Compiles the real stream_management.c, with stand-ins only for the three things it calls from
# the rest of the jabber plugin, against this application's own libpurple. The frameworks in the
# tree are unsigned and arm64 will not load unsigned code, so copies are made beside the test
# binary and signed ad hoc.
set -e
cd "$(dirname "$0")"

ROOT="$(cd ../.. && pwd)"
SRC="$ROOT/Dependencies/source/libpurple"
HARNESS="${TMPDIR:-/tmp}/adium-omemo-harness"

if [ ! -d "$SRC/libpurple/protocols/jabber/stream_management.c" ] && [ ! -f "$SRC/libpurple/protocols/jabber/stream_management.c" ]; then
	echo "libpurple source not unpacked at $SRC; run Dependencies/build.sh --download-libpurple" >&2
	exit 1
fi

if [ ! -d "$HARNESS/Frameworks" ]; then
	mkdir -p "$HARNESS/bin" "$HARNESS/Frameworks"
	cp -R "$ROOT/Frameworks/"*.framework "$HARNESS/Frameworks/"
	cp "$ROOT/Frameworks/"*.dylib "$HARNESS/Frameworks/" 2>/dev/null || true
	for one in "$HARNESS/Frameworks/"*; do codesign -f -s - "$one" >/dev/null 2>&1 || true; done
fi
mkdir -p "$HARNESS/bin"

xcrun clang -o "$HARNESS/bin/smsession-test" smsession-test.c \
	-I smshim \
	-I "$SRC/libpurple/protocols/jabber" -I "$SRC/libpurple" -I "$SRC" \
	-I "$ROOT/Dependencies/build/include" \
	-I "$ROOT/Dependencies/build/include/glib-2.0" \
	-I "$ROOT/Dependencies/build/lib/glib-2.0/include" \
	-I "$ROOT/Dependencies/build/include/libxml2" \
	-F"$ROOT/Frameworks" -framework libpurple -framework libglib

exec "$HARNESS/bin/smsession-test"
