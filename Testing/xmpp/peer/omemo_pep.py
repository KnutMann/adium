#!/usr/bin/env python3
"""OMEMO announcement checks (XEP-0384) for the Adium test server.

This pins down the part of OMEMO that has nothing to do with cryptography and
everything to do with whether anyone can find us: publishing a device list and a
bundle, and another account being able to read both.

Without Adium involved, it publishes exactly the stanzas
Plugins/Purple Service/adiumPurpleOMEMO.m builds, then checks from a second
account that:

  - the device list is readable by somebody who is not subscribed to our
    presence, which is the whole reason for the open access model: a stranger
    who wants to write to us for the first time is precisely somebody who cannot
    read a presence-restricted node;
  - the bundle node, whose name carries the device number, is readable the same
    way and comes back with the key material intact and the right sizes;
  - publishing again replaces the item rather than adding a second one, so a
    reader always sees one current list;
  - adding a device to the list keeps the ones already on it, which is the
    mistake that takes every other device of an account off the air.

Prints one PASS/FAIL line per check and exits non-zero if anything failed.
"""

import asyncio
import base64
import os
import sys

from slixmpp import ClientXMPP
from slixmpp.xmlstream import ET

SERVER = ("127.0.0.1", 5222)
NS_OMEMO = "eu.siacs.conversations.axolotl"
NODE_DEVICELIST = "eu.siacs.conversations.axolotl.devicelist"
NODE_BUNDLES = "eu.siacs.conversations.axolotl.bundles"
NS_PUBSUB = "http://jabber.org/protocol/pubsub"
NS_DATA = "jabber:x:data"
NS_PUBSUB_OWNER = "http://jabber.org/protocol/pubsub#owner"
NS_PUBSUB_ERRORS = "http://jabber.org/protocol/pubsub#errors"

OUR_DEVICE = 1234567
ANOTHER_DEVICE = 7654321

RESULTS = []
SASL_INSECURE = {'feature_mechanisms': {'unencrypted_plain': True,
                                        'unencrypted_scram': True}}


def report(name: str, ok: bool, detail: str = ""):
    RESULTS.append(ok)
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))


def publish_options(publish_parent):
    """The options Adium sends, which is what makes the node readable by anybody."""
    options = ET.SubElement(publish_parent, "{%s}publish-options" % NS_PUBSUB)
    form = ET.SubElement(options, "{%s}x" % NS_DATA)
    form.set("type", "submit")
    for var, kind, value in (("FORM_TYPE", "hidden", NS_PUBSUB + "#publish-options"),
                             ("pubsub#persist_items", None, "true"),
                             ("pubsub#access_model", None, "open")):
        field = ET.SubElement(form, "{%s}field" % NS_DATA)
        field.set("var", var)
        if kind:
            field.set("type", kind)
        ET.SubElement(field, "{%s}value" % NS_DATA).text = value


