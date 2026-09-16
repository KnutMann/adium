#!/usr/bin/env python3
"""Checks a contact's call capabilities exactly the way Conversations does.

Subscribes to adium@localhost, waits for presence, reads the XEP-0115 caps
ver from it, asks disco#info on the full JID, verifies the advertised hash
against the answer, and says which of the Jingle call namespaces are there.
Run while the Adium under test has the adium@localhost account connected.
"""

import asyncio
import base64
import hashlib
import sys

from slixmpp import ClientXMPP
from slixmpp.xmlstream import ET

SERVER = ("127.0.0.1", 5222)
TARGET = "adium@localhost"
SASL_INSECURE = {'feature_mechanisms': {'unencrypted_plain': True,
                                        'unencrypted_scram': True}}

CALL_FEATURES = [
    "urn:xmpp:jingle:1",
    "urn:xmpp:jingle-message:0",
    "urn:xmpp:jingle:apps:rtp:1",
    "urn:xmpp:jingle:apps:rtp:audio",
    "urn:xmpp:jingle:apps:rtp:video",
    "urn:xmpp:jingle:transports:ice-udp:1",
    "urn:xmpp:jingle:apps:dtls:0",
]


def caps_ver(identities, features, forms):
    """XEP-0115 verification string, sha-1."""
    s = ""
    for category, typ, lang, name in sorted(identities):
        s += f"{category}/{typ}/{lang}/{name}<"
    for feature in sorted(features):
        s += feature + "<"
    for form in sorted(forms, key=lambda f: f.get("FORM_TYPE", [""])[0]):
        s += form.get("FORM_TYPE", [""])[0] + "<"
        for var in sorted(k for k in form if k != "FORM_TYPE"):
            s += var + "<"
            for value in sorted(form[var]):
                s += value + "<"
    return base64.b64encode(hashlib.sha1(s.encode()).digest()).decode()


class Probe(ClientXMPP):
    def __init__(self):
        super().__init__("peer@localhost/capscheck", "peer-pw", plugin_config=SASL_INSECURE)
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.presence_seen = asyncio.get_event_loop().create_future()
        self.add_event_handler("session_start", self.on_start)
        self.add_event_handler("presence_available", self.on_presence)

    async def on_start(self, event):
        self.send_presence()
        self.send_presence(pto=TARGET, ptype="subscribe")
        print(f"Warte auf Praesenz von {TARGET} (Abo-Anfrage gesendet; in Adium ggf. erlauben) ...")

    def on_presence(self, presence):
        if presence["from"].bare != TARGET or self.presence_seen.done():
            return
        caps = presence.xml.find("{http://jabber.org/protocol/caps}c")
        self.presence_seen.set_result((str(presence["from"]), caps))

    async def check(self):
        full_jid, caps = await asyncio.wait_for(self.presence_seen, 120)
        node = caps.get("node") if caps is not None else None
        ver = caps.get("ver") if caps is not None else None
        print(f"Praesenz von {full_jid}")
        print(f"Caps: node={node} ver={ver} hash={caps.get('hash') if caps is not None else None}")

        iq = self.make_iq_get(ito=full_jid)
        query = ET.Element("{http://jabber.org/protocol/disco#info}query")
        if node and ver:
            query.set("node", f"{node}#{ver}")
        iq.xml.append(query)
        answer = await iq.send()

        result = answer.xml.find("{http://jabber.org/protocol/disco#info}query")
        identities, features, forms = [], [], []
        for child in (result if result is not None else []):
            if child.tag.endswith("identity"):
                identities.append((child.get("category") or "", child.get("type") or "",
                                   child.get("lang") or child.get("{http://www.w3.org/XML/1998/namespace}lang") or "",
                                   child.get("name") or ""))
            elif child.tag.endswith("feature"):
                features.append(child.get("var"))
            elif child.tag.endswith("x"):
                form = {}
                for field in child:
                    var = field.get("var")
                    values = [v.text or "" for v in field if v.tag.endswith("value")]
                    if var:
                        form[var] = values
                forms.append(form)

        print(f"\ndisco#info: {len(identities)} Identitaeten, {len(features)} Features")
        ok = True
        for feature in CALL_FEATURES:
            there = feature in features
            ok &= there
            print(f"  {'PASS' if there else 'FAIL'}  {feature}")

        if ver:
            computed = caps_ver(identities, features, forms)
            match = (computed == ver)
            ok &= match
            print(f"\n{'PASS' if match else 'FAIL'}  XEP-0115-Hash stimmt "
                  f"(annonciert {ver}, berechnet {computed})")
            if not match:
                print("      -> Conversations verwirft die Caps bei Hash-Abweichung komplett!")
        else:
            print("\nFAIL  Praesenz traegt gar keine Caps")
            ok = False

        print(f"\n{'ALLES GUT: Conversations sieht die Anruf-Faehigkeiten' if ok else 'PROBLEM GEFUNDEN'}")
        return ok


def main():
    probe = Probe()
    probe.connect(*SERVER)
    loop = asyncio.get_event_loop()
    ok = loop.run_until_complete(probe.check())
    probe.disconnect()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
