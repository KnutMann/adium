# XMPP capabilities: what we have and what comes next

Inventory taken on 2026-08-19, checked against libpurple 2.14.14
(`Dependencies/source/libpurple/.../jabber/`), the fork patches
(`Dependencies/patches/pidgin-2.14.14/jabber/`) and the AdiumY tree, not from memory. This is the
inventory document M17 of the platform roadmap asks for.

## Already there, costs nothing

- **XEP-0198 Stream Management**: upstream in libpurple 2.14. Done.
- **XEP-0191 Blocking**: complete in the prpl, wired to the UI through adiumPurplePrivacy and
  ESBlockingPlugin. Needs a verification (M16) only, no code.
- **XEP-0184 receipts / XEP-0333 markers**: our own fork patches (receipt.c, chatmarker.c);
  receiving, automatic receipts and "displayed" on reading all work. What is missing is only the
  per message display.
- Also covered: 0030/0115, 0045, 0249, 0085, 0203, 0199, 0084/0153, 0163, 0237, 0047/0065/0096.

**AdiumY as a model**: no newer XEP series than the ones listed in M17; the AdiumY tree was
migrated to ARC and reformatted after its XEP commits, so the diffs are a design model and never
cherry-pickable. AdiumY's own XEP audit stands at "Proposed", so conformance is unverified there
too.

## Order of work

**Quick to take over (AdiumY as a model):**
1. **XEP-0280 Carbons** plus the mandatory **XEP-0334 Hints**: messages from the phone appear here
   too; the biggest everyday gain. Build it as a prpl patch following the pattern of receipt.c.
   Risks: duplicates against the local logs, and without `<private/>` on OTR messages, OTR fragments
   land on other devices. (AdiumY 186103ce, 3512b2b8, 69406099)
2. **XEP-0352 CSI**: less traffic and fewer wakeups while idle; small, wires into the existing idle
   detection; needs the explicit active policy from M17. (AdiumY a54fe609 plus 29901c55)
3. **XEP-0402 PEP bookmarks**: the MUC list and autojoin in step with Gajim, Dino and Conversations;
   manageable, and AdiumY has tests (407ebcf6). Do not build 0048 on its own, it has been deprecated
   since 2020.

**Manageable, with no model to follow:**
4. **XEP-0410 MUC Self-Ping**: notices room sessions that died quietly after a network change and
   rejoins; a small timer over the existing ping code, with care taken against rejoin loops.

**Valuable, but a project of its own:**
5. **XEP-0313 MAM**: only once the history and reconnect model is settled, plus XEP-0359 dedup, or
   it is a duplicate generator. 6. **XEP-0363 HTTP Upload**: the only file transfer that is reliable
   in 2026, but HTTPS PUT, URL safety and the UI make it large. 7. **XEP-0308 corrections**, bundled
   with the per message state model of the message view (the blocker is the missing id to DOM
   mapping, documented in adiumPurpleSignals.m); whoever builds that one data model unlocks 0308,
   the 0184 ticks and 0333 per message all at once.

**OMEMO: BUILT on 2026-09-15** (XEP-0384, namespace `eu.siacs.conversations.axolotl`, one to one
conversations; group rooms and XEP-0454 are still missing). The cryptographic layer is picomemo
(ISC, pinned to one commit), the XMPP side is our own code as it is for Carbons, CSI and Jingle:
`AIOMEMOStore` holds identity, sessions and trust, `AIOMEMOMessage` the wire form,
`adiumPurpleOMEMO.m` the PEP and stanza work, `AIOMEMOController` the bridge to the interface.
Checks live under `Testing/omemo/` and `Testing/xmpp/server.sh omemo-pep`. An earlier assessment,
for the record: (the note from 22.08 that the shtrom fork carried a port of the Pidgin lurch plugin
in `Lurch4Adium-0.0.4/*` is WRONG and was disproved on 2026-09-15: the branches contain not one line
of it, only a checked in libgcrypt 1.6.2. What stands is the verdict on lurch itself, frozen since
February 2022, and axc, which has no trust model at all. picomemo was chosen instead, C and ISC
licensed, providing the cryptographic layer while the XMPP side stays our work as it does for
Carbons, CSI and Jingle.)

**Tempting, but no:** 0393 styling (it reaches into the whole presentation, queue it behind
Carbons), 0444/0461 (experimental, and not presentable without the id mapping), Bind2/SASL2 (core
surgery for no visible gain), MIX (no deployment).

