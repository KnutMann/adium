# Adium (Apple Silicon fork)

**This is a fork of the original [Adium](https://adium.im)
([source](https://github.com/adium/adium)), rebuilt for Apple Silicon
(arm64), including all bundled libraries, so it keeps running on
current Macs.** The original is Intel-only and will stop working when
Apple retires Rosetta 2.

**Adium was created and developed by the Adium team.** All credit for
the application itself belongs to the original developers; see
[Copyright.txt](Copyright.txt). This fork is not affiliated with or
endorsed by them. It is maintained by a long-time Adium user who
simply wants to keep a beloved app alive after many years of use.
The upstream project has been inactive since 2021, and its last
official release is an Intel-only binary whose days are numbered with
Rosetta 2 being phased out.

## Original project

* Website: <https://adium.im>
* Source: <https://github.com/adium/adium>
* Last official release (Intel, runs on Apple Silicon via Rosetta 2):
  [Adium 1.5.10.4](https://adiumx.cachefly.net/Adium_1.5.10.4.dmg)

## What this fork changes

* Native arm64 build; the app bundle is self-contained (no Homebrew or
  other third-party runtime dependencies)
* Bundled libpurple upgraded from 2.12.0 (2017) to 2.14.14 (2025)
* Notifications via the macOS Notification Center (replaces Growl)
* Many fixes for current AppKit/WebKit behavior (message styles,
  contact list, tabs, tooltips)
* Removed services whose networks no longer exist: AIM, ICQ, MSN,
  Yahoo, Google Talk, MobileMe, LiveJournal, Sametime and Twitter
* Removed Sparkle auto-update (the update feed is long dead); update
  by pulling and rebuilding

**New services: Telegram** (via the bundled
[tdlib-purple](https://github.com/BenWiederhake/tdlib-purple) plugin)
**and WhatsApp** (via
[purple-gowhatsapp](https://github.com/hoehermann/purple-gowhatsapp)).

Still supported classic services: **XMPP/Jabber, IRC, Gadu-Gadu,
Bonjour (local network), Novell GroupWise and SIMPLE**, plus OTR
encryption, tabbed chats, message styles, contact list themes and
Xtras.

This is a work in progress; expect rough edges. See the commit history
for details on what has been touched.

## System requirements

* Apple Silicon Mac, macOS 11 or later
* Everything is native arm64, including all bundled dependencies
  (libpurple, glib, libotr, ...): no Rosetta 2, no Homebrew required
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

All required libraries (libpurple, glib, libotr, libgcrypt, ...) are
vendored as prebuilt arm64 frameworks in the repository. Rebuilding
them from source is only necessary when upgrading a dependency; see
`Dependencies/build.sh` (this does require a Homebrew toolchain).

## License

GNU GPL v2 or later, see [License.txt](License.txt). Original code
copyright the Adium team and contributors
([Copyright.txt](Copyright.txt)).

### Bundled third-party binaries and their sources

This repository ships some components as prebuilt arm64 binaries. The
corresponding sources are publicly available at the exact revisions
listed here:

| Binary | Project | Revision | License |
| --- | --- | --- | --- |
| `PurplePlugins/libwhatsmeow.so` | [purple-gowhatsapp](https://github.com/hoehermann/purple-gowhatsapp) | `5a436315caefd3b89c2b631a7b8028742e58f047` | GPL v3 |
| `PurplePlugins/libtelegram-tdlib.so` | [tdlib-purple](https://github.com/BenWiederhake/tdlib-purple) | `43e6cc2f14ccd08171b1515f6216f4bbf84eed80` | GPL v2 |
| (statically inside `libtelegram-tdlib.so`) | [TDLib](https://github.com/tdlib/td) | `8d08b34e22a08e58db8341839c4e18ee06c516c5` | Boost 1.0 |
| `Frameworks/libssl.3.dylib`, `libcrypto.3.dylib` | [OpenSSL 3](https://www.openssl.org) | Homebrew build | Apache 2.0 |
| `Frameworks/libwebp.7.dylib`, `libsharpyuv.0.dylib` | [libwebp](https://chromium.googlesource.com/webm/libwebp) | Homebrew build | BSD 3-Clause |
| `Frameworks/libpng16.16.dylib` | [libpng](http://www.libpng.org) | Homebrew build | libpng/zlib |
| `Frameworks/libotr.framework` and friends | [libotr](https://otr.cypherpunks.ca), [libgcrypt](https://gnupg.org), [libgpg-error](https://gnupg.org), [gettext](https://www.gnu.org/software/gettext/) | Homebrew builds | GPL v2 / LGPL v2.1 |

libpurple, glib and the other core dependencies are not shipped as
binaries; they are built from source by the scripts in
`Dependencies/` (which pin the exact versions, e.g. libpurple
2.14.14). The LGPL components are dynamically linked, so they can be
swapped out by rebuilding the bundle.
