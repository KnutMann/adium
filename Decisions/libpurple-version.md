# libpurple 2.14.14, not libpurple 3

**Decision.** The bundled libpurple is 2.14.14, built from the Pidgin release by
`Dependencies/phases/build_purple.sh` with the patches under
`Dependencies/patches/pidgin-2.14.14/`.

**Why.** Everything that makes this fork interesting is a libpurple 2 plug-in:
WhatsApp, Signal, Teams, Telegram, IRCv3 and now Matrix are all written against
the 2.x plug-in API, and none of them exists for 3. Moving to libpurple 3 means
either porting six third-party plug-ins or losing six protocols, and it buys
nothing a user would notice.

It is not a comfortable position. 2.14.x is barely maintained upstream, and a
break in OpenSSL or glib lands here and has to be patched locally, which is
exactly what `Dependencies/patches/pidgin-2.14.14/` is.

**What it costs.** Local patches that have to be re-applied at every bump, and a
dependency that will eventually stop receiving fixes. The XMPP extensions this
fork added, receipts, chat markers and carbons, are patches on top of 2.14.14
rather than upstream work.

**Reconsider when** the third-party plug-ins move to 3, which would be visible as
their repositories gaining a `purple3` build, or when 2.14.x stops building
against a supported OpenSSL. Worth a look once a year rather than once a release.

**Verified** 19 October 2026: `build_purple.sh` fetches pidgin-2.14.14.
