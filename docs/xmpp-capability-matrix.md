# XMPP capabilities: what we have and what comes next

First taken on 2026-08-19 against libpurple 2.14.14, the fork patches under
`Dependencies/patches/pidgin-2.14.14/jabber/` and the AdiumY tree. **Rewritten on 2026-10-01,
because almost everything the 2026-08-19 order of work called "next" had been built in the
meantime and the document still called it open.** Every line below was checked in the code on
that date, not recalled: for each extension, the namespace or the obvious identifier was searched
for under `Plugins/Purple Service`, `Source` and `Dependencies/patches`, and the file that
carries it is named.

A document like this goes stale quietly, so the rule for the next reader is: distrust it and
grep. A one line check for any of them, for example XEP-0280:

    grep -rl "urn:xmpp:carbons" --include='*.m' --include='*.patch' \
      "Plugins/Purple Service" Source Dependencies/patches

## Built

- **0198 stream management, including resumption.** Upstream in libpurple 2.14 for the counting
  half; the resumption half is ours, in `stream_management.c.patch`. Adium used to tear a
  connection down before libpurple ever saw the socket fail, which is the one thing that makes
  resumption impossible, so `ESAccountNetworkConnectivityPlugin.m` now gives a vanished network
  ten seconds before it acts, and asks for an acknowledgement when the network settles, because
  a dead socket is only discovered by writing to it. Checks in `Testing/xmpp/smsession-test.sh`.
- **0280 carbons** plus **0334 hints**: `adiumPurpleCarbons.m`.
- **0352 CSI**: `adiumPurpleCSI.m`, `<inactive/>` when Adium stops being the active application.
- **0402 PEP bookmarks**: `adiumPurpleBookmarks.m`.
- **0313 MAM**: `AMPurpleJabberMAM.m`.
- **0363 HTTP upload**: `AMPurpleJabberHTTPFileUpload.m`.
- **0308 last message correction**: `ESPurpleJabberAccount.m` and the message view's id mapping.
- **0444 reactions**, one to one and in rooms: `adiumPurpleSignals.m` and the chip Xtra.
- **0393 message styling**: `Source/AIMessageStyling.m`, as a display filter for every protocol.
- **0384 OMEMO**, one to one, namespace `eu.siacs.conversations.axolotl`, over picomemo (ISC,
  pinned to one commit): `AIOMEMOStore`, `AIOMEMOMessage`, `adiumPurpleOMEMO.m`,
  `AIOMEMOController`. **0454 media** is there too, `AIOMEMOMedia.m`. Checks under
  `Testing/omemo/`.
- **0166 Jingle** with native WebRTC, our own code rather than farstream: sixteen files from
  `AIJingleEngine.m` to `AIJingleCallWindowController.m`.
- **0191 blocking**, **0184 receipts** and **0333 markers** including the per message display,
  which was the piece the 2026-08-19 inventory listed as missing.
- Also covered: 0030/0115, 0045, 0249, 0085, 0203, 0199, 0084/0153, 0163, 0237, 0047/0065/0096,
  0077 registration, 0359 for deduplication.

**AdiumY as a model**: it has no newer XEP series than the ones above, and its tree was migrated
to ARC and reformatted after its XEP commits, so its diffs were ever only a design model and
never cherry-pickable.

## Not built

- **0410 MUC self-ping** and **MUC status code 333**. The two halves of one problem: after a
  resumption a client can still believe it is in a room it was silently removed from, and a
  presence carrying code 333 says the room removed an occupant over a technical fault, which
  today reads to Adium like an ordinary departure. This is the last open piece of the
  resumption work, where it is called step 9.
- **OMEMO in rooms**, plus reading **0380** on receipt, key rotation by time
  (`rotateSignedPreKey` exists and nobody calls it) and **omemo:2**.
  `AIOMEMOController.m` refuses a group chat outright today.

**Still no, and the reasons still hold:** Bind2 and SASL2, core surgery for no visible gain, and
MIX, which nothing deploys. Two that stood here as "no" in August were built anyway, and the
reasons they were refused are worth keeping because both turned out to be the real cost: 0393
styling does reach into the whole presentation, and 0444 reactions were not presentable until
the id to DOM mapping existed. Neither was cheap; both were done once that mapping was.

**The 2026-08-19 roadmap, for the record, since it has been walked: Carbons plus Hints, then CSI,
then 0402 bookmarks, each as its own step with a verification before the next. It held, and the
three projects it called too large to start on the side, MAM, HTTP upload and the per message
state model, were all built afterwards anyway.**

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
