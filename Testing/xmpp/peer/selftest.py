#!/usr/bin/env python3
"""Automated feature checks for the Adium XMPP test server.

Connects as the test accounts and verifies, without Adium involved, that the
server actually provides what the Adium XMPP roadmap develops against:
message delivery, carbons, the archive, client state indication and PEP
bookmarks. Prints one PASS/FAIL line per feature and exits non-zero if
anything failed.
"""

import asyncio
import sys
import uuid

from slixmpp import ClientXMPP

SERVER = ("127.0.0.1", 5222)
RESULTS = []
SASL_INSECURE = {'feature_mechanisms': {'unencrypted_plain': True,
                                        'unencrypted_scram': True}}



def report(name: str, ok: bool, detail: str = ""):
    RESULTS.append(ok)
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))


class TestClient(ClientXMPP):
    def __init__(self, account: str, resource: str):
        super().__init__(f"{account}@localhost/{resource}", f"{account}-pw", plugin_config=SASL_INSECURE)
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.register_plugin("xep_0030")  # disco
        self.register_plugin("xep_0280")  # carbons
        self.register_plugin("xep_0313")  # mam
        self.register_plugin("xep_0163")  # pep
        self.register_plugin("xep_0060")  # pubsub
        self.ready = asyncio.get_event_loop().create_future()
        self.inbox = asyncio.Queue()
        self.carbons = asyncio.Queue()
        self.add_event_handler("session_start", self.on_start)
        self.add_event_handler("message", self.on_message)
        self.add_event_handler("carbon_sent", self.on_carbon)

    async def on_start(self, event):
        self.send_presence()
        await self.get_roster()
        if not self.ready.done():
            self.ready.set_result(True)

    def on_message(self, msg):
        if msg["type"] in ("chat", "normal") and msg["body"]:
            self.inbox.put_nowait((str(msg["from"]), msg["body"]))

    def on_carbon(self, msg):
        fwd = msg["carbon_sent"]
        self.carbons.put_nowait((str(fwd["to"]), fwd["body"]))


async def expect(queue: asyncio.Queue, timeout: float = 5.0):
    return await asyncio.wait_for(queue.get(), timeout)


async def run_checks():
    adium = TestClient("adium", "desktop")
    phone = TestClient("adium", "phone")
    peer = TestClient("peer", "peer")

    for client in (adium, phone, peer):
        client.connect(*SERVER)

    try:
        await asyncio.wait_for(asyncio.gather(adium.ready, phone.ready, peer.ready), 10)
        report("Anmeldung aller drei Testsitzungen", True)
    except asyncio.TimeoutError:
        report("Anmeldung aller drei Testsitzungen", False, "Timeout beim Verbinden")
        return

    # 1. Plain roundtrip: peer -> adium
    marker = f"roundtrip-{uuid.uuid4().hex[:8]}"
    peer.send_message(mto="adium@localhost", mbody=marker, mtype="chat")
    try:
        sender, body = await expect(adium.inbox)
        report("Nachrichtenzustellung peer → adium", body == marker, body)
    except asyncio.TimeoutError:
        report("Nachrichtenzustellung peer → adium", False, "nichts angekommen")

    # 2. Carbons: desktop enables them; phone sends; desktop must see the copy
    try:
        await adium["xep_0280"].enable()
        marker = f"carbon-{uuid.uuid4().hex[:8]}"
        phone.send_message(mto="peer@localhost", mbody=marker, mtype="chat")
        to, body = await expect(adium.carbons)
        report("Carbons (XEP-0280): Kopie der Zweitgerät-Nachricht", body == marker, body)
    except asyncio.TimeoutError:
        report("Carbons (XEP-0280): Kopie der Zweitgerät-Nachricht", False, "keine Kopie angekommen")
    except Exception as e:
        report("Carbons (XEP-0280): Kopie der Zweitgerät-Nachricht", False, str(e))

    # 3. MAM: the carbon marker must be in the archive
    try:
        await asyncio.sleep(0.5)
        found = False
        async for rsm in adium["xep_0313"].retrieve(with_jid="peer@localhost", iterator=True):
            for msg in rsm["mam"]["results"]:
                if marker in (msg["mam_result"]["forwarded"]["stanza"]["body"] or ""):
                    found = True
        report("Archiv (XEP-0313 MAM): Nachricht wiedergefunden", found)
    except Exception as e:
        report("Archiv (XEP-0313 MAM): Nachricht wiedergefunden", False, str(e))

    # 4. CSI: send inactive/active nonzas; the stream has to survive a ping after
    try:
        for state in ("inactive", "active"):
            adium.send_raw(f"<{state} xmlns='urn:xmpp:csi:0'/>")
        await adium["xep_0030"].get_info(jid="localhost")
        report("CSI (XEP-0352): Zustandswechsel ohne Streamabbruch", True)
    except Exception as e:
        report("CSI (XEP-0352): Zustandswechsel ohne Streamabbruch", False, str(e))

    # 5. PEP native bookmarks (XEP-0402 storage node): publish and read back
    try:
        node = "urn:xmpp:bookmarks:1"
        room = f"test-{uuid.uuid4().hex[:6]}@conference.localhost"
        payload = (f"<conference xmlns='{node}' name='Selftest-Raum' autojoin='false'>"
                   f"<nick>adium</nick></conference>")
        from slixmpp.xmlstream import ET
        await adium["xep_0060"].publish("adium@localhost", node,
                                        id=room, payload=ET.fromstring(payload))
        items = await adium["xep_0060"].get_items("adium@localhost", node)
        ids = [item["id"] for item in items["pubsub"]["items"]]
        report("Bookmarks (XEP-0402): PEP-Knoten beschreib- und lesbar", room in ids)
    except Exception as e:
        report("Bookmarks (XEP-0402): PEP-Knoten beschreib- und lesbar", False, str(e))

    for client in (adium, phone, peer):
        client.disconnect()
    await asyncio.sleep(0.3)


def main():
    asyncio.get_event_loop().run_until_complete(run_checks())
    print(f"\n{RESULTS.count(True)}/{len(RESULTS)} Prüfungen bestanden")
    sys.exit(0 if all(RESULTS) else 1)


if __name__ == "__main__":
    main()
