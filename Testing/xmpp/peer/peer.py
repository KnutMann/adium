#!/usr/bin/env python3
"""Counterpart tooling for the Adium XMPP test server.

Speaks as peer@localhost (or as a second device on the adium account), so
features under development in Adium have something on the other end that is
scriptable and honest about what it received.
"""

import argparse
import asyncio
import logging

from slixmpp import ClientXMPP
from slixmpp.xmlstream import ET

SERVER = ("127.0.0.1", 5222)


SASL_INSECURE = {'feature_mechanisms': {'unencrypted_plain': True,
                                        'unencrypted_scram': True}}


def password_for(user: str) -> str:
    return f"{user}-pw"


class Peer(ClientXMPP):
    """peer@localhost: prints what it gets; in echo mode it answers too."""

    def __init__(self, echo: bool):
        super().__init__("peer@localhost/peer", password_for("peer"), plugin_config=SASL_INSECURE)
        self.echo = echo
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.add_event_handler("session_start", self.on_start)
        self.add_event_handler("message", self.on_message)

    async def on_start(self, event):
        self.send_presence()
        await self.get_roster()
        print("peer@localhost connected, waiting for messages (Ctrl-C ends it)")

    def on_message(self, msg):
        if msg["type"] not in ("chat", "normal"):
            return
        # XEP-0308: a message that names an earlier one instead of standing on its own
        replace = msg.xml.find("{urn:xmpp:message-correct:0}replace")
        if replace is not None:
            print(f"< {msg['from']} CORRECTS {replace.get('id')}: {msg['body']}")
        else:
            print(f"< {msg['from']} (id={msg['id']}): {msg['body']}")
        if self.echo and msg["body"]:
            msg.reply(f"Echo: {msg['body']}").send()


class OneShotSender(ClientXMPP):
    def __init__(self, account: str, to: str, body: str):
        super().__init__(f"{account}@localhost/oneshot", password_for(account), plugin_config=SASL_INSECURE)
        self.to = to
        self.body = body
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.add_event_handler("session_start", self.on_start)

    async def on_start(self, event):
        self.send_presence()
        self.send_message(mto=self.to, mbody=self.body, mtype="chat")
        # Give the stanza a moment on the wire before disconnecting
        await asyncio.sleep(0.5)
        self.disconnect()


class Corrector(ClientXMPP):
    """Says something, then says it differently (XEP-0308).

    The correction is an ordinary message carrying <replace id='...'/> naming the
    first one. Adium should rewrite the line that is already there rather than put
    a second one under it, and mark it as corrected. With --only-correction the
    first message is skipped, which is the case where the message being named is
    not on the page at all.
    """

    def __init__(self, account: str, to: str, first: str, second: str, only_correction: bool, delay: float):
        super().__init__(f"{account}@localhost/corrector", password_for(account), plugin_config=SASL_INSECURE)
        self.to = to
        self.first = first
        self.second = second
        self.only_correction = only_correction
        self.delay = delay
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.add_event_handler("session_start", self.on_start)

    async def on_start(self, event):
        self.send_presence()

        first = self.make_message(mto=self.to, mbody=self.first, mtype="chat")
        first_id = first["id"]
        if not self.only_correction:
            first.send()
            print(f"sent       id={first_id}: {self.first}")
            await asyncio.sleep(self.delay)
        else:
            first_id = "never-sent-" + first_id
            print(f"skipped, the correction points at the unknown id {first_id}")

        second = self.make_message(mto=self.to, mbody=self.second, mtype="chat")
        replace = ET.Element("{urn:xmpp:message-correct:0}replace")
        replace.set("id", first_id)
        second.append(replace)
        second.send()
        print(f"corrected  id={first_id} -> {self.second}")

        await asyncio.sleep(0.5)
        self.disconnect()


class SecondDevice(ClientXMPP):
    """A second resource on the adium account, carbons enabled.

    Whatever the Adium under test sends or receives should show up here as a
    carbon copy; whatever is typed here (stdin) is sent to peer@localhost and
    should show up in Adium the same way.
    """

    def __init__(self):
        super().__init__("adium@localhost/phone", password_for("adium"), plugin_config=SASL_INSECURE)
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.register_plugin("xep_0280")
        self.add_event_handler("session_start", self.on_start)
        self.add_event_handler("carbon_sent", self.on_carbon_sent)
        self.add_event_handler("carbon_received", self.on_carbon_received)
        self.add_event_handler("message", self.on_message)

    async def on_start(self, event):
        self.send_presence()
        await self.get_roster()
        await self["xep_0280"].enable()
        print("Second device on adium@localhost connected, carbons enabled")
        print("Typed lines go to peer@localhost as a message")
        asyncio.get_event_loop().add_reader(0, self.read_stdin)

    def read_stdin(self):
        import sys
        line = sys.stdin.readline().strip()
        if line:
            self.send_message(mto="peer@localhost", mbody=line, mtype="chat")

    def on_carbon_sent(self, msg):
        fwd = msg["carbon_sent"]
        print(f"[carbon, the other device sent] to {fwd['to']}: {fwd['body']}")

    def on_carbon_received(self, msg):
        fwd = msg["carbon_received"]
        print(f"[carbon, the other device received] from {fwd['from']}: {fwd['body']}")

    def on_message(self, msg):
        if msg["type"] in ("chat", "normal") and msg["body"]:
            print(f"< {msg['from']}: {msg['body']}")


