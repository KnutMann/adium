#!/usr/bin/env python3
"""The other side of the conversation in the README's screenshot, played on the local Prosody test server.

Four invented contacts live on the local Prosody test server. "prepare" makes them
contacts of the demo account, gives them names and duck avatars; "online" keeps them
online and lets Tobias, the one the screenshot talks to, act on commands appended to
a command file, one per line:

  say <text>            a message, asking for a receipt and markable
  typing | paused       a chat state
  pic <url> [<text>]    a picture shared as its address (XEP-0066)
  react <emoji> [<id>]  a reaction to the last message from the demo account, or to <id>
  displayed [<id>]      a read marker for the last message from the demo account
  quit

  Run by make-screenshots.sh, with the peer tool's virtualenv (Testing/xmpp/peer/.venv):
  python3 stage.py prepare
  python3 stage.py online <command file>
  SCREENSHOT_AVATARS names the folder with Blue.png, Green.png, Purple.png and Yellow.png.
"""
import asyncio, os, sys, logging
from slixmpp import ClientXMPP

HERE = os.path.dirname(os.path.abspath(__file__))
AVATARS = os.environ.get("SCREENSHOT_AVATARS", os.path.join(HERE, "avatars"))
SASL_INSECURE = {'feature_mechanisms': {'unencrypted_plain': True, 'unencrypted_scram': True}}
SELF = "ada"
PEERS = [("tobias", "Tobias Rehn", "Blue"), ("mira", "Mira Okafor", "Green"),
         ("lars", "Lars Nyström", "Purple"), ("noor", "Noor Haddad", "Yellow")]
PLUGINS = ["xep_0030", "xep_0054", "xep_0153", "xep_0172", "xep_0184", "xep_0333",
           "xep_0444", "xep_0066", "xep_0085", "xep_0115", "xep_0199", "xep_0359"]

def jid(user): return f"{user}@localhost"

class Actor(ClientXMPP):
    def __init__(self, user, name=None, colour=None):
        super().__init__(f"{user}@localhost/desk", f"{user}-pw", plugin_config=SASL_INSECURE)
        self.user, self.name, self.colour = user, name, colour
        self.enable_starttls = False; self.enable_direct_tls = False; self.enable_plaintext = True
        for p in PLUGINS: self.register_plugin(p)
        self.ready = asyncio.Event()
        self.last_in = None
        self.add_event_handler("session_start", self.start)
        self.add_event_handler("presence_subscribe", self.on_subscribe)
        self.add_event_handler("message", self.on_message)

    async def start(self, _):
        await self.get_roster()
        self.send_presence()
        if self.name:
            vcard = self['xep_0054'].make_vcard()
            vcard['FN'] = self.name; vcard['NICKNAME'] = self.name.split()[0]
            await self['xep_0054'].publish_vcard(vcard)
            with open(os.path.join(AVATARS, self.colour + ".png"), "rb") as f: data = f.read()
            await self['xep_0153'].set_avatar(avatar=data, mtype="image/png")
            try: await self['xep_0172'].publish_nick(self.name)
            except Exception as e: print(f"[{self.user}] nick not published: {e}")
            print(f"[{self.user}] online as {self.name} with the {self.colour.lower()} duck")
        self.ready.set()

    def on_subscribe(self, pres):
        who = pres['from'].bare
        self.send_presence(pto=who, ptype='subscribed')
        self.send_presence(pto=who, ptype='subscribe')

    def on_message(self, msg):
        if msg['type'] not in ('chat', 'normal') or not msg['body']: return
        self.last_in = (msg['id'], msg['from'].bare)
        if msg['request_receipt']: self['xep_0184'].ack(msg)
        print(f"[{self.user}] from {msg['from'].bare}: {msg['body']!r} id={msg['id']} markable={bool(msg['markable'])}")

    # Tobias's repertoire
    def say(self, text):
        m = self.make_message(mto=jid(SELF), mbody=text, mtype='chat')
        m['request_receipt'] = True; m['markable'] = True; m['chat_state'] = 'active'
        m.send(); print(f"[{self.user}] said {text!r} id={m['id']}")
    def state(self, which):
        m = self.make_message(mto=jid(SELF), mtype='chat'); m['chat_state'] = which; m.send()
    def pic(self, url, text=None):
        m = self.make_message(mto=jid(SELF), mbody=text or url, mtype='chat')
        m['oob']['url'] = url; m['request_receipt'] = True; m['markable'] = True
        m.send(); print(f"[{self.user}] shared {url}")
    def react(self, emoji, mid=None):
        mid = mid or (self.last_in and self.last_in[0])
        if not mid: print("nothing to react to"); return
        self['xep_0444'].send_reactions(jid(SELF), to_id=mid, reactions=[emoji])
        print(f"[{self.user}] reacted {emoji} to {mid}")
    def displayed(self, mid=None):
        mid = mid or (self.last_in and self.last_in[0])
        if not mid: print("nothing to mark"); return
        self['xep_0333'].send_marker(jid(SELF), mid, 'displayed')
        print(f"[{self.user}] marked {mid} displayed")

def connect(actor):
    actor.connect(("127.0.0.1", 5222))

async def prepare():
    me = Actor(SELF)
    peers = [Actor(u, n, c) for u, n, c in PEERS]
    for a in [me] + peers: connect(a)
    await asyncio.gather(*(a.ready.wait() for a in [me] + peers))
    for u, n, _ in PEERS:
        me.update_roster(jid(u), name=n)
        me.send_presence(pto=jid(u), ptype='subscribe')
    await asyncio.sleep(3)
    await me.get_roster()
    for j in me.client_roster.keys():
        item = me.client_roster[j]
        if j != jid(SELF): print(f"  {j}: name={item['name']!r} subscription={item['subscription']}")
    for a in [me] + peers: a.disconnect()
    await asyncio.sleep(1)

async def online(command_file):
    peers = [Actor(u, n, c) for u, n, c in PEERS]
    for a in peers: connect(a)
    await asyncio.gather(*(a.ready.wait() for a in peers))
    tobias = peers[0]
    open(command_file, "a").close()
    done = 0
    print("ready for commands")
    while True:
        await asyncio.sleep(0.3)
        with open(command_file) as f: lines = f.read().splitlines()
        for line in lines[done:]:
            done += 1
            parts = line.split(" ", 1)
            cmd, rest = parts[0], (parts[1] if len(parts) > 1 else "")
            try:
                if cmd == "say": tobias.say(rest)
                elif cmd in ("typing", "paused"): tobias.state("composing" if cmd == "typing" else "paused")
                elif cmd == "pic": p = rest.split(" ", 1); tobias.pic(p[0], p[1] if len(p) > 1 else None)
                elif cmd == "react": p = rest.split(" "); tobias.react(p[0], p[1] if len(p) > 1 else None)
                elif cmd == "displayed": tobias.displayed(rest or None)
                elif cmd == "quit":
                    for a in peers: a.disconnect()
                    await asyncio.sleep(1); return
                elif cmd: print(f"unknown command {cmd!r}")
            except Exception as e: print(f"command {line!r} failed: {e}")

if __name__ == "__main__":
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(message)s")
    if len(sys.argv) >= 2 and sys.argv[1] == "prepare": asyncio.run(prepare())
    elif len(sys.argv) >= 3 and sys.argv[1] == "online": asyncio.run(online(sys.argv[2]))
    else: print(__doc__); sys.exit(2)
