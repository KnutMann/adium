# Adium — Apple Silicon fork

**This is a fork of the original [Adium](https://adium.im)
([source](https://github.com/adium/adium)), rebuilt for Apple Silicon
(arm64) so it keeps running on current Macs — including all bundled
libraries.** The original is Intel-only and will stop working when
Apple retires Rosetta 2.

**Adium was created and developed by the Adium team.** All credit for
the application itself belongs to the original developers — see
[Copyright.txt](Copyright.txt). This fork is not affiliated with or
endorsed by them — it is maintained by a long-time Adium user who
simply wants to keep the app he has been using for many years alive.
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

Still supported services: **XMPP/Jabber, IRC, Gadu-Gadu, Bonjour
(local network), Novell GroupWise and SIMPLE**, plus OTR encryption,
tabbed chats, message styles, contact list themes and Xtras.

This is a work in progress; expect rough edges. See the commit history
for details on what has been touched.

## System requirements

* Apple Silicon Mac, macOS 11 or later
* Everything is native arm64, including all bundled dependencies
  (libpurple, glib, libotr, ...) — no Rosetta 2, no Homebrew required
* Xcode (for building — there are no binary releases at this time)

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

GNU GPL v2 — see [License.txt](License.txt). Original code copyright
the Adium team and contributors ([Copyright.txt](Copyright.txt)).
