# Adium (revival fork)

**This is a fork of the original [Adium](https://adium.im)
([source](https://github.com/adium/adium)) that revives and modernizes
it for current macOS.** It began as an Apple Silicon (arm64) port —
the original is an Intel-only binary from 2021 — and has grown into a
broader overhaul: a rebuilt, System Settings-style preferences window,
a WKWebView message view, Notification Center in place of Growl,
password storage in the Keychain, Telegram and WhatsApp alongside the
classic services, and a long list of fixes for how modern AppKit and
WebKit behave.

**Adium was created and developed by the Adium team.** All credit for
the application itself belongs to the original developers; see
[Copyright.txt](Copyright.txt). This fork is not affiliated with or
endorsed by them. It is maintained by a long-time Adium user who simply
wants to keep a beloved app alive after many years of use. The upstream
project has been inactive since 2021.

Current version: **1.6.0**.

## Original project

* Website: <https://adium.im>
* Source: <https://github.com/adium/adium>
* Last official release (Intel; on Apple Silicon it runs only through
  Rosetta 2, which Apple is phasing out):
  [Adium 1.5.10.4](https://adiumx.cachefly.net/Adium_1.5.10.4.dmg)

## What this fork changes

### Platform

* Native arm64 build; the app bundle is self-contained, with no
  Homebrew or other third-party runtime dependency
* All bundled libraries are native arm64, built from pinned sources
* Bundled libpurple upgraded from 2.12.0 (2017) to 2.14.14, on a
  current glib
* Passwords stored through the Keychain (SecItem) API
* Removed the dead Sparkle auto-update feed; update by pulling and
  rebuilding

### User interface

* A rebuilt preferences window in the style of System Settings: a
  source-list sidebar, cards instead of boxed groups, and a reusable
  settings form every pane is now laid out on, sizing itself with Auto
  Layout
* The whole app target is XIB-based; the last of the old nibs are gone
* The chat message view renders with WKWebView
* Modern window chrome — full-size content, tab-bar vibrancy, the
  current tab style — and a sweep of fixes for focus rings, scrolling,
  contact-list drawing, tabs and tooltips on recent macOS
* Notifications go through the macOS Notification Center, including the
  Dock badge and menu-bar unread indicators, replacing Growl
* The menu-bar status item, the contact list's borderless window and
  the now-playing "music status" (on Music.app, and Spotify) revived
  and brought up to date

### Messaging and services

* **New: Telegram** (via the bundled
  [tdlib-purple](https://github.com/BenWiederhake/tdlib-purple) plugin)
  **and WhatsApp** (via
  [purple-gowhatsapp](https://github.com/hoehermann/purple-gowhatsapp)),
  with inline images and voice notes, reactions, typing, read markers,
  group chats, profile pictures and address-book names
* XMPP modernized: read markers, delivery receipts, chat markers and
  message carbons
* OTR migrated to the libotr 4.x API
* An IRC fix so anything after login is actually sent — an upstream
  libpurple rate limiter never drained its queue under Adium's event
  loop
* Removed services whose networks no longer exist: AIM, ICQ, MSN,
  Yahoo, Google Talk, MobileMe, LiveJournal, Sametime, Twitter, Zephyr
  and Meanwhile

### Localization

* String extraction, unrun for years, caught up: hundreds of strings
  the app already showed but had never been extracted are now
  translatable, filled in across the 26 shipped languages
* Growl and other dead-feature wording renamed so it no longer misleads

Still supported classic services: **XMPP/Jabber, IRC, Gadu-Gadu,
Bonjour (local network), Novell GroupWise and SIMPLE**, plus OTR
encryption, tabbed chats, message styles, contact list themes and
Xtras.

This is a work in progress; expect rough edges. See the commit history
for details on what has been touched.

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

All required libraries (libpurple, glib, libotr, libgcrypt, ...) are
vendored as prebuilt arm64 frameworks in the repository. Rebuilding
them from source is only necessary when upgrading a dependency or
patching one (as the IRC fix does); see `Dependencies/build.sh` (this
does require a Homebrew toolchain).

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
binaries; they are built from source by the scripts in `Dependencies/`
(which pin the exact versions, e.g. libpurple 2.14.14). The LGPL
components are dynamically linked, so they can be swapped out by
rebuilding the bundle.
