#!/usr/bin/env python3
"""Make the test accounts contacts of each other.

Without this they are strangers, and a stranger's files are not fetched by themselves unless
the person has said they should be: Adium's file transfer setting governs that, and its usual
value is "only from people on my contact list". A picture sent between two accounts that have
never been introduced therefore stays an address, silently and correctly, which looks exactly
like a fault in the code that fetches pictures.

Real conversations are between contacts, so the test server should be too.
"""

import asyncio
import sys

from slixmpp import ClientXMPP

SERVER = ("127.0.0.1", 5222)
SASL_INSECURE = {'feature_mechanisms': {'unencrypted_plain': True,
                                        'unencrypted_scram': True}}


class Introducer(ClientXMPP):
    def __init__(self, account: str, partner: str):
        super().__init__(f"{account}@localhost/introducer", f"{account}-pw",
                         plugin_config=SASL_INSECURE)
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.partner = f"{partner}@localhost"
        self.settled = asyncio.Event()

        self.add_event_handler("session_start", self._started)
        self.add_event_handler("presence_subscribe", self._asked)

    async def _started(self, _event):
        await self.get_roster()
        self.send_presence()

        #Ask to see them, and put them on the list under a group so they are plainly not strangers
        self.send_presence_subscription(pto=self.partner)
        self.update_roster(self.partner, name=self.partner.split("@")[0], groups=["Test"])
        self.settled.set()

    def _asked(self, presence):
        #And say yes when asked the same thing
        self.send_presence_subscription(pto=presence["from"].bare, ptype="subscribed")


async def run():
    both = [Introducer("adium", "peer"), Introducer("peer", "adium")]
    for one in both:
        one.connect(*SERVER)

    await asyncio.wait_for(asyncio.gather(*[one.settled.wait() for one in both]), 20)

    #Let the two answer each other's request before leaving
    await asyncio.sleep(3)

    for one in both:
        one.disconnect()


def main():
    try:
        asyncio.run(asyncio.wait_for(run(), 40))
    except asyncio.TimeoutError:
        print("FEHLSCHLAG: die Konten haben sich nicht rechtzeitig vorgestellt")
        sys.exit(1)

    print("adium@localhost und peer@localhost stehen jetzt auf der Liste des jeweils anderen.")
    print("In Adium erscheint der neue Kontakt nach dem naechsten Verbinden.")


if __name__ == "__main__":
    main()
