#!/bin/zsh
# Build and run the registration watcher: what libpurple reports, and in which order, while an
# account registers itself at the test server (XEP-0077).
#
#   ./regwire.sh                 the whole set: a fresh name three ways, then the same name again
#   ./regwire.sh <name> <pw> [fill|raw|cancel]   one run
#
# Needs the test server with registration switched on: Testing/xmpp/server.sh start (the
# configuration in this directory has it on). Names this script made up are deleted again.
set -e
cd "$(dirname "$0")"

ROOT="$(cd ../.. && pwd)"
HARNESS="${TMPDIR:-/tmp}/adium-omemo-harness"
CONTAINER=adium-xmpp

if [ ! -d "$HARNESS/Frameworks" ]; then
	mkdir -p "$HARNESS/bin" "$HARNESS/Frameworks"
	cp -R "$ROOT/Frameworks/"*.framework "$HARNESS/Frameworks/"
	cp "$ROOT/Frameworks/"*.dylib "$HARNESS/Frameworks/" 2>/dev/null || true
	for one in "$HARNESS/Frameworks/"*; do codesign -f -s - "$one" >/dev/null 2>&1 || true; done
fi
mkdir -p "$HARNESS/bin"

cp "$ROOT/Frameworks/libpurple.framework/Versions/0/libpurple" \
   "$HARNESS/Frameworks/libpurple.framework/Versions/0/libpurple"
codesign -f -s - "$HARNESS/Frameworks/libpurple.framework" >/dev/null 2>&1 || true

xcrun clang -o "$HARNESS/bin/regwire" regwire.c \
	-I "$ROOT/Frameworks/libpurple.framework/Headers" \
	-I "$ROOT/Frameworks/libglib.framework/Headers" \
	-F"$ROOT/Frameworks" -framework libpurple -framework libglib

if [ $# -ge 2 ]; then
	exec "$HARNESS/bin/regwire" "$@"
fi

NAME="regwire-$$"
cleanup() { docker exec "$CONTAINER" prosodyctl deluser "$NAME@localhost" >/dev/null 2>&1 || true; }
trap cleanup EXIT

for mode in cancel raw fill fill; do
	echo
	echo "===== $NAME, $mode ====="
	"$HARNESS/bin/regwire" "$NAME" "$NAME-pw" "$mode"
done
echo
echo "===== account on the server? ====="
docker exec "$CONTAINER" test -e "/var/lib/prosody/localhost/accounts/$NAME.dat" && echo "yes: $NAME@localhost exists" || echo "no"