class Publisher(ClientXMPP):
    """Puts out a device list and a bundle the way Adium does."""

    def __init__(self, account: str, resource: str):
        super().__init__(f"{account}@localhost/{resource}", f"{account}-pw",
                         plugin_config=SASL_INSECURE)
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.ready = asyncio.Event()
        self.add_event_handler("session_start", self._started)

    async def _started(self, _event):
        self.send_presence()
        await self.get_roster()
        self.ready.set()

    async def make_node_open(self, node):
        """Reconfigure an existing node so anybody may read it.

        Needed because publish-options are a PRECONDITION, not a reconfiguration: if the node
        already exists with a different access model, the publish is refused rather than the
        node adjusted. Any account that has used OMEMO from another client, or whose server
        created the node with its own defaults, is in exactly that position.
        """
        iq = self.make_iq_set()
        pubsub = ET.SubElement(iq.xml, "{%s}pubsub" % NS_PUBSUB_OWNER)
        configure = ET.SubElement(pubsub, "{%s}configure" % NS_PUBSUB_OWNER)
        configure.set("node", node)
        form = ET.SubElement(configure, "{%s}x" % NS_DATA)
        form.set("type", "submit")
        for var, kind, value in (("FORM_TYPE", "hidden", NS_PUBSUB + "#node_config"),
                                 ("pubsub#persist_items", None, "true"),
                                 ("pubsub#access_model", None, "open")):
            field = ET.SubElement(form, "{%s}field" % NS_DATA)
            field.set("var", var)
            if kind:
                field.set("type", kind)
            ET.SubElement(field, "{%s}value" % NS_DATA).text = value
        await iq.send(timeout=10)

    async def publish_device_list(self, devices):
        iq = self.make_iq_set()
        pubsub = ET.SubElement(iq.xml, "{%s}pubsub" % NS_PUBSUB)
        publish = ET.SubElement(pubsub, "{%s}publish" % NS_PUBSUB)
        publish.set("node", NODE_DEVICELIST)
        item = ET.SubElement(publish, "{%s}item" % NS_PUBSUB)
        item.set("id", "current")
        lst = ET.SubElement(item, "{%s}list" % NS_OMEMO)
        for device in devices:
            entry = ET.SubElement(lst, "{%s}device" % NS_OMEMO)
            entry.set("id", str(device))
        publish_options(pubsub)
        await iq.send(timeout=10)

    async def publish_bundle(self, device):
        iq = self.make_iq_set()
        pubsub = ET.SubElement(iq.xml, "{%s}pubsub" % NS_PUBSUB)
        publish = ET.SubElement(pubsub, "{%s}publish" % NS_PUBSUB)
        publish.set("node", f"{NODE_BUNDLES}:{device}")
        item = ET.SubElement(publish, "{%s}item" % NS_PUBSUB)
        item.set("id", "current")
        bundle = ET.SubElement(item, "{%s}bundle" % NS_OMEMO)

        signed = ET.SubElement(bundle, "{%s}signedPreKeyPublic" % NS_OMEMO)
        signed.set("signedPreKeyId", "1")
        signed.text = base64.b64encode(b"\x05" + os.urandom(32)).decode()

        ET.SubElement(bundle, "{%s}signedPreKeySignature" % NS_OMEMO).text = \
            base64.b64encode(os.urandom(64)).decode()
        ET.SubElement(bundle, "{%s}identityKey" % NS_OMEMO).text = \
            base64.b64encode(b"\x05" + os.urandom(32)).decode()

        prekeys = ET.SubElement(bundle, "{%s}prekeys" % NS_OMEMO)
        for number in range(1, 101):
            one = ET.SubElement(prekeys, "{%s}preKeyPublic" % NS_OMEMO)
            one.set("preKeyId", str(number))
            one.text = base64.b64encode(b"\x05" + os.urandom(32)).decode()

        publish_options(pubsub)
        await iq.send(timeout=10)


class Reader(ClientXMPP):
    """A second account, deliberately not subscribed to the first one's presence."""

    def __init__(self, account: str, resource: str):
        super().__init__(f"{account}@localhost/{resource}", f"{account}-pw",
                         plugin_config=SASL_INSECURE)
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.ready = asyncio.Event()
        self.add_event_handler("session_start", self._started)

    async def _started(self, _event):
        self.send_presence()
        await self.get_roster()
        self.ready.set()

    async def fetch_items(self, who: str, node: str):
        iq = self.make_iq_get(ito=who)
        pubsub = ET.SubElement(iq.xml, "{%s}pubsub" % NS_PUBSUB)
        items = ET.SubElement(pubsub, "{%s}items" % NS_PUBSUB)
        items.set("node", node)
        items.set("max_items", "1")
        answer = await iq.send(timeout=10)
        return answer.xml


def devices_in(answer):
    lst = answer.find(".//{%s}list" % NS_OMEMO)
    if lst is None:
        return None
    found = []
    for entry in lst.findall("{%s}device" % NS_OMEMO):
        identifier = entry.get("id")
        if identifier and identifier.isdigit():
            found.append(int(identifier))
    return found


