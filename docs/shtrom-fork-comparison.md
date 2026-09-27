# Comparison with shtrom/adium (the preserved 1.6/1.7 Mercurial line)

Checked on 2026-08-22 against our master. [shtrom/adium](https://github.com/shtrom/adium) is a real
GitHub fork (SHAs are comparable, last push December 2020) and preserves the **final Mercurial
state** up to 2016 that the GitHub mirror never received: `adium-1.6` is the 1.6 candidate that was
never released (267 commits against our line), `master` is the less stable 1.7hg/default (~30 more).
Our merge base with it is already the 1.5.9 changelog (2013), so the 1.5.10.x content exists on both
lines under different SHAs, which is why the raw numbers exaggerate badly.

## Already here (inherited through 1.5.10.x or built ourselves, no action)

SSLRead EOF handling in ssl-cdsa (#16356), reachability across sleep and wake, HiDPI detection on a
second monitor (#16552), loading account nibs from their own bundle (#16591, solved here through
ai_loadNibNamed), libotr 4.0.0 including SMP, the MySpace removal, the RBSplitView removal,
libpurple versions (ours: 2.14.14).

## Candidates worth harvesting (missing here, checked)

Commits refer to shtrom/adium. Ordered by value:

1. **Cocoa rebuild of the libpurple request UI** — `b558e23d8` (plus `99e69e1d8`, `061335c4e`):
   AMPurpleRequestFieldsController without a WebView, with its own xib per field type (Boolean,
   Choice, Integer, List, MultiList, MultilineString, SecureString, String). Here that very class is
   the **last WebView user** (the remaining deprecation in modernisation.md). Take over the concept
   and the field logic; whether xibs from 2013 or our AISettingsFormView provides the presentation
   is a decision for the time of the rebuild.
2. **Encryption details window** — `918aa4980` (plus the `175`/`edceaa599` area): a window in front
   of the certificate view showing issuer, TLS version, cipher, MAC and key exchange; it drags about
   350 lines of SecureTransport introspection into ssl-cdsa behind it. Caveat: we want to lift
   ssl-cdsa onto OpenSSL in the medium term, so the UI side stays but the introspection would have
   to be written anew.
3. **windowWillClose: super first** — `5f1abc62b` (#16579): AIAuthorizationRequestsWindowController
   and AISpecialPasswordPromptController call super at the end; the fix moves it to the beginning,
   because super is what sets the controller's release in motion. **The bug is still here** (both
   files are still MRR).
4. **Paste privacy** — `a80f5d288`: when HTML is pasted, do not fetch the embedded images
   (a WebResourceLoadDelegate that returns nil). Prevents unwanted network access on paste. Missing
   here; AIMessageEntryTextView.
5. **Midnight rotation of transcripts** — `24ff5d93c` (#6786) plus the guard `628253902`: chats that
   run for days are split at midnight. Our AILoggerPlugin does not rotate at all.
6. **XtrasInstaller fixes** — `771b5a417` (#16795, sharedApplication delegate instead of NSApp; we
   still have the old form, Source/XtrasInstaller.m:410) and `fa6c033b5` (#16288, installing from
   the website).
7. **Transcript viewer: selection after deleting** — `f8f0d9f1c` (#11420). Our state is unchecked.
8. **Link scanner** — `026e9bdc6` (#16217/#16413, move the scan position on after a find,
   MIN_LINK_LENGTH 4). Our AHHyperlinkScanner is structurally different; check first whether the
   class of bug exists at all.
9. **Emoticon menu bundle** — a separator per pack `d9a2f8805` (#16452), an option to switch it off
   `149909ebb` (#16407), the arrow cursor `727c3b355` (#16432), alignment `6737b11e1` (#16434),
   removing the toolbar item `4170f0088` (#16396). Fits the open "emoticon keyboard" point of the
   UI inventory.
10. **Odds and ends**: edit menu entries `72c4c165b` (#16416), DuckDuckGo search in the context menu
    `2666f79b4`, a combined link/browser toolbar item `baf2dd8a4` (#15404), OTR to the most recently
    active instance `f6076f069`, the OTR logging question without stealing focus `0c279dec0`, an
    isOnline fast path `8626e38ff` (1.7), SenTestingKit to XCTest `50f1bb7c2` (1.7, should the tests
    ever be revived).

## Topic branches of the fork (worth an inventory of their own)

`Lurch4Adium-0.0.4/*` (**the name misleads, verified on 2026-09-15:** the two branches `base` and
`patched` contain ZERO files with lurch, omemo, axolotl or signal-protocol in their names. The only
difference in content is a checked in libgcrypt 1.6.2, which the OTR migration has long since dealt
with. It is the preparation for a port that never happened, and worthless as a starting point for
OMEMO), `HistoricMUCMessages`, `IRCServerConsole`, `AddConfigureRoomForMUCs`, `EmoticonsMenu`,
`AdiumApplescriptRunnerUsingXPC` (our AppKit on the main thread problem!), `AutoLayout`,
`PreferencesRedux`, `Sandboxing`, `eventloop_libdispatch`, `voice-video`, `fix-autoscroll`,
`TorProxyType`, `AILoggerWithBlocks`, `JSXtras`. Dead: `GTalkOAuth2Support`/`GoogleOAuth2`,
`MSN-XMPP`, `libotr4.0.0` (merged), `10.6+`.

The clone lives in the session scratchpad; the lasting source is GitHub.
