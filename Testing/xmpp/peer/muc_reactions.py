#!/usr/bin/env python3
"""MUC reaction checks (XEP-0444 with XEP-0359) for the Adium test server.

Two sessions join a room; one sends a message, the other reacts to it. This
checks, without Adium involved, the exact wire behaviour Adium's group-chat
reactions rely on:

  - the room stamps a stanza-id (XEP-0359) on each message, and that id - not the
    sender's own message id, which is meaningless to anyone else - is what a
    reaction in the room points at;
  - a reaction sent as type='groupchat' to the room, naming that stanza-id, is
    reflected to the other occupants carrying the same id and the emoji, from
    room@service/nick so the reactor can be told apart;
  - an empty set clears it (a reaction taken back).

Mirrors the Adium side: message.c prefers the stanza-id stamped by the room,
reactions.c sends type='groupchat', and adiumJabberReactionReceived matches the
room by bare jid and buckets by occupant nick. Prints one PASS/FAIL line per
check and exits non-zero if anything failed.
"""

import asyncio
import sys
import uuid

from slixmpp import ClientXMPP, JID
from slixmpp.xmlstream import ET

SERVER = ("127.0.0.1", 5222)
NS_REACTIONS = "urn:xmpp:reactions:0"
NS_SID = "urn:xmpp:sid:0"
NS_FALLBACK = "urn:xmpp:fallback:0"
THUMB = "\U0001F44D"
RESULTS = []
SASL_INSECURE = {'feature_mechanisms': {'unencrypted_plain': True,
                                        'unencrypted_scram': True}}


def report(name: str, ok: bool, detail: str = ""):
    RESULTS.append(ok)
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))


class MucClient(ClientXMPP):
    def __init__(self, account: str, resource: str):
        super().__init__(f"{account}@localhost/{resource}", f"{account}-pw", plugin_config=SASL_INSECURE)
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.register_plugin("xep_0030")  # disco
        self.register_plugin("xep_0004")  # data forms (room config)
        self.register_plugin("xep_0045")  # MUC
        self.register_plugin("xep_0359")  # stanza-id
        self.ready = asyncio.get_event_loop().create_future()
        self.groupchat = asyncio.Queue()
        self.add_event_handler("session_start", self.on_start)
        self.add_event_handler("message", self.on_message)

    async def on_start(self, event):
        self.send_presence()
        await self.get_roster()
        if not self.ready.done():
            self.ready.set_result(True)

    def on_message(self, msg):
        if msg["type"] == "groupchat":
            self.groupchat.put_nowait(msg)


def reactions_send(client: MucClient, room: str, target_id: str, emojis):
    """Send our full current set of reactions to a room message, exactly as Adium does: a
    plain-text fallback body of the emoji (a bare space when the set is empty) so the room
    relays the stanza, an XEP-0428 marker so reaction-aware clients hide that body, and the
    reactions element itself."""
    msg = client.make_message(mto=room, mtype="groupchat")

    body = ET.SubElement(msg.xml, "{jabber:client}body")
    body.text = " ".join(emojis) if emojis else " "
    fallback = ET.SubElement(msg.xml, "{%s}fallback" % NS_FALLBACK)
    fallback.set("for", NS_REACTIONS)

    node = ET.Element("{%s}reactions" % NS_REACTIONS)
    if target_id:
        node.set("id", target_id)
    for emoji in emojis:
        child = ET.SubElement(node, "{%s}reaction" % NS_REACTIONS)
        child.text = emoji
    msg.xml.append(node)
    msg.send()


def parse_reactions(msg):
    """(id, [emoji, ...]) for a reactions message, or None when it is not one."""
    node = msg.xml.find("{%s}reactions" % NS_REACTIONS)
    if node is None:
        return None
    emojis = [(child.text or "") for child in node.findall("{%s}reaction" % NS_REACTIONS)]
    return node.get("id"), emojis


def room_stanza_id(msg, room_bare: str):
    """The stanza-id the room stamped (by == the room), the id a reaction names."""
    fallback = None
    for sid in msg.xml.findall("{%s}stanza-id" % NS_SID):
        fallback = fallback or sid.get("id")
        if sid.get("by") == room_bare:
            return sid.get("id")
    return fallback


