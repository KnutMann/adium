#!/bin/zsh
# Build and run the check that Adium reads a MUC self-ping answer (XEP-0410) and a MUC status
# code 333 (XEP-0045) the way the specifications say.
#
# Compiles the REAL rules file the application ships, Plugins/Purple Service/AIMUCSelfPingRules.c,
# so what passes here is what runs. Needs no server and no account: every rule is a function of
# one stanza. The frameworks in the tree are unsigned and arm64 will not load unsigned code, so
# copies are made beside the test binary and signed ad hoc.
set -e
cd "$(dirname "$0")"

ROOT="$(cd ../.. && pwd)"
RULES="$ROOT/Plugins/Purple Service"
HARNESS="${TMPDIR:-/tmp}/adium-omemo-harness"

if [ ! -f "$RULES/AIMUCSelfPingRules.c" ]; then
	echo "AIMUCSelfPingRules.c is missing from $RULES" >&2
	exit 1
fi

if [ ! -d "$HARNESS/Frameworks" ]; then
	mkdir -p "$HARNESS/bin" "$HARNESS/Frameworks"
	cp -R "$ROOT/Frameworks/"*.framework "$HARNESS/Frameworks/"
	cp "$ROOT/Frameworks/"*.dylib "$HARNESS/Frameworks/" 2>/dev/null || true
	for one in "$HARNESS/Frameworks/"*; do codesign -f -s - "$one" >/dev/null 2>&1 || true; done
fi
mkdir -p "$HARNESS/bin"

xcrun clang -o "$HARNESS/bin/mucselfping-test" \
	mucselfping-test.c "$RULES/AIMUCSelfPingRules.c" \
	-I "$RULES" \
	-I "$ROOT/Frameworks/libpurple.framework/Headers" \
	-I "$ROOT/Frameworks/libglib.framework/Headers" \
	-F"$ROOT/Frameworks" -framework libpurple -framework libglib

exec "$HARNESS/bin/mucselfping-test"
