# What is left to modernise

Measured from a clean build against the macOS 26.5 SDK, not guessed. The point of the list is to
separate what merely warns from what will one day stop the application from building or running.

Rerun the census with:

    rm -rf build/Adium.build build/AIUtilities.build
    xcodebuild -project Adium.xcodeproj -target Adium -configuration Debug build 2>&1 > /tmp/b.log
    grep -c "warning:" /tmp/b.log
    grep -oE "'[A-Za-z_][A-Za-z0-9_:]*' is deprecated" /tmp/b.log | sort | uniq -c | sort -rn

Both build directories, or the count silently leaves out whichever framework was not recompiled.
That is how a census of 418 was published when the real figure was 441.

## Done

- **Warning noise.** 6033 warnings, of which 5248 were vendored frameworks quoting their own
  headers. That is libpurple, glib and libotr written the way they were written, not something this
  project can change without patching them on every update, so it is off for the build and our own
  four in AutoHyperlinks were fixed properly. What is left is ours to look at.
- **Deployment target.** AIUtilities.xcodeproj said 10.11 while everything else said 11.0. Xcode
  was already warning; eventually it refuses.
- **Empty prototypes.** 39 C functions declared `()` rather than `(void)`. Harmless today, an error
  in C23.
- **Duplicate declarations.** `CBPurpleAccount.h` declared two methods twice, which made every
  `@selector` on either of them ambiguous, and `AIObjectAdditions.h` declared one twice.
- **Two informal protocols written down**, so the compiler stops guessing `id` for a method that
  answers yes or no.

## The one that could have broken the application

**WebKit 1**: done, and the item this list was ordered around. `WebView`, `WebFrame`,
`DOMHTMLElement`, `DOMRange` and neighbours, which Apple removed from iOS years ago and keeps on
the Mac out of politeness. The chat window already ran on `WKWebView`; three users were left, and
all three are gone:

- The live style preview in `ESWebKitMessageViewPreferences.m`: `AIWebKitPreviewMessageViewController`
  subclasses `AIWebKitMessageViewWKController` now (144698659).
- `AIWebKitMessageViewController`, which turned out not to be dormant after all, since the preview
  held it up; it went with `AIWebKitDelegate` and `ESWebView` once the preview moved (144698659).
- `AMPurpleRequestFieldsController`: the protocol form is built on `AISettingsFormView`, one row
  per field, following the shape of the never released 1.6 (shtrom/adium b558e23d8) without its
  per-type xibs (77b729b3d).

Checked 2026-10-11: no source file uses a WebKit 1 class any more. What still names one is
comments, and `AIInterfaceController.m` asking `NSClassFromString(@"WebHTMLView")` while it
decides how to paste, a lookup by name that needs no link. `WebKit.framework` stays linked for
`WKWebView`.

## The rest, by how much it matters

**Carbon file system**: done, all 25. What went: eight uses of `TickCount`, replaced by a
monotonic clock counting the same sixtieths of a second so that every interval and comparison
written against it reads as it did; five of `LSGetApplicationForURL`, which asked in a roundabout
way which application opens a web address and is now asked directly; and both alias resolutions,
where four Carbon calls in a chain became one `NSURL` message.

The last three were in `libezv`, and left with it when Bonjour was removed. The count is zero.

**Sheets with a modal delegate**: done. All 21 begins and 10 ends, plus the shared `-closeWindow:`
that nearly every sheet controller inherits, now use the completion-handler form and `-[NSWindow
endSheet:]`.

**Nib loading**: done, all 25. Both calls hand back every top level object holding one reference
that belongs to nobody, and the callers are split on what they do with it: nine take it over and
release it in `-dealloc`, the rest let it stand. `-[NSBundle ai_loadNibNamed:owner:]` reproduces
that exactly rather than deciding for them, which is a separate job and a riskier one. See
`AIContactListUserPictureMenuController` for why: it throws itself into the autorelease pool the
moment the menu is built, so the leak is the only thing holding the menu up.