**The agreed roadmap (2026-08-19): Carbons plus Hints, then CSI, then 0402 bookmarks, in that order,
each as a prpl patch following the pattern of receipt.c and chatmarker.c and with an M16
verification before the next step. XEP-0191 is only tested and booked as present. MAM, HTTP Upload
and the per message state model stay projects of their own and are not started on the side.**

## Addendum: BeagleIM and Martin as a reference, video calls (research 2026-08-22)

**BeagleIM** (tigase/beagle-im, GPLv3, Swift) and its XMPP library **Martin** (AGPLv3!) are still
maintained in 2026 (BeagleIM 6.0.1 of 2026-06-13, Martin devel of 2026-06-11, both at one person's
pace; GitHub is now only a mirror of tigase.dev). Taking code over directly: none. It is Swift on a
Combine architecture, none of which fits prpl C or our Objective-C, and the GPLv3/AGPLv3 chain would
take the GPL2 option away from the work as a whole. **As a read only protocol reference alongside
AdiumY it is valuable** for the agreed roadmap: `MessageCarbonsModule.swift` (enable after bind, not
after an SM resume; the bare JID filter against forged carbons),
`ClientStateIndicationModule.swift` (the active/inactive policy), `PEPBookmarksModule.swift` (the
0402 node, publish-options). Keep writing the implementation against the XEP texts, do not copy.

**Video calls: BUILT** (September 2026), and on exactly the path described here. The starting
position was as stated: voice and video in libpurple 2.x is dead on macOS, farstream never ran here,
our build does not set USE_VV, and 2.14.14 knows nothing of DTLS-SRTP (XEP-0320), without which no
modern client (Conversations, Dino, Monal, BeagleIM) will negotiate. A separate Martin component
with a second connection would have been unclean (a second login, a second resource, AGPL in the
bundle).

What was built is an Adium plugin that speaks Jingle IQs over the existing
`jabber-receiving-xmlnode` and `jabber-sending-xmlnode` signals on the **same** libpurple connection
and gives only the media layer to a WebRTC.xcframework (stasel/WebRTC 153, fetched against a SHA-256
by `Dependencies/webrtc/fetch-webrtc.sh`, not checked in). Signalling: XEP-0166/0167 (including
rtp:info mute and unmute), 0176, 0320, 0338, 0339, 0293, 0294, plus 0353 (message initiation) and
0215 (STUN/TURN discovery including `expires`). The code lives in
`Plugins/Purple Service/AIJingle*`; the SDP to Jingle mapping is Foundation only and therefore
testable without Adium. BeagleIM and Martin were a reading reference throughout, with not one line
taken over.

Confirmed live against Conversations on Android: ringing, answering, sound and picture in both
directions, muting in both directions, hanging up. Four test series under `Testing/webrtc/` cover the
SDP mapping, the state machine, the whole stack with two real PeerConnections, the video view and
the window geometry. One blemish on BeagleIM itself: its WebRTC binary has stood at M101 since 2022.

What remains open at this point is only renegotiation during a call (content-add, that is switching
from voice to video mid call); neither Conversations nor BeagleIM can do that.

**Noted for later: calls on Telegram.** Of the four third party services, Telegram is the only one
where the code built here really carries over, because the division of labour is the same: TDLib
does signalling and all of the cryptography and no media at all, and from tgcalls v2 onwards the
media layer is ordinary DTLS-SRTP, evidenced by two independent clients (Ajaxy/telegram-tt with the
browser's own RTCPeerConnection, gotd/td with pion). ntgcalls builds against unmodified Google
libwebrtc m152, ours is M153.

In our tree it is switched off twice over: tdlib-purple is built with `-DNoVoip=TRUE`, and
`call.cpp:181-195` additionally throws away every call when the interface reports no audio
capability, which is always the case here (`adiumPurpleMedia.m` is not compiled at all, and `USE_VV`
and `USE_GSTREAMER` are undefined).

What could be reused are AIJingleVideoView, AIJingleCallWindowController, the camera follow mode,
AIJingleCallDiagnostics and half of the media side of AIJingleCallController, whose binding to the
protocol runs through a delegate that speaks STRINGS. What would have to be replaced are
AIJingleSessionMachine and AIJingleEngine.

FIRST STEP, hours rather than days: `getCallProtocol()` in `call.cpp:9-17` never sets
`library_versions_`, although the constructor of the bundled TDLib has that fifth field. That is why
the plugin only ever gets `callServerTypeTelegramReflector`. One attempt at putting `"13.0.0"` there
and logging whether `callServerTypeWebrtc` entries then arrive answers the only genuinely open
question. Realistically it would fail at the EncryptedConnection layer (msg_key plus AES-CTR) and at
the reflector fallback under strict NAT.
