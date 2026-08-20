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

Docker comes from colima on this machine; `colima start` brings the
daemon up if `server.sh` complains that it cannot connect.

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

## Selftest

`server.sh selftest` connects as three sessions (two on the adium
account, one as peer) and checks, without Adium involved, that the rig
itself works: login, message delivery, a carbon copy of a second
device's message, finding that message again through MAM, CSI state
changes without stream breakage, and writing and reading a XEP-0402
bookmark. One PASS/FAIL line each; exit code 0 only if everything
passed. Run it first whenever a feature test behaves strangely, so
server problems and Adium problems stay apart.
