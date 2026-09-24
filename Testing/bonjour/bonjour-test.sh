#!/bin/zsh
# Zwei Nachbarn auf einer Maschine: einer wartet, einer schickt einen Gruss.
#
# Beweist gegen das echte mDNSResponder dieses Rechners, dass prpl-bonjour sich anmeldet,
# den anderen findet und eine Nachricht zustellt, ohne dass die laufende Anwendung oder
# ein zweiter Rechner gebraucht wird. Baut wie smwire.sh gegen die ad hoc signierten
# Frameworks der Anwendung.
#
# Die Namen und Ports sind mit Bedacht welche, die sonst niemand hat. Auf dieser Maschine
# laeuft im Normalfall auch das richtige Adium mit einem Bonjour-Konto: das haelt Port 5298
# besetzt, und wenn ein Nachbar hier so heisst wie das Konto dort, tauft mDNS ihn auf
# "name (2)" um, waehrend sein XMPP-Stream weiter den alten Namen nennt. Der Empfaenger
# findet dann keinen Nachbarn dieses Namens und legt auf. Genau so sah der Fehlschlag vom
# 24.09.2026 aus.
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
	echo "== beide Haelften bestanden: gefunden, geschickt, angekommen"
else
	echo "== FEHLSCHLAG, siehe Ausgabe oben"
	echo "   Haeufigste Ursache: ein weiterer Bonjour-Teilnehmer auf dieser Maschine."
	echo "   Steht oben ein Nachbar mit \"(2)\" im Namen, hat mDNS wegen einer Namensgleichheit"
	echo "   umgetauft, und der Empfaenger kann den Absender nicht mehr zuordnen."
fi
exit $STATUS
