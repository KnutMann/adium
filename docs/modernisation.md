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

## The one that can actually break the application

**WebKit 1.** `WebView`, `WebFrame`, `DOMHTMLElement`, `DOMRange` and neighbours. Apple removed
this from iOS years ago and keeps it on the Mac out of politeness. The chat window already runs
on `WKWebView`; two users are left.

- `Plugins/WebKit Message View/ESWebKitMessageViewPreferences.m` — the live style preview, through
  `AIWebKitPreviewMessageViewController`, which subclasses the old controller
- `Plugins/WebKit Message View/AIWebKitMessageViewController.m` — kept compiled as a dormant
  fallback and reachable from nothing

The second is the cheapest: deciding it is dead removes most of the remaining calls on its own.
`AMPurpleRequestFieldsController` was the third and is done: the protocol form is built on
`AISettingsFormView` now, one row per field, following the shape of the never released 1.6
(shtrom/adium b558e23d8) without its per-type xibs.

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

Where Network.framework IS the right tool is the reachability monitor, and that is already
written down as roadmap item M07 with the correct caveats (NWPathMonitor for the global path;
it is not a host-reachability oracle and has nothing to do with proxies).

**Accessibility**, 15 calls in the old attribute style.

**Address Book**, 2 calls. Small only because the integration was cut back; `ABPerson` and friends
are deprecated in favour of Contacts and the remaining uses are in the address book tab and the
picture tool.

**Atomics**: done. All 15 OSAtomic sites in the log indexing moved to `<stdatomic.h>`, with the
five variables retyped `_Atomic` so every plain read keeps full-barrier meaning, and the two
always-succeeding compare-and-swaps rewritten as the plain stores they were.

**~30 further deprecated calls** spread thin: the certificate-trust panel's old Security API, the
old-style status item view, a strftime date formatter in the message styles, and single renames in
the Purple service UI. The census command above lists them all.

**Help pages for services that are gone.** `AdiumHelp/pgs` still explains how to set up AIM, ICQ,
MobileMe, Twitter, Sametime and Bonjour. Nothing links these to the build, so they are stale text
shipped inside the application rather than anything that can break, and fixing one of them without
the rest would only make the set less coherent. Worth one pass over the whole directory some day.

## Not warnings, and still worth doing

**Notarisation.** `Adium.entitlements` exists and is assigned to nothing:
`CODE_SIGN_ENTITLEMENTS` appears nowhere in the project, and the built application carries only the
automatic debug entitlement. Harmless while the hardened runtime is off, silently fatal the day it
is turned on, because TCC then refuses without ever asking the user.

**Camera and microphone descriptions.** `Resources/Info.plist` has neither
`NSCameraUsageDescription` nor `NSMicrophoneUsageDescription`. Any future call feature aborts on
first use rather than asking.

**The XtrasCreator.** A standalone tool under `Other/XtrasCreator` with its own project, not
built by the main one, and demonstrably barely used: packs it writes never had their author shown,
and nobody noticed for eighteen years. Its Info.plist declares editors for all seven Xtra kinds,
but only the two icon-pack editors were ever written; the other five document classes
(AXCSoundSetDocument, AXCEmoticonSetDocument, AXCMessageStyleDocument, AXCScriptPackDocument,
AXCDockIconPackDocument) never existed at any point in the repository's history, so they are
declarations of intent, not lost code, and would have to be built from the two that exist plus
the AXCAbstractXtraDocument base, which already handles the bundle structure, Info.plist,
version, author and readme. An overhaul also means: the service template for a new icon set
still proposes the 2008 roster (AIM, Bonjour, MobileMe...) instead of asking the running app
what it speaks; and whether the project builds on arm64 at all has not been checked. Worth doing
if icon sets are going to be made for this fork; the sound and emoticon editors would be small,
the message style editor is a project of its own. When the overhaul happens, upstream already
converted five of the six nibs to xibs (found in jas8522/adium@6ff728a under
`Other/XtrasCreator/`); the sixth, `IconPack_IconPlistView.nib`, was lost upstream in that
conversion while the code still loads it by name, so our binary nib is the only surviving
copy and has to be converted by hand.

**Reproducible plugin builds.** The Telegram plugin was a binary in `PurplePlugins/` whose build
recipe had been lost, which cost an account when it was rebuilt from what the tree actually held.
That one is fixed and guarded. WhatsApp and Signal have not been checked the same way.

**libpurple 2.14.14.** Barely maintained upstream. A break in OpenSSL or glib lands here and has to
be patched locally.

## Suggested order

1. Decide whether the dormant `AIWebKitMessageViewController` can go. Cheap, and it settles most of
   the WebKit count.
2. The other two WebKit users. This is the item that decides whether the application still starts in
   five years.
3. Notarisation, with entitlements and the hardened runtime.
4. Carbon file system and the modal-delegate sheets, both mechanical.
5. Secure Transport.
6. The long tail.
