# XMPP test server

A local Prosody server for developing and verifying Adium's XMPP features
without touching any real account. Runs as an arm64 Docker container
(Alpine's Prosody 13), reachable only from this machine on
`localhost:5222`.

The server has the features the Adium XMPP roadmap develops against
switched on: Message Carbons (XEP-0280), Message Archive Management
(XEP-0313), Client State Indication (XEP-0352), PEP Native Bookmarks
(XEP-0402) and a MUC component at `conference.localhost`. Encryption is
offered through a self-signed certificate, generated on first start, but
not required, so both the TLS and the plaintext path can be exercised.

## Server

    ./server.sh start      build if needed, start, create the accounts
    ./server.sh stop       stop; data survives in Docker volumes
    ./server.sh status     running state and existing accounts
    ./server.sh logs       follow the server log
    ./server.sh reset      stop and delete all data, certificate included
    ./server.sh selftest   run the automated feature checks
    ./server.sh muc-reactions  group-chat reaction checks (XEP-0444 with XEP-0359)
    ./server.sh omemo-pep      OMEMO announcement checks (XEP-0384)
    ./server.sh roster         make the test accounts contacts of each other
    ./server.sh trust          accept this server's certificate on this Mac
    ./server.sh untrust        take that back

Docker comes from colima on this machine; `colima start` brings the
daemon up if `server.sh` complains that it cannot connect.

`muc-reactions` verifies, without Adium involved, the wire behaviour Adium's
group-chat reactions rely on: two sessions join a room, one sends a message and
the other reacts to it, and the check confirms the room stamps a stanza-id, that
a reaction named against that id is reflected to the other occupant carrying the
same id and emoji, and that an empty set takes it back. It also pins down the
part that is easy to get wrong: a room relays only messages with a body, so the
reaction must ship a fallback body (hidden by an XEP-0428 marker) or it never
arrives.

## Sending files from Adium

Uploads go over HTTPS, and this server's certificate is its own. An unknown certificate is
refused like any other, so the upload fails and Adium quietly falls back to the classic file
transfer, which looks like a bug in the upload code and is not.

    ./server.sh trust

puts that one certificate, for the name `localhost`, into the login keychain. No administrator
rights are involved and `./server.sh untrust` removes it again. Adium has to be restarted
afterwards to notice.

Run `./server.sh roster` as well. Two accounts that have never been introduced are strangers
to each other, and a stranger's files are not fetched by themselves unless the person has said
they should be: Adium's file transfer setting governs that, and its usual value is "only from
people on my contact list". A picture sent between strangers therefore stays an address,
silently and correctly, which looks exactly like a fault in the code that fetches pictures.

With that done, configure both `adium@localhost` and `peer@localhost` in Adium and send a
picture from one to the other. That exercises the whole of our own path in one go: the upload,
the encryption if the conversation is encrypted, the address that carries the key, and the
fetching, decrypting and playing at the far end.

What it does not exercise is whether somebody else's client can read what we produced. For that
the file has to be somewhere they can reach, which a server on this machine is not.

## Accounts

Passwords are the user name with `-pw` appended.

| Account           | Purpose                                    |
| ----------------- | ------------------------------------------ |
| `adium@localhost` | the account to configure in Adium          |
| `peer@localhost`  | the counterpart the peer tool speaks as    |
| `admin@localhost` | server admin, rarely needed                |

In Adium, add an XMPP account `adium@localhost` with connect server
`127.0.0.1`, port 5222. The certificate is self-signed and has to be
accepted once; alternatively allow plaintext for the account, the server
accepts both.

## Counterpart tool

`peer/run.sh` bootstraps a virtualenv with slixmpp on first use.

    peer/run.sh echo             answer everything sent to peer@localhost
    peer/run.sh listen           only print what arrives
    peer/run.sh send "Hallo"     one message to adium@localhost
    peer/run.sh second-device    sit on the adium account as resource
                                 "phone" with carbons enabled: shows what
                                 the Adium under test sends and receives,
                                 and typed lines go out as messages so
                                 their carbons appear in Adium

    peer/run.sh bookmark add raum --autojoin --name "Mein Raum"
    peer/run.sh bookmark remove raum
    peer/run.sh bookmark list

    peer/run.sh selftest         automated feature checks against the server
    peer/run.sh muc-reactions    group-chat reaction checks (XEP-0444/0359)

The bookmark commands act on the adium account's XEP-0402 storage the
way another device would: a running Adium should see additions and
removals appear in its contact list live, and pick everything up at the
next connect otherwise. Rooms without an @ get @conference.localhost
appended.

## Selftest

`server.sh selftest` connects as three sessions (two on the adium
account, one as peer) and checks, without Adium involved, that the rig
itself works: login, message delivery, a carbon copy of a second
device's message, finding that message again through MAM, CSI state
changes without stream breakage, and writing and reading a XEP-0402
bookmark. One PASS/FAIL line each; exit code 0 only if everything
passed. Run it first whenever a feature test behaves strangely, so
server problems and Adium problems stay apart.
