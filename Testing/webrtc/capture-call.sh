#!/bin/sh
# Wer sagt bei einem Anruf was, auf dem Draht gelesen
#
# Adium zaehlt seine eigenen Anfragen und die Antworten, die ankommen, aber
# nicht, was dazwischen passiert. Ein Anruf, der zehn Sekunden braucht, hat drei
# moegliche Schuldige, und sie sehen von innen gleich aus: unsere Pakete gehen
# gar nicht erst raus, sie gehen raus und die Gegenseite schweigt, oder sie geht
# raus und die Gegenseite lehnt ab. Diese Aufzeichnung trennt die drei.
#
# Aufruf waehrend eines Anrufs, mit Rechten zum Mitlesen:
#   sudo Testing/webrtc/capture-call.sh [Sekunden] [Schnittstelle]

SECONDS_TO_WATCH=${1:-45}
INTERFACE=${2:-$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')}
CAPTURE=${TMPDIR:-/tmp}/adium-call-stun.pcap

if [ "$(id -u)" != "0" ]; then
	echo "Mitlesen geht nur mit Rechten dafuer:"
	echo "  sudo $0 $*"
	exit 1
fi

MINE=$(ipconfig getifaddr "$INTERFACE")
echo "Schnittstelle $INTERFACE, eigene Adresse $MINE"
echo "Zeichne $SECONDS_TO_WATCH Sekunden auf. Ruf jetzt an oder nimm an."
echo

# Alles mit dem STUN-Erkennungswort, also Pruefungen und Relay-Verkehr zugleich.
# Es steht ab dem vierten Byte der Nutzlast, die Art der Nachricht im ersten.
tcpdump -i "$INTERFACE" -n -s 128 -w "$CAPTURE" 'udp[12:4] = 0x2112a442' 2>/dev/null &
CAPTURER=$!
sleep "$SECONDS_TO_WATCH"
kill "$CAPTURER" 2>/dev/null
wait "$CAPTURER" 2>/dev/null
echo "Fertig. Das Gelesene steht in $CAPTURE"
echo

count() { tcpdump -r "$CAPTURE" -n "$1" 2>/dev/null | wc -l | tr -d ' '; }
first() { tcpdump -r "$CAPTURE" -n -tt "$1" 2>/dev/null | head -1 | awk '{print $1}'; }
last()  { tcpdump -r "$CAPTURE" -n -tt "$1" 2>/dev/null | tail -1 | awk '{print $1}'; }

# Mit wem wurde ueberhaupt gesprochen
PEERS=$(tcpdump -r "$CAPTURE" -n 2>/dev/null | awk '{print $3, $5}' |
        tr -d ':' | tr ' ' '\n' | sed 's/\.[0-9]*$//' | grep -v "^$MINE$" | sort -u)

printf "%-18s %8s %8s %8s %8s\n" "Gegenstelle" "gefragt" "bejaht" "abgelehnt" "gefragt?"
printf "%-18s %8s %8s %8s %8s\n" "" "von uns" "" "" "von ihr"
echo "---------------------------------------------------------------"

for PEER in $PEERS; do
	OUT=$(count "src host $MINE and dst host $PEER and udp[8:2] = 0x0001")
	OK=$(count "src host $PEER and udp[8:2] = 0x0101")
	BAD=$(count "src host $PEER and udp[8:2] = 0x0111")
	IN=$(count "src host $PEER and udp[8:2] = 0x0001")
	printf "%-18s %8s %8s %8s %8s\n" "$PEER" "$OUT" "$OK" "$BAD" "$IN"

	if [ "$OUT" != "0" ]; then
		echo "    unsere erste Frage:  $(first "src host $MINE and dst host $PEER and udp[8:2] = 0x0001")"
	fi
	if [ "$OK" != "0" ]; then
		echo "    ihre erste Antwort:  $(first "src host $PEER and udp[8:2] = 0x0101")"
	fi
	if [ "$IN" != "0" ]; then
		echo "    ihre erste Frage:    $(first "src host $PEER and udp[8:2] = 0x0001")"
	fi
	if [ "$BAD" != "0" ]; then
		echo "    ABGELEHNT: sie hoert uns, weist uns aber ab. Das waere unser Fehler."
	fi
done

echo
echo "Zu lesen so: keine Zeile heisst, dass nichts den Mac verlassen hat."
echo "Fragen ohne Antworten heisst, dass die Gegenseite schweigt."
echo "Abgelehnte heissen, dass sie zuhoert und uns nicht glaubt."
