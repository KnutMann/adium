#!/bin/sh
# Wer sagt bei einem Anruf was, auf dem Draht gelesen
#
# Adium zaehlt seine eigenen Anfragen und die Antworten, die ankommen, aber
# nicht, was dazwischen passiert. Ein Anruf, der zehn Sekunden braucht, hat drei
# moegliche Schuldige, und sie sehen von innen gleich aus: unsere Pakete gehen
# gar nicht erst raus, sie gehen raus und die Gegenseite schweigt, oder sie geht
# raus und die Gegenseite lehnt ab. Diese Aufzeichnung trennt die drei.
#
# Gelesen wird ausserdem, WAS in den Paketen steht, denn das beantwortet die
# naechste Frage gleich mit. Der USERNAME einer Pruefanfrage traegt die ICE-
# Kennungen beider Seiten, und ein Anruf, dessen Anfragen unbeantwortet bleiben,
# sieht von aussen genauso aus wie einer, dessen Anfragen die Gegenseite
# stillschweigend verwirft, weil die Kennung nicht stimmt. Die beiden Faelle
# stehen hier nebeneinander: passen die Kennungen spiegelbildlich zusammen, ist
# unsere Seite in Ordnung und das Schweigen gehoert der anderen.
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
# Ganze Pakete, denn abgeschnittene verlieren genau die Attribute, die zaehlen.
tcpdump -i "$INTERFACE" -n -s 0 -w "$CAPTURE" 'udp[12:4] = 0x2112a442' 2>/dev/null &
CAPTURER=$!
sleep "$SECONDS_TO_WATCH"
kill "$CAPTURER" 2>/dev/null
wait "$CAPTURER" 2>/dev/null
echo "Fertig. Das Gelesene steht in $CAPTURE"
echo

MINE="$MINE" python3 - "$CAPTURE" <<'AUSWERTUNG'
import binascii, collections, os, subprocess, sys

mine = os.environ["MINE"]
dump = subprocess.run(["tcpdump", "-r", sys.argv[1], "-n", "-tt", "-x"],
                      capture_output=True, text=True).stdout

packets, current = [], None
for line in dump.splitlines():
    if line and not line[0].isspace():
        field = line.split()
        current = {"at": float(field[0]), "from": field[2], "to": field[4].rstrip(":"), "hex": ""}
        packets.append(current)
    elif current is not None and ":" in line:
        current["hex"] += "".join(line.split(":", 1)[1].split())

if not packets:
    print("Nichts aufgezeichnet. Kein Anruf, oder die falsche Schnittstelle.")
    raise SystemExit(0)

start = packets[0]["at"]

ART = {0x0001: "fragt", 0x0101: "antwortet", 0x0111: "lehnt ab",
       0x0003: "will Relay", 0x0103: "Relay ja", 0x0113: "Relay nein",
       0x0008: "Erlaubnis", 0x0108: "Erlaubnis ja",
       0x0004: "verlaengert", 0x0104: "verlaengert ja",
       0x0016: "sendet ueber Relay", 0x0017: "empfaengt ueber Relay"}


def zerlegen(packet):
    """Art der Nachricht und die Attribute, die etwas verraten."""
    raw = binascii.unhexlify(packet["hex"])[28:]        # hinter IP und UDP
    if len(raw) < 20:
        return None, {}
    art = int.from_bytes(raw[0:2], "big")
    laenge = int.from_bytes(raw[2:4], "big")
    gefunden, stelle = {}, 20
    while stelle + 4 <= min(len(raw), 20 + laenge):
        typ = int.from_bytes(raw[stelle:stelle + 2], "big")
        gross = int.from_bytes(raw[stelle + 2:stelle + 4], "big")
        wert = raw[stelle + 4:stelle + 4 + gross]
        if typ == 0x0006:
            gefunden["USERNAME"] = wert.decode("utf-8", "replace")
        elif typ == 0x0025:
            gefunden["USE-CANDIDATE"] = True
        elif typ == 0x802a:
            gefunden["Rolle"] = "fuehrend"
        elif typ == 0x8029:
            gefunden["Rolle"] = "folgend"
        elif typ == 0x0009 and len(wert) >= 4:
            gefunden["Fehler"] = wert[2] * 100 + wert[3]
        stelle += 4 + gross + ((4 - gross % 4) % 4)
    return art, gefunden