**Menu batching**: done. 21 calls to `setMenuChangedMessagesEnabled:`, which the SDK header says
"no longer do anything useful" as of 10.6, and 10 allocations through a menu zone that has been the
default zone since 10.2.

**Accessibility**: done, all 15. `accessibilitySetOverrideValue:forAttribute:` maps one to one onto
`setAccessibilityLabel:`, `setAccessibilityTitle:` and `setAccessibilityRoleDescription:`, and
`NSCell` still adopts the protocol, so the receivers did not have to move.

**Text insertion**: done, all 12 calls and both overrides. `-insertText:` stopped being what the text
input system calls in 10.11; the overrides in `AISendingTextView` and `AIMessageEntryTextView` now
sit on `-insertText:replacementRange:` instead, which also means text put in from elsewhere passes
through them rather than around them.

**Dates**: done, all 19. The five fixed formats were checked against the old ones over 848,000
comparisons across five time zones, including the half hour and quarter hour ones, before a
character of the transcript file name was allowed to change. Nine calls turned out to be wrapping a
date in a calendar nothing then asked about, and were deleted. Two bugs fell out: `%d` in a message
alias had never produced a date, and the message style preview read its own fixed dates by guessing
at them in natural language.

**Secure Transport**, now measured precisely: 31 warnings, all in
`Plugins/Purple Service/libpurple_extensions/ssl-cdsa.c`, which is the SSL plugin the build
actually uses (`HAVE_CDSA` is defined; the OpenSSL variant only compiles as fallback).

Network.framework was examined for this and ruled out, deliberately (19.08.2026). The plugin does
not open connections; it wraps a socket libpurple hands it, already tunnelled through the user's
per-account proxy (`SSLSetConnection(ctx, gsc->fd)` on a descriptor purple_proxy produced -
HTTP, SOCKS4 or SOCKS5, configured in Adium's own proxy pane and pushed into libpurple by
CBPurpleAccount). NWConnection cannot adopt an existing descriptor: it would establish the
connection itself, silently bypassing every per-account proxy, and it speaks no SOCKS4 at all,
which Adium's UI offers. That is the "proxy behavior differs; regression risk" in one sentence,
and for anyone routing an account through Tor it is not a nuance but the feature.

The road off the deprecated API that keeps proxy semantics byte-identical is the OpenSSL backend
this tree already compiles as fallback: it wraps the same descriptor the same way. What it lacks
is the trust-decision hook (`register_certificate_ui_cb` is cdsa-specific), which would need the
same IPC added to ssl-openssl.c, handing the chain over as SecCertificateRef
(SecCertificateCreateWithData is current API) so the certificate panel and the M02b routing keep
working unchanged. Until someone does that with live connection testing per protocol, the
deprecated-but-functional Secure Transport stays.

The unreleased 1.6 line carries a connection-security details window on top of this file
(shtrom/adium 918aa4980: issuer, TLS version, cipher, MAC and key exchange shown before the
certificate panel). The window is worth having; its ~350 lines of Secure Transport introspection
are an investment into the API this section is about leaving, so if it comes, it comes together
with the backend decision, not before it.

Where Network.framework IS the right tool is the reachability monitor, and that is already
written down as roadmap item M07 with the correct caveats (NWPathMonitor for the global path;
it is not a host-reachability oracle and has nothing to do with proxies).

**Address Book**: done. The integration runs on Contacts and nothing links AddressBook any more
(7e40b2674, roadmap item M01).

**Atomics**: done. All 15 OSAtomic sites in the log indexing moved to `<stdatomic.h>`, with the
five variables retyped `_Atomic` so every plain read keeps full-barrier meaning, and the two
always-succeeding compare-and-swaps rewritten as the plain stores they were.

**~30 further deprecated calls** spread thin: the certificate-trust panel's old Security API, the
old-style status item view, a strftime date formatter in the message styles, and single renames in
the Purple service UI. The census command above lists them all.

