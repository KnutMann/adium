# A network that is gone is gone from the code too

**Decision.** The application carries no service for a network that no longer
exists, and "carries" means code, not a registration line. A libpurple service
reaches the account list in one of two ways: through a class that calls
`+registerService` in `CBPurpleServicePlugin.m` (Gadu-Gadu, SIMPLE, GroupWise,
XMPP, WhatsApp), or through a row in `AIPurpleServiceDescriptors.plist` for a
protocol plug-in the bridge has loaded (Bonjour, IRC, Telegram, Signal, Teams,
Teams Personal, Matrix). The bundled libpurple links six protocols statically:
bonjour, gg, irc, jabber, novell and simple, and nothing else.

**Why.** The upstream project had done it once already: MSN, Yahoo, Facebook
Chat and MySpaceIM left in March 2017, when those networks closed their doors
to third-party clients. This fork did the rest in August 2026:

* AIM, ICQ and .Mac/MobileMe (`7dc2c49fc`, 7 August). AOL shut AIM in December
  2017 and ICQ closed in June 2024; and Pidgin had dropped the oscar protocol in
  2.14.3, so the code would not have compiled against the libpurple this fork
  was about to move to.
* Google Talk and LiveJournal (`5aa9583f6`, the same day). Google ended XMPP
  client sign-in in 2022 and LJ Talk is gone. Sametime went with them: its
  library is unmaintained and was never built for arm64.
* Twitter and Laconica (`cf97a3d21`). The API that third-party clients used was
  shut in 2023.
* Zephyr (`0282590f3`, 11 August). Never registered in the first place: its line
  had been commented out for so long that nothing in its eleven files said so,
  while the code compiled into AdiumLibpurple and shipped in every build, and
  the host manager it needed was an i386/ppc binary.
* The built-in IRC class is compiled but not registered (`232e4746a`), because
  prpl-eionrobb-ircv3 speaks the same protocol and knows the capabilities the
  old one never heard of; two services for one protocol only made both harder
  to tell apart in the account list.

A service for a dead network is worse than none: it offers an account that
cannot connect, and its code is a tax on every migration, the ARC conversion
and the libpurple upgrade among them. The commented-out registration line is
the trap, because the code is then compiled, shipped and invisible. That is why
the comment above the list in `CBPurpleServicePlugin.m` says to drop the code
instead.

**What it costs.** An account of a retired service in an existing installation
is not shown and not deleted. `AdiumAccounts` keeps every entry whose service it
cannot find in `unloadableAccounts` and writes it back unchanged at every save,
so an ICQ account from 2010 sits in `Accounts.plist` indefinitely, with its
keychain entry beside it. Nothing cleans that up, and nothing should without
asking. The iChat importer finds no AIM service and imports nothing for it. And
the help book has not caught up: `AdiumHelp/pgs/` still has pages for AIM, ICQ
and MobileMe accounts.

**Verified** 19 October 2026: `CBPurpleServicePlugin.m` registers five classes
and the exclusion list it hands `AIPurpleGenericService` names six protocols;
the descriptor holds seven rows; `PROTOCOLS` in
`Dependencies/phases/build_purple.sh` is `bonjour,gg,irc,jabber,novell,simple`;
`git grep -il oscar` outside `Dependencies/`, `docs/` and the language folders
finds the project file, the help book and libpurple's own headers, and no
source file.
