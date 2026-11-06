#!/usr/bin/env python3
"""Put one file on the test server's HTTP upload (XEP-0363) as tobias and print its address,
so that the picture in the conversation comes from the local server, over the certificate
Testing/xmpp/server.sh trust made this Mac accept. Run by make-screenshots.sh with the peer
tool's virtualenv: python3 upload.py <file> <content-type>"""
import asyncio, os, sys, subprocess
from slixmpp import ClientXMPP
from slixmpp.xmlstream import ET

path, ctype = sys.argv[1], sys.argv[2]
size = os.path.getsize(path)

class Up(ClientXMPP):
    def __init__(self):
        super().__init__("tobias@localhost/upload", "tobias-pw",
                         plugin_config={'feature_mechanisms': {'unencrypted_plain': True, 'unencrypted_scram': True}})
        self.enable_starttls = False; self.enable_direct_tls = False; self.enable_plaintext = True
        self.register_plugin("xep_0030")
        self.add_event_handler("session_start", self.start)
    async def start(self, _):
        items = await self['xep_0030'].get_items(jid="localhost")
        service = None
        candidates = ["localhost"] + [j for j, node, name in items['disco_items']['items']]
        for j in candidates:
            info = await self['xep_0030'].get_info(jid=j)
            if "urn:xmpp:http:upload:0" in info['disco_info']['features']: service = j
        if not service: print("no upload service"); self.disconnect(); return
        iq = self.make_iq_get(ito=service)
        req = ET.SubElement(iq.xml, "{urn:xmpp:http:upload:0}request")
        req.set("filename", os.path.basename(path)); req.set("size", str(size)); req.set("content-type", ctype)
        res = await iq.send()
        slot = res.xml.find("{urn:xmpp:http:upload:0}slot")
        put = slot.find("{urn:xmpp:http:upload:0}put").get("url"); get = slot.find("{urn:xmpp:http:upload:0}get").get("url")
        headers = ["-H", f"Content-Type: {ctype}"]
        for h in slot.find("{urn:xmpp:http:upload:0}put").findall("{urn:xmpp:http:upload:0}header"):
            headers += ["-H", f"{h.get('name')}: {h.text}"]
        r = subprocess.run(["curl", "-sk", "-o", "/dev/null", "-w", "%{http_code}", "-T", path, *headers, put], capture_output=True, text=True)
        print("PUT", r.stdout.strip(), get)
        self.disconnect()

c = Up(); c.connect(("127.0.0.1", 5222))
asyncio.get_event_loop().run_until_complete(c.disconnected)
