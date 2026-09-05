#!/usr/bin/env python3
"""Walks the exact road Adium's AMPurpleJabberHTTPFileUpload takes, without Adium.

Sends the same stanzas the Adium class sends (disco#info and disco#items on the
domain, disco#info on every item, then a versioned slot request) and applies the
same acceptance rules to the answers: both slot addresses must be https, and
only the three headers XEP-0363 allows are honored. Then a small PNG really goes
up into the slot and is fetched back. One PASS/FAIL line per step.
"""

import asyncio
import base64
import ssl
import sys
import urllib.request

from slixmpp import ClientXMPP
from slixmpp.xmlstream import ET

SERVER = ("127.0.0.1", 5222)
NS0 = "urn:xmpp:http:upload:0"
NS_LEGACY = "urn:xmpp:http:upload"
SASL_INSECURE = {'feature_mechanisms': {'unencrypted_plain': True,
                                        'unencrypted_scram': True}}

# A valid 1x1 PNG
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQAB"
    "h6FO1AAAAABJRU5ErkJggg==")

RESULTS = []


def report(name, ok, detail=""):
    RESULTS.append(ok)
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))


class Probe(ClientXMPP):
    def __init__(self):
        super().__init__("adium@localhost/uploadprobe", "adium-pw", plugin_config=SASL_INSECURE)
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.add_event_handler("session_start", self.on_start)

    async def disco(self, to, kind):
        iq = self.make_iq_get(ito=to)
        iq.xml.append(ET.Element(f"{{http://jabber.org/protocol/disco#{kind}}}query"))
        return await iq.send()

    async def find_service(self):
        """The same walk the Adium class does: the domain first, then its items."""
        candidates = ["localhost"]
        try:
            items = await self.disco("localhost", "items")
            query = items.xml.find("{http://jabber.org/protocol/disco#items}query")
            if query is not None:
                for item in query:
                    jid = item.get("jid")
                    if jid:
                        candidates.append(jid)
        except Exception as error:
            report("disco#items auf die Domain", False, str(error))
            return None, None, None

        for jid in candidates:
            try:
                info = await self.disco(jid, "info")
            except Exception:
                continue
            query = info.xml.find("{http://jabber.org/protocol/disco#info}query")
            if query is None:
                continue
            features = {feature.get("var")
                        for feature in query.findall("{http://jabber.org/protocol/disco#info}feature")}
            if NS0 in features or NS_LEGACY in features:
                namespace = NS0 if NS0 in features else NS_LEGACY
                max_size = 0
                for form in query.findall("{jabber:x:data}x"):
                    for field in form.findall("{jabber:x:data}field"):
                        if field.get("var") == "max-file-size":
                            value = field.find("{jabber:x:data}value")
                            if value is not None and value.text:
                                max_size = int(value.text)
                return jid, namespace, max_size
        return None, None, None

    async def request_slot(self, service, namespace, filename, size, content_type):
        """The versioned request, exactly as the Adium class sends it."""
        iq = self.make_iq_get(ito=service)
        request = ET.Element(f"{{{namespace}}}request")
        if namespace == NS0:
            request.set("filename", filename)
            request.set("size", str(size))
            request.set("content-type", content_type)
        else:
            for name, text in (("filename", filename), ("size", str(size)),
                               ("content-type", content_type)):
                child = ET.SubElement(request, f"{{{namespace}}}{name}")
                child.text = text
        iq.xml.append(request)
        answer = await iq.send()

        slot = answer.xml.find(f"{{{namespace}}}slot")
        if slot is None:
            return None, None, None
        put = slot.find(f"{{{namespace}}}put")
        get = slot.find(f"{{{namespace}}}get")
        if put is None or get is None:
            return None, None, None

        put_url = put.get("url") or (put.text or "").strip()
        get_url = get.get("url") or (get.text or "").strip()

        # The same allowlist the Adium class applies
        headers = {}
        for header in put.findall(f"{{{namespace}}}header"):
            name = header.get("name") or ""
            if name.lower() in ("authorization", "cookie", "expires") and header.text:
                headers[name] = header.text
        return put_url, headers, get_url

    async def on_start(self, event):
        self.send_presence()
        try:
            service, namespace, max_size = await self.find_service()
            report("Upload-Dienst per Discovery gefunden", bool(service),
                   f"{service}, {namespace}, Limit {max_size}" if service else "keiner announced ihn")
            if not service:
                return

            put_url, headers, get_url = await self.request_slot(
                service, namespace, "probe.png", len(PNG), "image/png")
            report("Slot erhalten", bool(put_url and get_url), f"put={put_url}")
            if not put_url:
                return

            https_only = put_url.startswith("https://") and get_url.startswith("https://")
            report("Beide Adressen https (Adiums Bedingung)", https_only,
                   "" if https_only else f"put={put_url} get={get_url}")
            if not https_only:
                return

            # The self-signed test certificate is fine here; Adium talks to real servers
            context = ssl.create_default_context()
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE

            request = urllib.request.Request(put_url, data=PNG, method="PUT")
            request.add_header("Content-Type", "image/png")
            for name, value in headers.items():
                request.add_header(name, value)
            with urllib.request.urlopen(request, context=context, timeout=15) as answer:
                report("HTTPS-PUT angenommen", answer.status // 100 == 2, f"Status {answer.status}")

            with urllib.request.urlopen(get_url, context=context, timeout=15) as answer:
                data = answer.read()
            report("Zurückgeholt und identisch", data == PNG, f"{len(data)} Bytes")
        except Exception as error:
            report("Ablauf", False, repr(error))
        finally:
            self.disconnect()


def main():
    probe = Probe()
    probe.connect(*SERVER)
    loop = asyncio.get_event_loop()
    loop.run_until_complete(probe.disconnected)
    print(f"\n{RESULTS.count(True)}/{len(RESULTS)} Prüfungen bestanden")
    sys.exit(0 if RESULTS and all(RESULTS) else 1)


if __name__ == "__main__":
    main()