class BookmarkTool(ClientXMPP):
    """Act on the adium account's XEP-0402 bookmarks like another device would."""

    def __init__(self, action, room, name=None, autojoin=False, nick=None):
        super().__init__("adium@localhost/bookmarktool", password_for("adium"), plugin_config=SASL_INSECURE)
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        self.register_plugin("xep_0060")
        self.action = action
        self.room = room if "@" in room else f"{room}@conference.localhost"
        self.bm_name = name
        self.autojoin = autojoin
        self.nick = nick
        self.add_event_handler("session_start", self.on_start)

    async def on_start(self, event):
        from slixmpp.xmlstream import ET
        node = "urn:xmpp:bookmarks:1"
        try:
            if self.action == "add":
                attrs = f" name='{self.bm_name}'" if self.bm_name else ""
                payload = (f"<conference xmlns='{node}'{attrs} "
                           f"autojoin='{'true' if self.autojoin else 'false'}'>"
                           + (f"<nick>{self.nick}</nick>" if self.nick else "")
                           + "</conference>")
                await self["xep_0060"].publish("adium@localhost", node,
                                               id=self.room, payload=ET.fromstring(payload))
                print(f"Bookmark set: {self.room} (autojoin={self.autojoin})")
            elif self.action == "remove":
                await self["xep_0060"].retract("adium@localhost", node, self.room, notify=True)
                print(f"Bookmark removed: {self.room}")
            elif self.action == "list":
                items = await self["xep_0060"].get_items("adium@localhost", node)
                found = list(items["pubsub"]["items"])
                if not found:
                    print("No bookmarks on the server")
                for item in found:
                    print(f"  {item['id']}: {ET.tostring(item['payload'], encoding='unicode') if item['payload'] is not None else '(empty)'}")
        except Exception as e:
            print(f"Error: {e}")
        finally:
            self.disconnect()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true", help="log the XMPP traffic")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("echo", help="answer everything as peer@localhost")
    sub.add_parser("listen", help="only listen in as peer@localhost")

    p_send = sub.add_parser("send", help="send one message")
    p_send.add_argument("body")
    p_send.add_argument("--to", default="adium@localhost")
    p_send.add_argument("--account", default="peer", help="the sending account (default: peer)")

    p_corr = sub.add_parser("correct", help="say something and then say it differently (XEP-0308)")
    p_corr.add_argument("first", nargs="?", default="We are meeting at seven")
    p_corr.add_argument("second", nargs="?", default="We are meeting at eight")
    p_corr.add_argument("--to", default="adium@localhost")
    p_corr.add_argument("--account", default="peer")
    p_corr.add_argument("--only-correction", action="store_true",
                        help="send only the correction, without the original")
    p_corr.add_argument("--delay", type=float, default=2.0,
                        help="seconds between the message and the correction")

    sub.add_parser("second-device", help="sit on the adium account as a second device")

    p_bm = sub.add_parser("bookmark", help="edit the server bookmarks of the adium account")
    p_bm.add_argument("action", choices=["add", "remove", "list"])
    p_bm.add_argument("room", nargs="?", default="testroom",
                      help="room (without an @, @conference.localhost is appended)")
    p_bm.add_argument("--name", help="display name of the bookmark")
    p_bm.add_argument("--autojoin", action="store_true")
    p_bm.add_argument("--nick", help="nickname in the room")

    args = parser.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.WARNING,
                        format="%(levelname)-8s %(message)s")

    if args.command in ("echo", "listen"):
        client = Peer(echo=(args.command == "echo"))
    elif args.command == "send":
        client = OneShotSender(args.account, args.to, args.body)
    elif args.command == "correct":
        client = Corrector(args.account, args.to, args.first, args.second,
                           args.only_correction, args.delay)
    elif args.command == "second-device":
        client = SecondDevice()
    elif args.command == "bookmark":
        client = BookmarkTool(args.action, args.room, name=args.name,
                              autojoin=args.autojoin, nick=args.nick)

    client.connect(*SERVER)
    try:
        if args.command in ("send", "bookmark", "correct"):
            client.loop.run_until_complete(client.disconnected)
        else:
            client.loop.run_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