**Help pages for services that are gone.** `AdiumHelp/pgs` still explains how to set up AIM, ICQ,
MobileMe, Twitter and Sametime. (Its Bonjour page is current again: Bonjour came back on
2026-09-21, efc24cd2b, though the page has not been checked against the new implementation.)
Nothing links these to the build, so they are stale text shipped inside the application rather
than anything that can break, and fixing one of them without the rest would only make the set
less coherent. Worth one pass over the whole directory some day.

## Not warnings, and still worth doing

**Notarisation.** `Adium.entitlements` was attached to nothing for five years.
`CODE_SIGN_ENTITLEMENTS` was taken out of the project in December 2020 over a signing problem with
the frameworks the dependency script builds, and nobody put it back, so the built application
carried only the automatic debug entitlement. It is attached again, in
`Frameworks/AIUtilities/xcconfigs/Adium.xcconfig`. What is still off is the hardened runtime
itself, `ENABLE_HARDENED_RUNTIME = NO`, and that is the half that has to be tried rather than
reasoned about: with it on, `com.apple.security.cs.disable-library-validation` is what decides
whether the six Purple plug-ins still load, and the only way to know is to start the application.

The usage descriptions this used to list as missing are there: `Resources/Info.plist` carries
`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSContactsUsageDescription`,
`NSAppleEventsUsageDescription`, and for Bonjour `NSLocalNetworkUsageDescription` together with
`NSBonjourServices`. They arrived with the calls and with Bonjour.

**The XtrasCreator**: done. The 2005 tool was retired and a new one took its name and place
under `Other/XtrasCreator` (c0da452eb, roadmap item M09), built around a single
`AXSXtraDocument`; the README lists the Xtra kinds it authors. What is left is the Finder UI
check the roadmap names.

**Reproducible plugin builds.** The Telegram plugin was a binary in `PurplePlugins/` whose build
recipe had been lost, which cost an account when it was rebuilt from what the tree actually held.
That one is fixed and guarded. WhatsApp and Signal have not been checked the same way.

**libpurple 2.14.14.** Barely maintained upstream. A break in OpenSSL or glib lands here and has to
be patched locally.

**The shelf from the unreleased 1.6/1.7 line.** Surveyed in `shtrom-fork-comparison.md`, with
commit hashes there; what has not been taken yet, in rough order of worth:

- ~~Paste privacy~~ — turned out to be present already: the deprecation sweep (2506a5eff) had
  ported it in a better form (selector-only WebResourceLoadDelegate, no WebKit import); the
  survey's "missing" was a false negative from grepping the wrong symbols.
- ~~Midnight transcript rotation (#6786)~~ — done, with the early-fire guard (66940ca18).
- ~~Transcript viewer selection after deleting (#11420)~~ — done.
- ~~Link scanner double-scan (#16217)~~ — verified absent: the newer AutoHyperlinks here already
  carries both the minimum length and the scan-location advance.
- ~~OTR to the most recently active resource~~ — done (OTRL_INSTAG_RECENT at all four sites).
- The emoticon menu package (per-pack separators, a disable switch, cursor and alignment fixes)
  — belongs to the open emoticon-UI item from the UI survey.
- Small UX: missing Edit menu items (#16416), search-with-DuckDuckGo context item, the combined
  link/browser toolbar item (#15404).
- The fork's topic branches deserve their own pass when their subject comes up:
  `AdiumApplescriptRunnerUsingXPC` for the AppKit-objects-die-on-the-main-thread constraint in
  AdiumApplescriptRunner, `HistoricMUCMessages` and `IRCServerConsole` for their features,
  `eventloop_libdispatch` for the glib loop.

## Suggested order

WebKit 1, the Carbon file system and the modal-delegate sheets, which used to head this list, are
done.

1. Notarisation, with entitlements and the hardened runtime.
2. Secure Transport.
3. The long tail.
