#!/bin/zsh
# Zwei Nachbarn auf einer Maschine: einer wartet, einer schickt einen Gruss.
#
# Beweist gegen das echte mDNSResponder dieses Rechners, dass prpl-bonjour sich anmeldet,
# den anderen findet und eine Nachricht zustellt, ohne dass die laufende Anwendung oder
# ein zweiter Rechner gebraucht wird. Baut wie smwire.sh gegen die ad hoc signierten
# Frameworks der Anwendung.
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

# libpurple jedes Mal auffrischen: gemessen wird, was eben gebaut wurde.
cp "$ROOT/Frameworks/libpurple.framework/Versions/0/libpurple" \
   "$HARNESS/Frameworks/libpurple.framework/Versions/0/libpurple"
codesign -f -s - "$HARNESS/Frameworks/libpurple.framework" >/dev/null 2>&1 || true

xcrun clang -o "$HARNESS/bin/bonjourwire" bonjourwire.c \
	-I "$ROOT/Frameworks/libpurple.framework/Headers" \
	-I "$ROOT/Frameworks/libglib.framework/Headers" \
	-F"$HARNESS/Frameworks" -framework libpurple -framework libglib

rm -rf "${TMPDIR:-/tmp}/adium-bonjourwire-erna" "${TMPDIR:-/tmp}/adium-bonjourwire-knut"

"$HARNESS/bin/bonjourwire" erna 5298 wait 25 &
WAITER=$!
sleep 2
"$HARNESS/bin/bonjourwire" knut 5299 send 25 &
SENDER=$!

STATUS=0
wait $SENDER || STATUS=1
wait $WAITER || STATUS=1

if [ $STATUS -eq 0 ]; then
	echo "== beide Haelften bestanden: gefunden, geschickt, angekommen"
else
	echo "== FEHLSCHLAG, siehe Ausgabe oben"
fi
exit $STATUS
