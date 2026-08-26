#!/usr/bin/env python3
"""Offer Adium a file transfer (XEP-0096 SI over XEP-0047 IBB).

Two steps, both automatic: first a throwaway session on the adium account
itself discovers which resource the running Adium is bound to (an account's
resources always see each other's presence, no roster needed), then the peer
account offers that full JID a file. The offer then waits for the human: the
transfer row with its buttons appears in Adium's message view, and clicking
Save accepts the stream, after which the bytes go over IBB.

Usage: sendfile.py <path> [--timeout SECONDS]
"""

import asyncio
import os
import sys
import uuid

from slixmpp import ClientXMPP, JID

SERVER = ("127.0.0.1", 5222)
IBB = "http://jabber.org/protocol/ibb"
SASL_INSECURE = {'feature_mechanisms': {'unencrypted_plain': True,
                                        'unencrypted_scram': True}}


class Sniffer(ClientXMPP):
    """Sits on the adium account just long enough to see its other resources."""

    def __init__(self):
        super().__init__("adium@localhost/sendfile-sniff", "adium-pw", plugin_config=SASL_INSECURE)
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.resources = set()
        self.ready = asyncio.get_event_loop().create_future()
        self.add_event_handler("session_start", self.on_start)
        self.add_event_handler("presence_available", self.on_presence)

    async def on_start(self, event):
        self.send_presence()
        if not self.ready.done():
            self.ready.set_result(True)

    def on_presence(self, presence):
        who = JID(presence["from"])
        if who.bare == "adium@localhost" and who.resource and who.resource != "sendfile-sniff":
            self.resources.add(who.resource)


class Sender(ClientXMPP):
    def __init__(self):
        super().__init__("peer@localhost/filepeer", "peer-pw", plugin_config=SASL_INSECURE)
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        for plugin in ("xep_0030", "xep_0047", "xep_0095", "xep_0096"):
            self.register_plugin(plugin)
        self.ready = asyncio.get_event_loop().create_future()
        self.add_event_handler("session_start", self.on_start)

    async def on_start(self, event):
        self.send_presence()
        if not self.ready.done():
            self.ready.set_result(True)


async def main():
    if len(sys.argv) < 2:
        print("Aufruf: sendfile.py <datei> [--timeout SEKUNDEN]")
        return 2
    path = sys.argv[1]
    timeout = 300
    if "--timeout" in sys.argv:
        timeout = int(sys.argv[sys.argv.index("--timeout") + 1])
    with open(path, "rb") as handle:
        payload = handle.read()
    name = os.path.basename(path)

    # Step one: which resource is the running Adium?
    sniffer = Sniffer()
    sniffer.connect(*SERVER)
    await asyncio.wait_for(sniffer.ready, 10)
    await asyncio.sleep(1.5)
    sniffer.disconnect()
    if not sniffer.resources:
        print("FAIL  kein verbundenes Adium auf adium@localhost gefunden")
        return 1
    target = JID("adium@localhost/" + sorted(sniffer.resources)[0])
    print(f"Adium gefunden: {target}")

    # Step two: offer the file and wait for the click.
    sender = Sender()
    sender.connect(*SERVER)
    await asyncio.wait_for(sender.ready, 10)

    sid = uuid.uuid4().hex
    print(f"Biete '{name}' an ({len(payload)} Bytes); jetzt in Adium annehmen oder ablehnen ...")
    try:
        # slixmpp's form options want mappings, not bare strings
        result = await sender["xep_0096"].request_file_transfer(
            target, sid=sid, name=name, size=len(payload),
            desc="Adium Dateitransfer-Test", mime_type="application/octet-stream",
            methods=[{"value": IBB}], timeout=timeout)
    except asyncio.TimeoutError:
        print("FAIL  niemand hat den Transfer angenommen (Timeout)")
        sender.disconnect()
        return 1
    except Exception as error:
        print(f"ABGELEHNT  {error}")
        print("PASS  Ablehnen-Knopf hat den Transfer sauber abgewiesen"
              if "reject" in str(error).lower() or "forbidden" in str(error).lower() or "cancel" in str(error).lower()
              else "HINWEIS  Fehlerantwort statt Annahme, Details oben")
        sender.disconnect()
        return 0

    print("Angenommen; sende ueber IBB ...")
    stream = await sender["xep_0047"].open_stream(target, sid=sid)
    await stream.sendall(payload)
    await stream.close()
    print(f"PASS  {len(payload)} Bytes uebertragen als '{name}'")
    sender.disconnect()
    await asyncio.sleep(0.3)
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.get_event_loop().run_until_complete(main()))