async def drain_for(queue: asyncio.Queue, predicate, timeout: float = 6.0):
    """First queued item matching predicate, waiting up to timeout in total."""
    loop = asyncio.get_event_loop()
    deadline = loop.time() + timeout
    while True:
        remaining = deadline - loop.time()
        if remaining <= 0:
            raise asyncio.TimeoutError
        msg = await asyncio.wait_for(queue.get(), remaining)
        if predicate(msg):
            return msg


async def run_checks():
    adium = MucClient("adium", "muc-desktop")
    peer = MucClient("peer", "muc-peer")

    for client in (adium, peer):
        client.connect(*SERVER)

    try:
        await asyncio.wait_for(asyncio.gather(adium.ready, peer.ready), 10)
        report("Anmeldung beider Sitzungen", True)
    except asyncio.TimeoutError:
        report("Anmeldung beider Sitzungen", False, "Timeout beim Verbinden")
        return

    room = JID(f"reactions-{uuid.uuid4().hex[:6]}@conference.localhost")
    room_bare = room.bare
    adium_nick, peer_nick = "adium", "peer"

    # adium joins first, so it owns the room; enable archiving so the room stamps a
    # stanza-id on every message, then let peer in.
    try:
        await adium["xep_0045"].join_muc_wait(room, adium_nick, timeout=10)
        form = await adium["xep_0045"].get_room_config(room)
        if "muc#roomconfig_enablearchiving" in form.get_fields():
            form.set_values({"muc#roomconfig_enablearchiving": "1"})
        await adium["xep_0045"].set_room_config(room, form)
        await peer["xep_0045"].join_muc_wait(room, peer_nick, timeout=10)
        report("Raum betreten und Archivierung eingeschaltet", True, room_bare)
    except Exception as e:
        report("Raum betreten und Archivierung eingeschaltet", False, str(e))
        for client in (adium, peer):
            client.disconnect()
        return

    # peer sends a message; adium must see it, stamped with a room stanza-id.
    marker = f"muc-{uuid.uuid4().hex[:8]}"
    peer.send_message(mto=room_bare, mbody=marker, mtype="groupchat")
    target_id = None
    try:
        got = await drain_for(adium.groupchat, lambda m: m["body"] == marker)
        target_id = room_stanza_id(got, room_bare)
        report("Nachricht mit Raum-Stanza-ID (XEP-0359) empfangen",
               bool(target_id), target_id or "keine stanza-id am Stanza")
    except asyncio.TimeoutError:
        report("Nachricht mit Raum-Stanza-ID (XEP-0359) empfangen", False, "nichts angekommen")

    if not target_id:
        # Without an id to point at there is nothing further to verify.
        for client in (adium, peer):
            client.disconnect()
        return

    # adium reacts to that message; peer must see it reflected, naming the same id.
    reactions_send(adium, room_bare, target_id, [THUMB])
    try:
        got = await drain_for(peer.groupchat,
                              lambda m: parse_reactions(m) is not None
                              and JID(m["from"]).resource == adium_nick)
        rid, emojis = parse_reactions(got)
        report("Reaktion (XEP-0444) im Raum gespiegelt und richtig zugeordnet",
               rid == target_id and emojis == [THUMB],
               f"id={rid} emojis={emojis} von={JID(got['from']).resource}")
    except asyncio.TimeoutError:
        report("Reaktion (XEP-0444) im Raum gespiegelt und richtig zugeordnet", False,
               "keine Reaktion angekommen")

    # adium takes the reaction back; peer must see an empty set for the same id.
    reactions_send(adium, room_bare, target_id, [])
    try:
        got = await drain_for(peer.groupchat,
                              lambda m: parse_reactions(m) == (target_id, [])
                              and JID(m["from"]).resource == adium_nick)
        report("Reaktion zurückgenommen (leere Menge)", True, f"id={target_id}")
    except asyncio.TimeoutError:
        report("Reaktion zurückgenommen (leere Menge)", False, "keine leere Reaktion angekommen")

    for client in (adium, peer):
        client.disconnect()
    await asyncio.sleep(0.3)


def main():
    asyncio.get_event_loop().run_until_complete(run_checks())
    print(f"\n{RESULTS.count(True)}/{len(RESULTS)} Prüfungen bestanden")
    sys.exit(0 if all(RESULTS) else 1)


if __name__ == "__main__":
    main()
