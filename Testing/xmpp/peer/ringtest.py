#!/usr/bin/env python3
"""Rings the Adium under test with a real XEP-0353 propose and reports every
jingle-message that comes back, with timestamps. The person at the Adium
decides: declining should produce a reject, answering a proceed."""

import asyncio
import logging
import os
import time
import uuid

from slixmpp import ClientXMPP
from slixmpp.xmlstream import ET
from slixmpp.xmlstream.handler import Callback
from slixmpp.xmlstream.matcher import MatchXPath

SERVER = ("127.0.0.1", 5222)
TARGET = "adium@localhost"
NS = "urn:xmpp:jingle-message:0"
SASL_INSECURE = {'feature_mechanisms': {'unencrypted_plain': True,
                                        'unencrypted_scram': True}}

start = time.monotonic()


def stamp():
    return f"[{time.monotonic() - start:6.2f}s]"


class Probe(ClientXMPP):
    def __init__(self):
        super().__init__("peer@localhost/ringtest", "peer-pw", plugin_config=SASL_INSECURE)
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.sid = f"ringtest-{uuid.uuid4().hex[:8]}"
        self.finished = asyncio.get_event_loop().create_future()
        self.add_event_handler("session_start", self.on_start)
        self.register_handler_for_messages()

    def register_handler_for_messages(self):
        def on_message(message):
            for kind in ("ringing", "proceed", "reject", "retract", "accept"):
                child = message.xml.find(f"{{{NS}}}{kind}")
                if child is not None:
                    print(f"{stamp()} {kind} von {message['from']} (id={child.get('id')})")
                    if kind in ("reject", "proceed") and not self.finished.done():
                        self.finished.set_result(kind)
        # slixmpp's "message" event needs a body; call signalling has none
        self.register_handler(Callback("all-messages",
                                       MatchXPath("{jabber:client}message"),
                                       lambda stanza: on_message(stanza)))

    async def on_start(self, event):
        self.send_presence()
        message = self.Message()
        message["to"] = TARGET
        message["type"] = "chat"
        propose = ET.Element(f"{{{NS}}}propose", {"id": self.sid})
        ET.SubElement(propose, "{urn:xmpp:jingle:apps:rtp:1}description", {"media": "audio"})
        message.xml.append(propose)
        message.send()
        print(f"{stamp()} propose gesendet (sid={self.sid}) - Adium sollte jetzt klingeln")


def main():
    if os.environ.get("RAW"):
        logging.basicConfig(level=logging.DEBUG, format="%(message)s")
    probe = Probe()
    probe.connect(*SERVER)
    loop = asyncio.get_event_loop()
    try:
        outcome = loop.run_until_complete(asyncio.wait_for(probe.finished, 90))
        print(f"{stamp()} Ausgang: {outcome}")
    except asyncio.TimeoutError:
        print(f"{stamp()} Keine Antwort binnen 90s")
    probe.disconnect()


if __name__ == "__main__":
    main()
