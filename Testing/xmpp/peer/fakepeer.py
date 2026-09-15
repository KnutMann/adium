#!/usr/bin/env python3
"""A stand-in for Conversations: speaks the call signalling, judges what Adium says.

Sits online as peer@localhost, announces the same call capabilities a modern
client announces, and plays both halves of the ringing dance (XEP-0353) plus the
session that follows (XEP-0166/0167/0176/0320). It carries no media: everything
up to the session-accept is signalling, and signalling is where the real-world
failures showed. Every stanza that matters is printed, and what Adium sends is
checked for the parts a peer needs to place a call.

  ./run.sh fakepeer            listen: ring back whatever Adium offers
  ./run.sh fakepeer --call     ring Adium first, then listen
"""

import asyncio
import os
import sys
import time
import uuid

from slixmpp import ClientXMPP
from slixmpp.xmlstream import ET
from slixmpp.xmlstream.handler import Callback
from slixmpp.xmlstream.matcher import MatchXPath

SERVER = ("127.0.0.1", 5222)
TARGET = "adium@localhost"
JMI = "urn:xmpp:jingle-message:0"
JINGLE = "urn:xmpp:jingle:1"
RTP = "urn:xmpp:jingle:apps:rtp:1"
ICE = "urn:xmpp:jingle:transports:ice-udp:1"
DTLS = "urn:xmpp:jingle:apps:dtls:0"
SASL_INSECURE = {'feature_mechanisms': {'unencrypted_plain': True,
                                        'unencrypted_scram': True}}

start = time.monotonic()
findings = []


def stamp():
    return f"[{time.monotonic() - start:6.2f}s]"


def note(ok, text, detail=""):
    findings.append(ok)
    print(f"{stamp()} {'PASS' if ok else 'FAIL'}  {text}{('  ' + detail) if detail else ''}")