async def run():
    publisher = Publisher("adium", "omemo-publisher")
    reader = Reader("peer", "omemo-reader")

    publisher.connect(*SERVER)
    reader.connect(*SERVER)
    await asyncio.wait_for(asyncio.gather(publisher.ready.wait(), reader.ready.wait()), 20)

    # Publishing a list, and a stranger being able to read it
    needed_reconfiguring = False
    try:
        await publisher.publish_device_list([OUR_DEVICE])
        report("Eine Geraeteliste laesst sich veroeffentlichen", True)
    except Exception as problem:
        # The node may already exist with the wrong access model, and publish-options only
        # state a condition rather than changing it. Then the node has to be reconfigured.
        if "precondition-not-met" not in str(problem):
            report("Eine Geraeteliste laesst sich veroeffentlichen", False, str(problem))
            return
        needed_reconfiguring = True
        try:
            await publisher.make_node_open(NODE_DEVICELIST)
            await publisher.publish_device_list([OUR_DEVICE])
            report("Ein Knoten mit falschem Zugriffsmodell laesst sich umstellen und dann beschreiben", True)
        except Exception as second:
            report("Ein Knoten mit falschem Zugriffsmodell laesst sich umstellen und dann beschreiben",
                   False, str(second))
            return

    if not needed_reconfiguring:
        report("Ein Knoten mit falschem Zugriffsmodell laesst sich umstellen und dann beschreiben",
               True, "nicht noetig gewesen")

    try:
        answer = await reader.fetch_items("adium@localhost", NODE_DEVICELIST)
        found = devices_in(answer)
        report("Ein fremdes Konto darf die Liste lesen", found is not None,
               "kein list-Element" if found is None else "")
        report("und findet die Geraetenummer darin", found == [OUR_DEVICE], str(found))
    except Exception as problem:
        report("Ein fremdes Konto darf die Liste lesen", False, str(problem))

    # A bundle, whose node name carries the device number
    bundle_node = f"{NODE_BUNDLES}:{OUR_DEVICE}"
    try:
        await publisher.publish_bundle(OUR_DEVICE)
        report("Ein Buendel laesst sich veroeffentlichen", True)
    except Exception as problem:
        if "precondition-not-met" not in str(problem):
            report("Ein Buendel laesst sich veroeffentlichen", False, str(problem))
            return
        try:
            await publisher.make_node_open(bundle_node)
            await publisher.publish_bundle(OUR_DEVICE)
            report("Ein Buendel laesst sich veroeffentlichen", True, "nach Umstellung des Knotens")
        except Exception as second:
            report("Ein Buendel laesst sich veroeffentlichen", False, str(second))
            return

    try:
        answer = await reader.fetch_items("adium@localhost", f"{NODE_BUNDLES}:{OUR_DEVICE}")
        bundle = answer.find(".//{%s}bundle" % NS_OMEMO)
        report("Ein fremdes Konto darf das Buendel lesen", bundle is not None)

        if bundle is not None:
            identity = bundle.find("{%s}identityKey" % NS_OMEMO)
            signed = bundle.find("{%s}signedPreKeyPublic" % NS_OMEMO)
            signature = bundle.find("{%s}signedPreKeySignature" % NS_OMEMO)
            prekeys = bundle.findall("{%s}prekeys/{%s}preKeyPublic" % (NS_OMEMO, NS_OMEMO))

            report("Die Identitaet kommt in der Groesse zurueck, in der sie ging",
                   identity is not None and len(base64.b64decode(identity.text)) == 33)
            report("Der signierte Schluessel traegt seine Nummer",
                   signed is not None and signed.get("signedPreKeyId") == "1")
            report("Die Unterschrift ist vierundsechzig Byte lang",
                   signature is not None and len(base64.b64decode(signature.text)) == 64)
            report("Alle hundert Einmalschluessel sind da", len(prekeys) == 100,
                   f"es waren {len(prekeys)}")
    except Exception as problem:
        report("Ein fremdes Konto darf das Buendel lesen", False, str(problem))

    # Publishing again replaces rather than adds
    try:
        await publisher.publish_device_list([OUR_DEVICE, ANOTHER_DEVICE])
        answer = await reader.fetch_items("adium@localhost", NODE_DEVICELIST)
        found = devices_in(answer)
        report("Eine zweite Veroeffentlichung ersetzt die erste",
               found is not None and sorted(found) == sorted([OUR_DEVICE, ANOTHER_DEVICE]),
               str(found))

        items = answer.findall(".//{%s}items/{%s}item" % (NS_PUBSUB, NS_PUBSUB))
        report("und hinterlaesst genau einen Eintrag", len(items) == 1, f"es waren {len(items)}")
    except Exception as problem:
        report("Eine zweite Veroeffentlichung ersetzt die erste", False, str(problem))

    # A node nobody has ever published to: the answer is an error, not an empty list,
    # and Adium has to read that as "this person does not do OMEMO" rather than as a failure
    try:
        await reader.fetch_items("admin@localhost", NODE_DEVICELIST)
        report("Ein Konto ohne OMEMO antwortet ueberhaupt", True)
    except Exception as problem:
        kind = type(problem).__name__
        report("Ein Konto ohne OMEMO antwortet mit einem Fehler, nicht mit Schweigen",
               "IqError" in kind or "item-not-found" in str(problem), f"{kind}: {problem}")

    publisher.disconnect()
    reader.disconnect()


def main():
    try:
        asyncio.run(asyncio.wait_for(run(), 60))
    except asyncio.TimeoutError:
        report("Die Pruefung laeuft in der vorgesehenen Zeit durch", False, "Zeitueberschreitung")

    print()
    print("ALLE PRUEFUNGEN BESTANDEN" if all(RESULTS) and RESULTS else "FEHLSCHLAEGE")
    sys.exit(0 if all(RESULTS) and RESULTS else 1)


if __name__ == "__main__":
    main()
