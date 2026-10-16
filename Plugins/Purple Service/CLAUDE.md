# Plugins/Purple Service, the bridge to libpurple

This folder builds the AdiumLibpurple framework (target AdiumLibpurple,
Info.plist in Plists/AdiumLibpurple). Everything that speaks a protocol goes
through here: libpurple's own protocols, the prebuilt third-party plug-ins in
PurplePlugins/, and the fork's XMPP work written against the XEPs.

## The bridge

SLPurpleCocoaAdapter owns libpurple's core: it brings the core up when the
plug-in loads (it used to wait for the first connection), runs libpurple's
event loop on the main run loop (adiumPurpleEventloop.m) and dispatches into
it. The adiumPurple*.m files are libpurple's ui-ops, one file per subsystem,
mapping C callbacks onto the controllers: accounts, blist (the buddy list),
connection, conversation, core, dns, ft (file transfer), notify, privacy,
request (libpurple's dialogs, made native), roomlist, signals, and
certificate trust, which verifies through SecTrust and asks the user. The
fork added files beside them for what libpurple's jabber plug-in does not do:
bookmarks (XEP-0402), carbons (XEP-0280), CSI (XEP-0352), MUC self-ping
(XEP-0410), fallback indication (XEP-0428), Jingle, OMEMO and WhatsApp.
libpurple_extensions/ssl-cdsa.c is the SSL plug-in on Apple's Security
framework that every connection uses.

CBPurpleAccount is the account base: an AIAccount whose connection is a
PurpleAccount. Its ForSubclasses category is what a protocol overrides.

## Services

A service is registered one of two ways, both in CBPurpleServicePlugin's
installPlugin. First by class: Jabber, Gadu-Gadu, WhatsApp, Novell and SIMPLE, each a PurpleService or AIService
subclass with a CBPurpleAccount subclass beside it (ESJabberService with
ESPurpleJabberAccount, AIWhatsAppService with AIPurpleWhatsAppAccount, and so
on). Then by descriptor: AIPurpleGenericService reads
AIPurpleServiceDescriptors.plist and registers one service for every protocol
libpurple loaded that the class list does not already answer for, each driven
by AIPurpleGenericAccount with no code of its own. That covers Bonjour,
Telegram, IRCv3, Signal, Teams (work and personal) and Matrix. The ESIRCService class remains in the folder but is not registered: IRC is served by the ircv3 plug-in through its descriptor, and the comment at that spot says how to bring the class back.

A descriptor row carries ServiceID, ServiceClass, ServiceCodeUniqueID, the
names and descriptions, IconBaseName and ServiceImportance, and optionally
UserNameLabel, CaseSensitive, AllowedLength, AllowedCharacters,
ForbiddenCharacters, AccountNameFromUID, AccountNameIncludesHost,
UserNamesAreEmailAddresses, UserNamesArePhoneNumbers, NetworkReachability,
EchoesOutgoingMessages and Experimental. Experimental keeps the service out
of every menu until the user runs

    defaults write com.adiumX.adiumX AIShowExperimentalServices -bool YES

and hides the offer, not accounts already made (see -isHidden in
AIPurpleGenericService). So a protocol that arrives as a libpurple plug-in is
a .so in PurplePlugins/ plus a row, and nothing else, unless it needs
behaviour of its own, as WhatsApp did.

## XMPP

ESPurpleJabberAccount is where the fork's XMPP work hangs, and
ESPurpleJabberAccountPlan is its settings form. The AMPurpleJabber* classes
ride on libpurple's jabber plug-in: ad hoc commands, external service
discovery (XEP-0215, where STUN and TURN come from), HTTP upload (XEP-0363,
used for pictures and voice notes), MAM (XEP-0313), service discovery
browsing and data forms among them.

OMEMO (XEP-0384): AIOMEMOController per account; AIOMEMOStore for identity,
sessions and skipped keys on disk; AIOMEMOMessage and AIOMEMOStanza for the
wire form; AIOMEMOMedia for encrypted files (XEP-0454); and
adiumPurpleOMEMO.m where libpurple hands messages over. The cryptography is
picomemo, which Dependencies/fetch.sh builds. Testing/omemo checks each piece
against published vectors.

Calls: AIJingleEngine does SDP and the Jingle transport; AIJingleSessionMachine
is the session state; AIJingleCallManager holds the calls and the ringing
(XEP-0353); AIJingleCallController runs one call on WebRTC; AIJingleCallUI,
AIJingleCallWindowController and AIJingleVideoView are the window;
AIJingleCallDiagnostics is "Check Call Readiness"; adiumPurpleJingle.m is the
ringing messages. Testing/webrtc has the harnesses.

Resources/ here is the plug-in's own strings, one .lproj per language.