class FakePeer(ClientXMPP):
    def __init__(self, call_first):
        super().__init__("peer@localhost/fakepeer", "peer-pw", plugin_config=SASL_INSECURE)
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.call_first = call_first
        self.our_sid = f"fake-{uuid.uuid4().hex[:8]}"
        self.add_event_handler("session_start", self.on_start)
        self.register_handler_raw()

    def register_handler_raw(self):
        """Match the stanzas themselves.

        TRAP, cost an afternoon: slixmpp's "message" event fires only for
        messages carrying a body. Call signalling carries none, so every
        answer looked like silence. Matching the element itself sees them.
        """
        self.register_handler(Callback(
            "all-messages", MatchXPath("{jabber:client}message"),
            lambda stanza: self.on_message_stanza(stanza.xml)))
        self.register_handler(Callback(
            "jingle-iqs", MatchXPath("{jabber:client}iq/{%s}jingle" % JINGLE),
            lambda stanza: self.on_iq_stanza(stanza.xml)))

    async def on_start(self, event):
        # The capabilities a caller looks for before offering its call button
        presence = self.Presence()
        caps = ET.SubElement(presence.xml, "{http://jabber.org/protocol/caps}c")
        caps.set("hash", "sha-1")
        caps.set("node", "https://conversations.im")
        caps.set("ver", "fakepeer")
        presence.send()
        print(f"{stamp()} online als peer@localhost/fakepeer")

        if self.call_first:
            await asyncio.sleep(1)
            self.send_jmi("propose", self.our_sid, TARGET, audio=True)
            print(f"{stamp()} propose an Adium gesendet (sid={self.our_sid}) "
                  f"-> bitte in Adium ANNEHMEN")

    # Sending ------------------------------------------------------------------
    def send_jmi(self, kind, sid, to, audio=False, video=False):
        message = self.Message()
        message["to"] = to
        message["type"] = "chat"
        child = ET.SubElement(message.xml, f"{{{JMI}}}{kind}", {"id": sid})
        if kind == "propose":
            if audio:
                ET.SubElement(child, f"{{{RTP}}}description", {"media": "audio"})
            if video:
                ET.SubElement(child, f"{{{RTP}}}description", {"media": "video"})
        ET.SubElement(message.xml, "{urn:xmpp:hints}store")
        message.send()
        print(f"{stamp()} -> {kind} (sid={sid}) an {to}")

    def send_initiate(self, to, sid):
        """Offer a real session, built from an SDP a real WebRTC produced."""
        path = os.path.join(os.path.dirname(__file__), "fixtures", "session-initiate.xml")
        xml = open(path).read().replace("SIDPLACEHOLDER", sid)
        iq = self.make_iq_set(ito=to)
        iq.xml.append(ET.fromstring(xml))
        iq.send(timeout=10)
        print(f"{stamp()} -> session-initiate (sid={sid})")

    def send_terminate(self, to, sid, reason="success"):
        iq = self.make_iq_set(ito=to)
        jingle = ET.SubElement(iq.xml, f"{{{JINGLE}}}jingle",
                               {"action": "session-terminate", "sid": sid})
        ET.SubElement(ET.SubElement(jingle, "reason"), reason)
        iq.send(timeout=5)
        print(f"{stamp()} -> session-terminate ({reason})")

    # Receiving ----------------------------------------------------------------
    def on_message_stanza(self, xml):
        sender = xml.get("from") or ""
        for kind in ("propose", "ringing", "proceed", "reject", "retract", "accept"):
            child = xml.find(f"{{{JMI}}}{kind}")
            if child is None:
                continue
            sid = child.get("id")
            print(f"{stamp()} <- {kind} (sid={sid}) von {sender}")

            if kind == "propose":
                media = [d.get("media") for d in child.findall(f"{{{RTP}}}description")]
                note(bool(media), "Adiums propose nennt seine Medien", f"{media}")
                note(sid is not None, "propose hat eine id")
                # Ring, then take the call the way a person would
                self.send_jmi("ringing", sid, sender)
                asyncio.get_event_loop().call_later(
                    1.5, lambda: self.send_jmi("proceed", sid, sender))
            elif kind == "ringing":
                note(True, "Adium meldet zurueck, dass es klingelt")
            elif kind == "proceed":
                note(True, "Adium nimmt an (proceed)")
                # As the caller, the session is ours to offer now
                self.send_initiate(sender, sid)

    def on_iq_stanza(self, xml):
        jingle = xml.find(f"{{{JINGLE}}}jingle")
        if jingle is None:
            return

        action = jingle.get("action")
        sender = xml.get("from") or ""
        sid = jingle.get("sid")
        print(f"{stamp()} <- jingle {action} (sid={sid}) von {sender}")

        # Every jingle iq is acknowledged, as the specification orders
        if xml.get("type") == "set" and xml.get("id"):
            ack = self.make_iq_result(id=xml.get("id"), ito=sender)
            ack.send()

        if action == "session-accept":
            note(True, "Adium beantwortet die Sitzung (session-accept)")
            self.judge_initiate(jingle)   # an accept must carry the same parts
            asyncio.get_event_loop().call_later(
                2.0, lambda: self.send_terminate(sender, sid, "success"))
        elif action == "session-initiate":
            self.judge_initiate(jingle)
            asyncio.get_event_loop().call_later(
                2.0, lambda: self.send_terminate(sender, sid, "success"))
        elif action == "transport-info":
            candidates = jingle.findall(f".//{{{ICE}}}candidate")
            if candidates:
                print(f"{stamp()}    (trickle: {len(candidates)} Kandidat(en))")

    def judge_initiate(self, jingle):
        """What a peer must find in an initiate to be able to answer it."""
        contents = jingle.findall(f"{{{JINGLE}}}content")
        note(bool(contents), "initiate traegt Inhalte", f"{len(contents)}")

        for content in contents:
            name = content.get("name")
            description = content.find(f"{{{RTP}}}description")
            transport = content.find(f"{{{ICE}}}transport")

            note(description is not None, f"Inhalt '{name}': RTP-Beschreibung da")
            if description is not None:
                payloads = description.findall(f"{{{RTP}}}payload-type")
                names = [p.get("name") for p in payloads[:3]]
                note(bool(payloads), f"Inhalt '{name}': Payload-Typen da",
                     f"{description.get('media')}: {names}")

            note(transport is not None, f"Inhalt '{name}': ICE-Transport da")
            if transport is not None:
                note(bool(transport.get("ufrag")) and bool(transport.get("pwd")),
                     f"Inhalt '{name}': ICE-Zugangsdaten da")
                fingerprint = transport.find(f"{{{DTLS}}}fingerprint")
                note(fingerprint is not None and bool((fingerprint.text or "").strip()),
                     f"Inhalt '{name}': DTLS-Fingerabdruck da",
                     (fingerprint.get("setup") if fingerprint is not None else ""))


def main():
    call_first = "--call" in sys.argv
    seconds = 60
    for index, argument in enumerate(sys.argv):
        if argument == "--seconds" and index + 1 < len(sys.argv):
            seconds = int(sys.argv[index + 1])

    peer = FakePeer(call_first)
    peer.connect(*SERVER)
    loop = asyncio.get_event_loop()
    try:
        loop.run_until_complete(asyncio.sleep(seconds))
    except KeyboardInterrupt:
        pass
    peer.disconnect()

    print()
    if findings:
        print(f"{sum(1 for f in findings if f)}/{len(findings)} Pruefungen bestanden")
    else:
        print("Nichts beobachtet: kam ein Anruf an?")
    sys.exit(0 if findings and all(findings) else 1)


if __name__ == "__main__":
    main()