for packet in packets:
    packet["art"], packet["dabei"] = zerlegen(packet)

# Wer mit wem, und wann zum ersten Mal
verkehr = collections.OrderedDict()
for packet in packets:
    schluessel = (packet["from"].rsplit(".", 1)[0], packet["to"].rsplit(".", 1)[0],
                  ART.get(packet["art"], hex(packet["art"] or 0)))
    eintrag = verkehr.setdefault(schluessel, [0, packet["at"] - start, packet["at"] - start])
    eintrag[0] += 1
    eintrag[2] = packet["at"] - start

print("Der Draht, nach Gegenstelle und Art")
print(f"  {'von':<16} {'nach':<16} {'was':<20} {'wie oft':>7} {'erst':>7} {'zuletzt':>8}")
for (woher, wohin, was), (wieoft, erst, zuletzt) in verkehr.items():
    print(f"  {woher:<16} {wohin:<16} {was:<20} {wieoft:>7} {erst:>6.2f}s {zuletzt:>7.2f}s")

# Die Kennungen, denn sie sagen, ob unsere Fragen ueberhaupt gemeint sein konnten
hin = {p["dabei"].get("USERNAME") for p in packets
       if p["art"] == 0x0001 and p["from"].startswith(mine + ".") and p["dabei"].get("USERNAME")}
her = {p["dabei"].get("USERNAME") for p in packets
       if p["art"] == 0x0001 and not p["from"].startswith(mine + ".") and p["dabei"].get("USERNAME")}

print()
print("Die ICE-Kennungen")
print(f"  wir fragen mit:      {', '.join(sorted(hin)) or 'nichts'}")
print(f"  die Gegenseite mit:  {', '.join(sorted(her)) or 'nichts'}")
spiegel = {tuple(reversed(name.split(':', 1))) for name in her if ':' in name}
if hin and her:
    passt = any(tuple(name.split(':', 1)) in spiegel for name in hin if ':' in name)
    print("  Die beiden sind Spiegelbilder, unsere Fragen waren also richtig adressiert."
          if passt else
          "  ACHTUNG: die beiden passen NICHT zusammen. Dann verwirft die Gegenseite "
          "unsere Fragen stillschweigend, und der Fehler ist unserer.")
elif hin:
    print("  Die Gegenseite hat nie gefragt, es gibt also nichts zu vergleichen.")

# Und das Urteil, Gegenstelle fuer Gegenstelle
print()
print("Was daraus folgt")
gegenstellen = sorted({p["to"].rsplit(".", 1)[0] for p in packets if p["from"].startswith(mine + ".")} |
                      {p["from"].rsplit(".", 1)[0] for p in packets if not p["from"].startswith(mine + ".")})
for wer in gegenstellen:
    gefragt = sum(1 for p in packets
                  if p["art"] == 0x0001 and p["from"].startswith(mine + ".") and p["to"].startswith(wer + "."))
    bejaht = sum(1 for p in packets if p["art"] == 0x0101 and p["from"].startswith(wer + "."))
    abgelehnt = sum(1 for p in packets if p["art"] == 0x0111 and p["from"].startswith(wer + "."))
    selbst = sum(1 for p in packets if p["art"] == 0x0001 and p["from"].startswith(wer + "."))
    if not (gefragt or selbst):
        continue

    if abgelehnt:
        urteil = "hoert uns und weist uns ab, das waere unser Fehler"
    elif gefragt and not bejaht and not selbst:
        urteil = "schweigt vollstaendig, dort kommt nichts an oder es darf nicht antworten"
    elif selbst and not bejaht:
        urteil = "fragt selbst, beantwortet aber unsere Fragen nicht"
    elif bejaht:
        erste = min(p["at"] - start for p in packets if p["art"] == 0x0101 and p["from"].startswith(wer + "."))
        urteil = f"antwortet, erstmals nach {erste:.2f}s"
    else:
        urteil = "unklar"
    print(f"  {wer:<16} {urteil}")
AUSWERTUNG
