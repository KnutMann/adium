# Adium (revival fork)

This is a fork of the original [Adium](https://adium.im)
([source](https://github.com/adium/adium)) that revives and modernizes
it for current macOS. It began as an Apple Silicon (arm64) port, as
the original is an Intel-only binary from 2021. Since then much has
changed: WhatsApp, Telegram, Signal and Microsoft Teams arrived
next to the classic services that stood the test of time, along with
full Dark Mode, replies straight from Notification Center banners,
a rebuilt System Settings-style preferences window, a WKWebView
message view, and a long list of fixes for how modern macOS behaves.

**Adium was created and developed by the Adium team.** All credit for
the application itself belongs to the original developers; see
[Copyright.txt](Copyright.txt). This fork is not affiliated with or
endorsed by them. It is maintained by a long-time Adium user who
simply wants to keep a beloved app alive after many years of use. The
upstream project has been inactive since 2021.

Current version: **1.8.0**.

## Original project

* Website: <https://adium.im>
* Source: <https://github.com/adium/adium>
* Last official release (Intel; on Apple Silicon it runs only through
  Rosetta 2, which Apple is phasing out):
  [Adium 1.5.10.4](https://adiumx.cachefly.net/Adium_1.5.10.4.dmg)

## What this fork changes

### Messaging and services

* WhatsApp (via
  [purple-gowhatsapp](https://github.com/hoehermann/purple-gowhatsapp)):
  QR-code device linking, inline images and voice notes, reactions,
  typing, read markers, group chats with member lists, profile
  pictures, business account names, an optional channel filter, and
  address-book names
* Telegram (via the bundled
  [tdlib-purple](https://github.com/adrighem/tdlib-purple) plugin)
  with the same everyday features, plus address-book integration
* Signal (via
  [purple-presage](https://github.com/hoehermann/purple-presage)),
  linked to your phone as an official companion device
* Microsoft Teams (via
  [purple-teams](https://github.com/EionRobb/purple-teams)), both work
  and personal accounts
* IRC modernized: the built-in IRC protocol is replaced by
  [purple2-ircv3](https://github.com/EionRobb/purple2-ircv3), which
  speaks the same protocol plus typing notifications and other IRCv3
  capabilities
* XMPP brought forward: message carbons (XEP-0280), so a conversation
  continued on another device shows up here too; client state
  indication (XEP-0352), telling the server when Adium is in the
  background; room bookmarks synchronized with other clients
  (XEP-0402), including autojoin; delivery receipts (XEP-0184) and read
  markers (XEP-0333), the latter now requested on outgoing messages too,
  so a message you send can be confirmed delivered and then read;
  message reactions (XEP-0444), sent from the message's context menu
  and delivered to the exact message they name, in direct chats and
  rooms alike; pictures shared by modern clients through HTTP upload
  (XEP-0363, announced per XEP-0066) are shown in the conversation
  itself rather than as a bare link, governed by the same setting that
  controls automatic file transfers, including its restriction to
  contacts of your own list
* OTR migrated to the libotr 4.x API
* Removed services whose networks no longer exist: AIM, ICQ, MSN,
  Yahoo, Google Talk, MobileMe, LiveJournal, Sametime, Twitter, Zephyr
  and Meanwhile

Still supported classic services: **XMPP/Jabber, IRC, Gadu-Gadu,
Novell GroupWise and SIMPLE**, plus OTR encryption and tabbed chats in
a modern look.

### Dark Mode and interface

* Full Dark Mode: the application chrome follows the system
  appearance, or a light/dark choice of its own
* A rebuilt preferences window in the style of System Settings: a
  source-list sidebar, cards instead of boxed groups, and a reusable
  settings form every pane is laid out on
* Installed xtras are managed in that window rather than in a window of
  their own, one card per category, and every row opens a page about
  that xtra: its icon, what it says it is, and the fields its manifest
  fills in
* The chat message view renders with WKWebView; the last legacy
  WebView is gone (libpurple's protocol forms are native Cocoa now)
* Two bundled monochrome service icon sets in the plain style of
  macOS's own symbols, one for light and one for dark
* Tab tear-off works again: drag a chat out into its own window, or
  back into another, with a live preview while dragging
* A bit of nostalgia: the now-playing music status supports
  **Apple Music, Spotify and Swinsian**
* Modern window chrome, tab-bar vibrancy, and a sweep of fixes for
  focus rings, scrolling, contact-list drawing and tooltips on recent
  macOS

### JavaScript plugins for the message view

* A new xtra type: an `.AdiumPlugin` bundle carrying one JavaScript
  file that changes how messages are displayed. It works in every
  message style, needs no compiled code, and therefore never worries
  about processor architectures
* Five such plugins come bundled: **Read Receipts** draws the familiar
  ticks next to the timestamp as a sent message advances (one grey
  tick when the server has it, a grey pair once delivered, a blue pair
  once read); **Reaction Chips** gathers emoji reactions as small
  chips on the message they belong to; **Big Emoji** enlarges short
  emoji-only messages; **Markdown Light** renders the usual asterisk
  and tilde markers as bold, italic and strikethrough; **Code Blocks**
  sets backticked spans and fenced blocks in monospace
* Built security first: every plugin runs in its own isolated script
  world, the message window refuses all remote network loads, and a
  plugin only ever sees the rendered display, never the text you send,
  your logs, or the network
* XtrasCreator authors the new type, with a scaffold to start from,
  an editor, and a lint pass that catches the common mistakes

### Notifications

* Notifications go through the macOS Notification Center, replacing
  Growl
* Reply straight from the banner: message notifications carry a
  text field, and the answer is sent without ever bringing Adium
  forward

### Platform and security

* Native arm64 build; the app bundle is self-contained, with no
  Homebrew or other third-party runtime dependency
* All bundled libraries are native arm64, built from pinned sources
* Bundled libpurple upgraded from 2.12.0 (2017) to 2.14.14, on a
  current glib
* Server certificates are actually verified (SecTrust with a
  proper trust prompt) on every SSL connection, including IRC, where
  the old code silently accepted anything
* Passwords stored through the Keychain (SecItem) API
* Address book integration moved from the AddressBook framework
  (deprecated since 2015) to the Contacts framework, with the modern
  permission prompt; cards are matched by phone number, chat address
  or a manual link

### Localization

* String extraction caught up: hundreds of strings the app already
  showed but had never been extracted are now translatable, filled in
  across the 26 shipped languages

### Tools

* **XtrasCreator**, the companion app for making Adium xtras, rebuilt
  from scratch on a modern base (`Other/XtrasCreator`): it authors
  emoticon sets, sound sets, status/service/menu-bar/group-chat icon
  packs, dock icons, message styles, contact list themes and layouts,
  and script packs, and writes the description Adium shows on an
  xtra's page
* **Contact Pictures**, opened from the Address Book settings: the
  cards linked to your chat contacts, each with the chat picture and
  the card picture side by side, and one button that puts the chat
  picture on the card. This is the single write Adium ever makes to
  the address book, and it happens only when that button is pressed

### Adopted from the unreleased 1.6/1.7 line

Adium's development did not stop at the last state of adium/adium:
the Mercurial mainline and community branches continued toward an
Adium 1.6/1.7 that was never released, preserved today in forks such
as [shtrom/adium](https://github.com/shtrom/adium).

* The emoticon picker in the message entry field, which replaces the
  old emoticon toolbar item
* Room configuration window for owners of XMPP chat rooms
* OTR messages routed to the contact's most recently active device
  instead of the best-ranked one
* Transcripts split at midnight, so a chat left open for days shows
  up on every day it covers

This is a work in progress; expect rough edges.

## System requirements

* Apple Silicon Mac, macOS 11 or later
* Everything is native arm64, including all bundled dependencies
  (libpurple, glib, libotr, ...): no Homebrew required to run
* Xcode for building (there are no binary releases at this time)

For Intel Macs and older systems, use the original
[Adium 1.5.10.4](https://adiumx.cachefly.net/Adium_1.5.10.4.dmg).

## Building

	git clone --recursive https://github.com/KnutMann/adium.git
	cd adium
	./bootstrap.sh

The app lands in `build/Release/Adium.app` (ad-hoc signed, so it runs
on the machine that built it; distributing binaries to others would
require a proper signing identity). `bootstrap.sh` builds the
AIUtilities and MMTabBarView subprojects first and stages their
products, then builds the main project.

### Building it yourself

One command from a fresh checkout to an installed application:

    ./install.sh

Everything beyond Xcode is checked into the repository as prebuilt arm64
binaries. The script verifies the bundled protocol plug-ins (including a
functional probe that asks libpurple itself whether every plug-in's protocol
registers - the failure mode it guards against is silent), builds the app,
verifies the result and installs it to /Applications. `--build-only` skips the
install, `--debug` builds the Debug configuration. The same verification runs
as a phase of every Xcode build.

The **XtrasCreator** companion app (see Tools above) builds
separately:
`xcodebuild -project Other/XtrasCreator/XtrasCreator.xcodeproj build`.

All required libraries (libpurple, glib, libotr, libgcrypt, ...) are
vendored as prebuilt arm64 frameworks in the repository. Rebuilding
them from source is only necessary when upgrading a dependency or
patching one; see `Dependencies/build.sh` (this does require a
Homebrew toolchain).

## License

GNU GPL v2 or later, see [License.txt](License.txt). Original code
copyright the Adium team and contributors
([Copyright.txt](Copyright.txt)).

### Bundled third-party binaries and their sources

This repository ships some components as prebuilt arm64 binaries. The
corresponding sources are publicly available at the exact revisions
listed here (the `Dependencies/patches/` directories document every
local change on top of them):

| Binary | Project | Revision | License |
| --- | --- | --- | --- |
| `PurplePlugins/libwhatsmeow.so` | [purple-gowhatsapp](https://github.com/hoehermann/purple-gowhatsapp) | `c58fcbac9aa7210ce08cf12ef3442932730ec312` | GPL v3 |
| `PurplePlugins/libtelegram-tdlib.so` | [tdlib-purple](https://github.com/adrighem/tdlib-purple) 2.1.0 | `b277ac1941dbed946444454f67b89265541237b7` | GPL v2 |
| (statically inside `libtelegram-tdlib.so`) | [TDLib](https://github.com/tdlib/td) 1.8.65 | `a8f21f5230172634becc1739050ef23ecd6ea291` | Boost 1.0 |
| `PurplePlugins/libsignal-presage.so` | [purple-presage](https://github.com/hoehermann/purple-presage) | `c4c9b8d8e1a822f973520e8870aba1d2347b18c6` (nightly-20260810) | GPL v3 |
| `PurplePlugins/libteams.so`, `libteams-personal.so` | [purple-teams](https://github.com/EionRobb/purple-teams) | `62f6fff` | GPL v3 |
| `PurplePlugins/libircv3.so` | [purple2-ircv3](https://github.com/EionRobb/purple2-ircv3) | `0e73297` | GPL v2 |
| `Frameworks/libssl.3.dylib`, `libcrypto.3.dylib` | [OpenSSL 3](https://www.openssl.org), used by TDLib inside the Telegram plugin | Homebrew build | Apache 2.0 |
| `Frameworks/libwebp.7.dylib`, `libsharpyuv.0.dylib` | [libwebp](https://chromium.googlesource.com/webm/libwebp) | Homebrew build | BSD 3-Clause |
| `Frameworks/libpng16.16.dylib` | [libpng](http://www.libpng.org) | Homebrew build | libpng/zlib |
| `Frameworks/libotr.framework` and friends | [libotr](https://otr.cypherpunks.ca), [libgcrypt](https://gnupg.org), [libgpg-error](https://gnupg.org), [gettext](https://www.gnu.org/software/gettext/) | Homebrew builds | GPL v2 / LGPL v2.1 |

libpurple, glib and the other core dependencies are not shipped as
binaries; they are built from source by the scripts in `Dependencies/`
(which pin the exact versions, e.g. libpurple 2.14.14). The LGPL
components are dynamically linked, so they can be swapped out by
rebuilding the bundle.
