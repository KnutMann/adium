#!/bin/zsh
# Two neighbours on one machine: one waits, one sends a greeting.
#
# Proves against this machine's own mDNSResponder that prpl-bonjour signs on, finds the
# other and delivers a message, without needing the running application or a second
# machine. Builds against the application's ad hoc signed frameworks, as smwire.sh does.
#
# The names and ports are deliberately ones nobody else has. The real Adium normally runs
# on this machine with a Bonjour account of its own: that holds port 5298, and if a
# neighbour here carries the same name as the account there, mDNS renames it to
# "name (2)" while its XMPP stream goes on giving the old name. The receiver then finds
# no neighbour of that name and hangs up. That is exactly what the failure of
# 2026-09-24 looked like.
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

# Refresh libpurple every time: what is measured is what was just built.
cp "$ROOT/Frameworks/libpurple.framework/Versions/0/libpurple" \
   "$HARNESS/Frameworks/libpurple.framework/Versions/0/libpurple"
codesign -f -s - "$HARNESS/Frameworks/libpurple.framework" >/dev/null 2>&1 || true

xcrun clang -o "$HARNESS/bin/bonjourwire" bonjourwire.c \
	-I "$ROOT/Frameworks/libpurple.framework/Headers" \
	-I "$ROOT/Frameworks/libglib.framework/Headers" \
	-F"$HARNESS/Frameworks" -framework libpurple -framework libglib

WAITER_NAME=adiumprobe-a
SENDER_NAME=adiumprobe-b

rm -rf "${TMPDIR:-/tmp}/adium-bonjourwire-$WAITER_NAME" "${TMPDIR:-/tmp}/adium-bonjourwire-$SENDER_NAME"

"$HARNESS/bin/bonjourwire" "$WAITER_NAME" 15298 wait 25 "$SENDER_NAME" &
WAITER=$!
sleep 2
"$HARNESS/bin/bonjourwire" "$SENDER_NAME" 15299 send 25 "$WAITER_NAME" &
SENDER=$!

STATUS=0
wait $SENDER || STATUS=1
wait $WAITER || STATUS=1

if [ $STATUS -eq 0 ]; then
	echo "== both halves passed: found, sent, arrived"
else
	echo "== FAILED, see the output above"
	echo "   Most common cause: another Bonjour participant on this machine."
	echo "   If a neighbour above carries \"(2)\" in its name, mDNS renamed it because two"
	echo "   carried the same one, and the receiver can no longer place the sender."
fi
exit $STATUS
