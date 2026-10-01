#!/bin/zsh
# Build and run the check that a real MUC service answers a self-ping the way XEP-0410's table
# expects, and that the application's own reading of those real answers comes out right.
#
# Compiles the REAL rules file, Plugins/Purple Service/AIMUCSelfPingRules.c, against this
# application's own libpurple. The frameworks in the tree are unsigned and arm64 will not load
# unsigned code, so copies are made beside the test binary and signed ad hoc.
#
# NEEDS THE TEST SERVER: Testing/xmpp/server.sh start
# Without it the test says so and exits 0, because a missing server is not a failing rule.
set -e
cd "$(dirname "$0")"

ROOT="$(cd ../.. && pwd)"
RULES="$ROOT/Plugins/Purple Service"
HARNESS="${TMPDIR:-/tmp}/adium-omemo-harness"

# The port is asked directly rather than through server.sh, whose status command prints that
# the container is not running and then exits 0 like everything else.
if ! nc -z 127.0.0.1 5222 >/dev/null 2>&1; then
	echo "SKIPPED: nothing is listening on 127.0.0.1:5222."
	echo "Start the test server with Testing/xmpp/server.sh start"
	exit 0
fi

if [ ! -d "$HARNESS/Frameworks" ]; then
	mkdir -p "$HARNESS/bin" "$HARNESS/Frameworks"
	cp -R "$ROOT/Frameworks/"*.framework "$HARNESS/Frameworks/"
	cp "$ROOT/Frameworks/"*.dylib "$HARNESS/Frameworks/" 2>/dev/null || true
	for one in "$HARNESS/Frameworks/"*; do codesign -f -s - "$one" >/dev/null 2>&1 || true; done
fi
mkdir -p "$HARNESS/bin"

xcrun clang -o "$HARNESS/bin/mucselfping-wire" \
	mucselfping-wire.c "$RULES/AIMUCSelfPingRules.c" \
	-I "$RULES" \
	-I "$ROOT/Frameworks/libpurple.framework/Headers" \
	-I "$ROOT/Frameworks/libglib.framework/Headers" \
	-F"$ROOT/Frameworks" -framework libpurple -framework libglib

exec "$HARNESS/bin/mucselfping-wire"
