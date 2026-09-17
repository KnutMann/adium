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
        print("peer@localhost verbunden, wartet auf Nachrichten (Ctrl-C beendet)")

    def on_message(self, msg):
        if msg["type"] not in ("chat", "normal"):
            return
        # XEP-0308: a message that names an earlier one instead of standing on its own
        replace = msg.xml.find("{urn:xmpp:message-correct:0}replace")
        if replace is not None:
            print(f"< {msg['from']} KORRIGIERT {replace.get('id')}: {msg['body']}")
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
            print(f"gesendet   id={first_id}: {self.first}")
            await asyncio.sleep(self.delay)
        else:
            first_id = "nie-gesendet-" + first_id
            print(f"uebersprungen, korrigiert wird die unbekannte id {first_id}")

        second = self.make_message(mto=self.to, mbody=self.second, mtype="chat")
        replace = ET.Element("{urn:xmpp:message-correct:0}replace")
        replace.set("id", first_id)
        second.append(replace)
        second.send()
        print(f"korrigiert id={first_id} -> {self.second}")

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
        print("Zweitgerät auf adium@localhost verbunden, Carbons aktiv")
        print("Eingetippte Zeilen gehen als Nachricht an peer@localhost")
        asyncio.get_event_loop().add_reader(0, self.read_stdin)

    def read_stdin(self):
        import sys
        line = sys.stdin.readline().strip()
        if line:
            self.send_message(mto="peer@localhost", mbody=line, mtype="chat")

    def on_carbon_sent(self, msg):
        fwd = msg["carbon_sent"]
        print(f"[carbon, anderes Gerät sandte] an {fwd['to']}: {fwd['body']}")

    def on_carbon_received(self, msg):
        fwd = msg["carbon_received"]
        print(f"[carbon, anderes Gerät empfing] von {fwd['from']}: {fwd['body']}")

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
                print(f"Lesezeichen gesetzt: {self.room} (autojoin={self.autojoin})")
            elif self.action == "remove":
                await self["xep_0060"].retract("adium@localhost", node, self.room, notify=True)
                print(f"Lesezeichen entfernt: {self.room}")
            elif self.action == "list":
                items = await self["xep_0060"].get_items("adium@localhost", node)
                found = list(items["pubsub"]["items"])
                if not found:
                    print("Keine Lesezeichen auf dem Server")
                for item in found:
                    print(f"  {item['id']}: {ET.tostring(item['payload'], encoding='unicode') if item['payload'] is not None else '(leer)'}")
        except Exception as e:
            print(f"Fehler: {e}")
        finally:
            self.disconnect()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true", help="XMPP-Verkehr mitloggen")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("echo", help="als peer@localhost alles beantworten")
    sub.add_parser("listen", help="als peer@localhost nur mitlesen")

    p_send = sub.add_parser("send", help="eine Nachricht senden")
    p_send.add_argument("body")
    p_send.add_argument("--to", default="adium@localhost")
    p_send.add_argument("--account", default="peer", help="absendendes Konto (Standard: peer)")

    p_corr = sub.add_parser("correct", help="etwas sagen und es dann anders sagen (XEP-0308)")
    p_corr.add_argument("first", nargs="?", default="Wir treffen uns um sieben")
    p_corr.add_argument("second", nargs="?", default="Wir treffen uns um acht")
    p_corr.add_argument("--to", default="adium@localhost")
    p_corr.add_argument("--account", default="peer")
    p_corr.add_argument("--only-correction", action="store_true",
                        help="nur die Korrektur senden, ohne das Original")
    p_corr.add_argument("--delay", type=float, default=2.0,
                        help="Sekunden zwischen Nachricht und Korrektur")

    sub.add_parser("second-device", help="als Zweitgerät auf dem adium-Konto sitzen")

    p_bm = sub.add_parser("bookmark", help="Server-Lesezeichen des adium-Kontos bearbeiten")
    p_bm.add_argument("action", choices=["add", "remove", "list"])
    p_bm.add_argument("room", nargs="?", default="testraum",
                      help="Raum (ohne @ wird @conference.localhost angehängt)")
    p_bm.add_argument("--name", help="Anzeigename des Lesezeichens")
    p_bm.add_argument("--autojoin", action="store_true")
    p_bm.add_argument("--nick", help="Spitzname im Raum")

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
