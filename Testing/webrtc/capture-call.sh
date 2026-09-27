#!/bin/sh
# Who says what during a call, read off the wire
#
# Adium counts its own requests and the answers that arrive, but not what
# happens in between. A call that takes ten seconds has three possible culprits,
# and from the inside they look the same: our packets never leave at all, they
# leave and the other side stays silent, or they leave and the other side turns
# us down. This recording tells the three apart.
#
# It also reads WHAT is in the packets, because that answers the next question
# straight away. The USERNAME of a check request carries the ICE identifiers of
# both sides, and a call whose requests go unanswered looks from the outside
# exactly like one whose requests the other side silently drops because the
# identifier does not match. The two cases stand side by side here: if the
# identifiers mirror each other, our side is in order and the silence belongs to
# the other one.
#
# Run it during a call, with the rights to listen in:
#   sudo Testing/webrtc/capture-call.sh [seconds] [interface]

SECONDS_TO_WATCH=${1:-45}
INTERFACE=${2:-$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')}
CAPTURE=${TMPDIR:-/tmp}/adium-call-stun.pcap

if [ "$(id -u)" != "0" ]; then
	echo "Listening in only works with the rights for it:"
	echo "  sudo $0 $*"
	exit 1
fi

MINE=$(ipconfig getifaddr "$INTERFACE")
echo "Interface $INTERFACE, own address $MINE"
echo "Recording for $SECONDS_TO_WATCH seconds. Place or accept the call now."
echo

# Everything carrying the STUN magic cookie, so checks and relayed traffic
# alike. It sits at the fourth byte of the payload, the kind of message at the
# first. Whole packets, because truncated ones lose exactly the attributes that
# matter.
tcpdump -i "$INTERFACE" -n -s 0 -w "$CAPTURE" 'udp[12:4] = 0x2112a442' 2>/dev/null &
CAPTURER=$!
sleep "$SECONDS_TO_WATCH"
kill "$CAPTURER" 2>/dev/null
wait "$CAPTURER" 2>/dev/null
echo "Done. What was read is in $CAPTURE"
echo

MINE="$MINE" python3 - "$CAPTURE" <<'ANALYSIS'
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
    print("Nothing recorded. No call, or the wrong interface.")
    raise SystemExit(0)

start = packets[0]["at"]

KIND = {0x0001: "asks", 0x0101: "answers", 0x0111: "turns us down",
        0x0003: "wants a relay", 0x0103: "relay yes", 0x0113: "relay no",
        0x0008: "permission", 0x0108: "permission yes",
        0x0004: "renews", 0x0104: "renewal yes",
        0x0016: "sends over relay", 0x0017: "receives over relay"}


def dissect(packet):
    """The kind of message, and the attributes that give something away."""
    raw = binascii.unhexlify(packet["hex"])[28:]        # past IP and UDP
    if len(raw) < 20:
        return None, {}
    kind = int.from_bytes(raw[0:2], "big")
    length = int.from_bytes(raw[2:4], "big")
    found, at = {}, 20
    while at + 4 <= min(len(raw), 20 + length):
        kind_of_attribute = int.from_bytes(raw[at:at + 2], "big")
        size = int.from_bytes(raw[at + 2:at + 4], "big")
        value = raw[at + 4:at + 4 + size]
        if kind_of_attribute == 0x0006:
            found["USERNAME"] = value.decode("utf-8", "replace")
        elif kind_of_attribute == 0x0025:
            found["USE-CANDIDATE"] = True
        elif kind_of_attribute == 0x802a:
            found["Role"] = "controlling"
        elif kind_of_attribute == 0x8029:
            found["Role"] = "controlled"
        elif kind_of_attribute == 0x0009 and len(value) >= 4:
            found["Error"] = value[2] * 100 + value[3]
        at += 4 + size + ((4 - size % 4) % 4)
    return kind, found


for packet in packets:
    packet["kind"], packet["carries"] = dissect(packet)

# Who talks to whom, and when for the first time
traffic = collections.OrderedDict()
for packet in packets:
    key = (packet["from"].rsplit(".", 1)[0], packet["to"].rsplit(".", 1)[0],
           KIND.get(packet["kind"], hex(packet["kind"] or 0)))
    entry = traffic.setdefault(key, [0, packet["at"] - start, packet["at"] - start])
    entry[0] += 1
    entry[2] = packet["at"] - start

print("The wire, by peer and kind")
print(f"  {'from':<16} {'to':<16} {'what':<20} {'how often':>9} {'first':>7} {'last':>8}")
for (sender, receiver, what), (how_often, first, last) in traffic.items():
    print(f"  {sender:<16} {receiver:<16} {what:<20} {how_often:>9} {first:>6.2f}s {last:>7.2f}s")

# The identifiers, because they say whether our questions could have been meant at all
ours = {p["carries"].get("USERNAME") for p in packets
        if p["kind"] == 0x0001 and p["from"].startswith(mine + ".") and p["carries"].get("USERNAME")}
theirs = {p["carries"].get("USERNAME") for p in packets
          if p["kind"] == 0x0001 and not p["from"].startswith(mine + ".") and p["carries"].get("USERNAME")}

print()
print("The ICE identifiers")
print(f"  we ask with:         {', '.join(sorted(ours)) or 'nothing'}")
print(f"  the other side with: {', '.join(sorted(theirs)) or 'nothing'}")
mirror = {tuple(reversed(name.split(':', 1))) for name in theirs if ':' in name}
if ours and theirs:
    matches = any(tuple(name.split(':', 1)) in mirror for name in ours if ':' in name)
    print("  The two are mirror images, so our questions were addressed correctly."
          if matches else
          "  CAUTION: the two do NOT match. Then the other side silently drops our "
          "questions, and the fault is ours.")
elif ours:
    print("  The other side never asked, so there is nothing to compare.")

# And the verdict, peer by peer
print()
print("What follows from this")
peers = sorted({p["to"].rsplit(".", 1)[0] for p in packets if p["from"].startswith(mine + ".")} |
               {p["from"].rsplit(".", 1)[0] for p in packets if not p["from"].startswith(mine + ".")})
for peer in peers:
    asked = sum(1 for p in packets
                if p["kind"] == 0x0001 and p["from"].startswith(mine + ".") and p["to"].startswith(peer + "."))
    affirmed = sum(1 for p in packets if p["kind"] == 0x0101 and p["from"].startswith(peer + "."))
    refused = sum(1 for p in packets if p["kind"] == 0x0111 and p["from"].startswith(peer + "."))
    asked_us = sum(1 for p in packets if p["kind"] == 0x0001 and p["from"].startswith(peer + "."))
    if not (asked or asked_us):
        continue

    if refused:
        verdict = "hears us and turns us away, that would be our fault"
    elif asked and not affirmed and not asked_us:
        verdict = "is completely silent, nothing arrives there or it may not answer"
    elif asked_us and not affirmed:
        verdict = "asks itself, but does not answer our questions"
    elif affirmed:
        earliest = min(p["at"] - start for p in packets if p["kind"] == 0x0101 and p["from"].startswith(peer + "."))
        verdict = f"answers, first after {earliest:.2f}s"
    else:
        verdict = "unclear"
    print(f"  {peer:<16} {verdict}")
ANALYSIS
