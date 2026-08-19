# Platform-modernisation migration roadmap

This document is an implementation roadmap for agents working on the next
platform-modernisation work in Adium. It is deliberately separate from
`docs/arc-migration.md` and `docs/modernisation.md`; do not amend either of
those documents as part of work described here.

The supported application baseline is Apple Silicon and macOS 11. The main
target currently builds against the macOS 26.5 SDK. ARC migration is owned by
another effort and is out of scope here.

## Rules for every item

- Take one numbered item per change set. Do not combine a UI rewrite, an API
  migration, and target-setting cleanup in one review.
- Preserve the existing dirty worktree. Read the current version of a file
  immediately before changing it; parallel agents are actively modernising the
  same code.
- Build the affected target before and after the change. For user-facing work,
  exercise the listed manual acceptance cases as well.
- Do not remove a compatibility reader for existing user data without a
  versioned, tested migration and an explicit product decision.
- Prefer AppKit/Foundation/Network/Contacts APIs already available on macOS 11
  over a new third-party dependency or a SwiftUI rewrite.

## Status and order

| ID | Priority | Scope | Status |
| --- | --- | --- | --- |
| M01 | P0 | AddressBook to Contacts | proposed |
| M02 | P0 | Remove private system APIs | proposed |
| M03 | P1 | Raise all owned targets to the macOS 11 baseline | proposed |
| M04 | P1 | Replace AutoHyperlinks with a small native link detector | proposed |
| M05 | P1 | Remove the hand-written URL query parser | proposed |
| M06 | P2 | Replace the custom ISO-8601 formatter after compatibility proof | proposed |
| M07 | P2 | Simplify connectivity monitoring | proposed |
| M08 | P2 | Move two legacy AppKit views to public modern APIs | proposed |
| M09 | P1 | Modernise the standalone XtrasCreator tool | implemented; Finder UI verification pending |
| M10 | P2 | Remove the obsolete Spotlight-importer subproject | implemented; live metadata verification pending |
| M11 | P0 | Ship signed, notarized GitHub Releases; retire the obsolete release path | proposed |
| M12 | P2 | Retire or rebuild unusable developer utilities | proposed |
| M13 | P1 | Audit the shipped in-app help against supported functionality | proposed |
| M14 | P1 | Make the application appearance-correct in Dark Mode | proposed |
| M15 | P1 | Reject invalid plug-in registration enum values at runtime | proposed |
| M16 | P2 | Add deterministic smoke coverage for controllable transports | proposed |
| M17 | P2 | Define the next XMPP capability work from evidence | proposed |
| M18 | P3 | Assess modern Xtra type registration without breaking bundles | proposed |
| M19 | P2 | Make dependency acquisition verifiable and maintainable | proposed |
| M20 | P2 | Restore automated unit tests by migrating SenTestingKit to XCTest | proposed |

M01 and M02 are the best first runtime work: they remove unsupported API
surface. M11 is release-critical work, but requires a designated release owner
and access to signing and publishing infrastructure. M03 should follow before
broadening any API migration, because it eliminates dead availability branches
that otherwise obscure the code.

## M01: Migrate AddressBook data access to Contacts

### Why

`AIAddressBookController` still stores and indexes `ABPerson` objects, listens
to `kABDatabaseChangedExternallyNotification`, and opens `addressbook://` URLs.
It is also partially migrated already: permission uses `CNContactStore` in the
same controller. Keeping both models makes permissions, threading, and record
identity hard to reason about.

Apple documents the Contacts framework as the replacement for AddressBook:
<https://developer.apple.com/documentation/contacts>.

### Primary code

- `Frameworks/Adium/Source/AIAddressBookController.{h,m}`
- `Frameworks/Adium/Source/AIAddressBookUserIconSource.{h,m}`
- `Frameworks/AIUtilities/Source/OWAddressBookAdditions.{h,m}`
- Consumers under `Source/` that accept `ABPerson` or use an AddressBook
  unique ID.
- `Resources/Info.plist` for `NSContactsUsageDescription`.

### Implementation plan

1. Keep `AIAddressBookController` as the public Adium-facing name for the
   first change. Introduce a private immutable value object, for example
   `AIContactsRecord`, rather than passing `CNContact` or `ABPerson` through
   the Adium model layer.
2. Give that record only the properties Adium needs: stable identifier,
   formatted name, phonetic name, emails, phone numbers, Jabber identifiers,
   thumbnail/image data, and the properties needed by the contact-info pane.
3. Fetch with `CNContactStore` on a dedicated serial queue. Request only
   required keys, including `CNContactIdentifierKey`, name keys,
   `CNContactEmailAddressesKey`, `CNContactPhoneNumbersKey`,
   `CNContactInstantMessageAddressesKey`, and image keys. Transfer the
   immutable records to the main queue before updating Adium list objects.
4. Replace the bespoke add/modify/delete parsing with
   `CNContactStoreDidChangeNotification`. Coalesce notifications and rebuild
   the in-memory index initially. A later optimisation may use Contacts change
   history, but it must not be part of the first port.
5. Index `CNLabeledValue` values explicitly. In particular, map Jabber instant
   message entries by service and identifier; do not assume AddressBook
   property names or legacy key constants survive the port.
6. Keep the current permission flow but make it use the same long-lived
   `CNContactStore`. Add `NSContactsUsageDescription` before the feature can
   be enabled in a distributed build.
7. Treat the existing `addressbook://` show/edit actions as a separate product
   decision. Do not invent a `contacts://` equivalent. Preserve the context
   menu only if a documented public API can perform the action; otherwise hide
   or replace it with an Adium contact inspector.
8. Search preferences and archived objects for stored AB record IDs before
   deleting any identifier conversion. CN contact identifiers have different
   semantics, especially for unified contacts. Provide a one-time migration or
   discard only nonessential cached links after an explicit decision.

### Acceptance criteria

- First launch requests Contacts permission with a useful purpose string.
- Denial leaves Adium usable and does not repeatedly prompt.
- Email, phone, Jabber, display-name, phonetic-name, and avatar matching work
  after a full rebuild and after a Contacts.app edit.
- Contacts changes while Adium is running refresh the list without stale
  `ABPerson` references.
- Test the merged/unified-contact case and an entry without image data.

## M02: Remove private system API calls

This item has three independent, low-risk subchanges. Land them separately.

### M02a: Outline-view selection rendering

`AIAlternatingRowOutlineView` declares and calls the private
`-[NSOutlineView _highlightColorForCell:]` method.

**Implementation:** remove the private category and let AppKit draw the
standard selection where that is sufficient. If a theme requires custom
selection drawing, provide it through a public `NSTableRowView` subclass and
`outlineView:rowViewForItem:`. Move the alternating-row and grid policy into
public `NSTableView` properties or the row view.

**Related recent work:** commit `c8b82535d` (12 August 2026) replaced manual
`drawRect:` focus-ring painting in `AIImageViewWithImagePicker` with AppKit's
public focus-ring-mask API. That class is the superclass of the editable
avatar in the contact-info inspector, which is why the defect was visible
there. It is a useful implementation precedent, but not an incomplete M02a
change: focus indication and table-row selection are separate AppKit drawing
paths, and that commit does not touch outline views. M02a remains necessary
because `AIAlternatingRowOutlineView` still both paints selection itself and
uses `_highlightColorForCell:` to suppress AppKit's cell highlight. The
inactive-selection suppression in `AIListOutlineView+Drawing` also still
uses private `_drawRowInRect:colored:selected:` and belongs in this work item.

**Acceptance:** selection, inactive selection, keyboard navigation, high
contrast, dark appearance, and variable-height contact rows still render
correctly. Do not change `AIVariableHeightOutlineView` in the same change set.

### M02b: Certificate trust explanatory text

`AIPurpleCertificateTrustWarningAlert` adds the non-public
`setInformativeText:` selector to `SFCertificateTrustPanel`.

**Security finding:** upstream issue [adium/adium#44](https://github.com/adium/adium/issues/44)
reports that an IRC connection to an expired certificate gets no meaningful
warning. The current callback only finds Jabber accounts; its fallback calls
the libpurple callback with `true`. Consequently an unrecognised connection,
including IRCv3, is accepted without a trust decision. Do not preserve that
fallback as part of a UI-only migration.

**Implementation:** show the explanatory hostname/error text in an AppKit
alert or sheet owned by Adium, then show the unmodified public certificate
trust panel. Associate the `PurpleSslConnection` with its owning
`CBPurpleAccount` rather than scanning only Jabber accounts, so the same
policy covers every shipped TLS-capable service. An unknown owner must fail
closed (`query_cert_cb(false, ...)`), not silently accept the chain. Retain an
explicit per-account opt-out only where it already exists and is visible to
the user.

**Acceptance:** invalid certificate, self-signed certificate, cancel, and
trust/continue flows are exercised for both Jabber and IRCv3, including
`expired.badssl.com:443` configured as SSL IRC. An invalid or unowned chain
never connects merely because the UI cannot identify its account. Never
replace certificate validation with a plain alert.

### M02c: Private recent-picture integration

`IKPictureTaker` itself is public and may remain. `IKRecentPicture` and
`setRecentPictureAsImageInput:` are not public API.

**Implementation:** remove the custom recent-picture object and selector.
Use the documented PictureTaker input/output APIs, its documented recents UI,
or Adium-owned image history. Keep file promises, pasteboard, drag/drop, and
cropping behaviour in `AIImageViewWithImagePicker` intact.

**Acceptance:** choose, crop, paste, drag out, cancel, and image deletion all
work; no class-dumped selector or `IKRecentPicture` declaration remains.

## M03: Make macOS 11 the effective baseline everywhere

### Why

The application target is macOS 11/arm64, while owned child projects still
carry 10.6 or 10.13 deployment settings, obsolete SDK compatibility
declarations, and an Intel-only Spotlight-importer configuration. This creates
dead branches and makes the build graph harder to understand.

### Primary code

- `Frameworks/AIUtilities/Source/AIOSCompatibility.h`
- `Frameworks/AIUtilities/Source/AIApplicationAdditions.{h,m}`
- `Source/AIStandardListScrollView.m` and `Source/AIListController.m`
- AutoHyperlinks and MMTabBarView xcconfigs/project settings
- `Frameworks/AIUtilities/xcconfigs/Spotlight Importer.xcconfig`

### Implementation plan

1. Set owned nested targets to `MACOSX_DEPLOYMENT_TARGET = 11.0` and arm64 or
   inherited standard architectures, matching the supported product. Do not
   change vendored dependency build settings as incidental cleanup.
2. Remove `AIOSCompatibility.h` only after replacing its imports and proving
   every formerly guarded declaration is supplied by the macOS 11 SDK.
3. Delete `isOnLionOrNewer` and `isOnMavericksOrNewer`. The two callers can
   use their macOS-11 behaviour unconditionally.
4. Audit framework link phases after the source cleanup. Remove a Carbon or
   CoreServices link only when `otool -L` and a clean link prove it is unused;
   AutoHyperlinks currently has a LaunchServices dependency.
5. Keep the active Spotlight-importer target in `AIUtilities.xcodeproj` on
   inherited standard architectures. It already builds as arm64 with the
   current SDK. Validate the embedded importer with the app, and handle the
   obsolete Intel-only subproject separately as M10.

### Acceptance criteria

- Clean Debug and Release builds have a uniform macOS 11 deployment target.
- The built app and embedded Spotlight importer, if retained, contain arm64.
- No production source includes `AIOSCompatibility.h` or checks for Lion or
  Mavericks.
- Test the contact-list scrolling and separate-Spaces behaviour affected by
  the two removed version probes.

## M04: Replace AutoHyperlinks carefully

### Why

The custom Flex-based scanner is a standalone framework with old target
settings and a 569-line parser. It is used by the display filter and link
management UI. Foundation's `NSDataDetector` covers ordinary links in natural
language text, but it is not a strict URL validator and may not recognise all
custom schemes.

Apple describes this limitation explicitly:
<https://developer.apple.com/documentation/foundation/nsdatadetector>.

### Implementation plan

1. First extract a small `AILinkDetector` interface in the application code.
   Make it return ranges and `NSURL` values, not attributed strings.
2. Implement normal `http`, `https`, `mailto`, and ordinary bare URL detection
   with `NSDataDetector`. Apply `NSLinkAttributeName` only to ranges that do
   not already have that attribute.
3. Add a deliberately small supplementary matcher only for product-approved
   schemes that `NSDataDetector` does not cover. Do not reproduce every rule
   of the old lexer by default. Use a public workspace/URL-handler API or a
   documented allow-list rather than an internal LaunchServices query.
4. Run the existing AutoHyperlinks URI corpus against old and new detectors.
   Categorise every difference as an intended improvement, a required
   compatibility exception, or a regression before deleting the framework.
5. After both production consumers are migrated, remove the framework target,
   project references, embedding/copy phases, LinkDriver, legacy OCUnit target,
   and its old deployment settings together.

### Acceptance criteria

- Existing `NSLinkAttributeName` attributes remain untouched.
- Links in incoming and outgoing messages are correct, including punctuation,
  brackets, internationalised domains, escaped URLs, mail addresses, and
  approved custom schemes.
- The old corpus is preserved or ported to the supported unit-test target.
- No product target links or embeds `AutoHyperlinks.framework`.

## M05: Replace AIURLAdditions query parsing

`NSURL(AIURLAdditions)` manually splits queries on `&`, `;`, and `=`. It does
not model escaped values, duplicate keys, empty values, or a value containing
an equals sign.

**Implementation:** replace callers with `NSURLComponents` and
`NSURLQueryItem`. If a caller deliberately accepts semicolon separators,
normalise that exact legacy input in one well-tested adapter before creating
components. Delete the category once callers are gone.

**Acceptance:** add unit cases for percent-encoded values, repeated keys,
empty values, `=` in the value, and both supported separators. Do not change
the semantics of the caller's first-value versus all-values choice by accident.

## M06: Replace the custom ISO-8601 formatter only after proof

`ISO8601DateFormatter` is nearly 1,000 lines and is built by both AIUtilities
and the Spotlight importer. `NSISO8601DateFormatter` is available on the
supported baseline and is the Foundation API for this format:
<https://developer.apple.com/documentation/foundation/iso8601dateformatter>.

**Implementation:** build a table-driven test corpus from real transcript
dates, imported logs, and every existing formatter test. Map each required
format to `NSISO8601DateFormatOptions`; use a POSIX `NSDateFormatter` only for
documented legacy variants the system formatter cannot parse. Retain a thin
adapter if callers need the `NSFormatter` interface.

**Acceptance:** old and new parsing/formatting agree for the approved corpus,
including timezone offsets, fractional seconds, week/ordinal forms if
supported, malformed-input rejection, and transcript filenames. Build and run
the Spotlight importer as part of this work. Do not start this until the
corpus exists.

## M07: Simplify connectivity monitoring without weakening it

`AIHostReachabilityMonitor` combines `CFHost`, `SCNetworkReachability`, raw
sockets, run-loop scheduling, locks, and sleep handling. Its only production
consumer is account auto-connect.

`NWPathMonitor` is appropriate for global network-path state:
<https://developer.apple.com/documentation/Network/NWPathMonitor>.
It is *not* a host-reachability replacement.

**Implementation:** first introduce an `AIConnectivityMonitoring` protocol and
test the account auto-connect policy with a fake monitor. Then make the
product decision:

- For normal automatic reconnection, use one `NWPathMonitor` for the global
  path and let libpurple's real connection attempt decide server reachability.
- If per-server probing remains essential, implement it explicitly with
  `NWConnection` and clear timeouts. Do not infer that a reachable local path
  means a particular server is reachable.

Deliver the interface/policy test separately from the monitor replacement.

**Acceptance:** offline launch, network return, sleep/wake, DNS failure, one
unreachable account among reachable accounts, and rapid network changes do not
produce duplicate connects or permanently waiting accounts.

## M08: Simplify legacy AppKit view code

### Image collection

`AIImageCollectionView` uses the pre-10.11 `content`/bindings architecture,
manual KVO, tracking areas, and hand-drawn highlight state. It has only two
product consumers: contact-picture selection and Dock-icon selection.

**Implementation:** migrate one consumer at a time to a modern
`NSCollectionViewDataSource`, reusable `NSCollectionViewItem`, and a public
layout. Keep selection, deletion, drag/drop, and image assignment in the
consumer's controller rather than in a general-purpose subclass. Apple's
modern collection-view architecture is documented at
<https://developer.apple.com/documentation/appkit/nscollectionview>.

### Alternating rows

`AIAlternatingRowTableView` is an empty compatibility subclass and should be
removed first by changing its XIB class references to `NSTableView`.
`AIAlternatingRowOutlineView` is covered by M02a; keep it until variable-height
and theme clients have moved to public row-view APIs.

**Acceptance:** keyboard selection, deletion, hover, drag/drop, inactive
window behaviour, dark mode, and all image-selection sheets work at normal and
large accessibility text sizes.

## M09: Modernise the standalone XtrasCreator tool

**Status:** Implemented. The arm64 Debug build, focused sorted-array tests,
the `NSURLIsPackageKey` round-trip test, and legacy/current Xtra format
round-trips pass. Finder verification of a custom icon selected through the UI
remains a manual acceptance check.

**Scope boundary:** Only Status Icons and Service Icons are functional document
types: `AXCStatusIconPackDocument` and `AXCServiceIconPackDocument` exist.
The other Xtra types still registered in the tool's `Info.plist` have no
document class and are deliberately disabled by `AXCStartingPointsController`.
Do not claim that this work restores creation of Sound Sets, Emoticon Sets,
Message Styles, Script Packs, or Dock Icon Packs; each needs its missing model
and writer implemented as separate product work.

### Why

`Other/XtrasCreator` is a standalone developer tool and is not embedded by
Adium. It currently fails an arm64 Debug build with the current SDK before
linking, because its generic sorted-array category calls `objc_msgSend` without
a typed function pointer. Its Xtra-writing path also contains about 1,300 lines
of Carbon icon-family and Finder-info code for two operations that public APIs
now provide.

This is a good isolated starting point: its product output is an Xtra bundle,
not a runtime component of the messenger. Do not mix it with the app's ARC
migration.

### Primary code

- `Other/XtrasCreator/NSMutableArrayAdditions.{h,m}`
- `Other/XtrasCreator/AXCAbstractXtraDocument.{h,m}`
- `Other/XtrasCreator/AXCIconPackDocument.m`
- `Frameworks/Adium/Source/AIServiceIcons.m`
- `Other/XtrasCreator/IconFamily.{h,m}`
- `Other/XtrasCreator/NSString+CarbonFSSpecCreation.{h,m}`
- `Other/XtrasCreator/NSFileManager+BundleBit.{h,m}`
- `Other/XtrasCreator/XtrasCreator.xcodeproj/project.pbxproj`

### Implementation plan

1. Repair the build failure in `compareObjectsWithSelector` using a typed IMP,
   for example `NSComparisonResult (*)(id, SEL, id)`, obtained with
   `methodForSelector:`. At the same time change the category's return type
   and indexes from `unsigned` to `NSUInteger`. Keep its existing sorted-array
   contract and add focused tests for empty, one-element, before, after, and
   equal insertion cases.
2. In `AXCAbstractXtraDocument`, replace the sole production use of
   `IconFamily` with `-[NSWorkspace setIcon:forFile:options:]`. Pass
   `NSExcludeQuickDrawElementsIconCreationOption`; only call it when the
   document has an icon, because a nil image removes a custom icon. Treat a NO
   result as a save failure that is surfaced to the caller rather than silently
   creating a bundle with incomplete metadata.
3. Replace `NSFileManager+BundleBit` with the documented
   `NSURLIsPackageKey` resource value on the newly created directory. On the
   supported macOS 11 baseline the key is writable for directories. Preserve
   the registered `LSTypeIsPackage` declarations in XtrasCreator's
   `Info.plist`; extension registration and the Finder package bit serve
   different discovery paths.
4. After testing the output, remove `IconFamily`, its Carbon FSSpec helper,
   the bundle-bit category, all associated project references/build files, and
   the Carbon framework link. `IconFamily` has no remaining consumer outside
   the Xtra document writer, so do not retain it as unused source.
5. In a separate cleanup change, set `ALWAYS_SEARCH_USER_PATHS = NO` and give
   the target a stable `PRODUCT_BUNDLE_IDENTIFIER` matching its Info.plist.
   Do not remove `ExceptionHandling.framework` in this item: the old local
   exception symbolication feature has no drop-in Foundation equivalent and
   needs a separate decision about crash reporting.

### Xtra format compatibility (implemented)

The two functional icon formats have two valid on-disk layouts:

- **Legacy:** a flat directory named `*.AdiumStatusIcons` or
  `*.AdiumServiceIcons`. `Icons.plist` is at its root and contains
  `AdiumSetVersion = 1`; it has no Xtra `Info.plist`.
- **Current:** a package with `Contents/Info.plist`, where
  `XtraBundleVersion = 1`, and `Contents/Resources/Icons.plist`, where
  `AdiumSetVersion = 1`.

The importer must recognise exactly those two versions. Do not accept an
arbitrary directory merely because it has an icon-like filename: malformed
packs must remain an open error. For a legacy import, derive the display name
from the filename, use empty author and `1.0` version defaults, and generate a
new `com.adiumx.xtra.<UUID>` bundle identifier for the exported package.

`AXCIconPackDocument` must remove `AdiumSetVersion` before constructing its
category model, while preserving every valid category and referenced resource.
The writer must always produce both version markers: `XtraBundleVersion = 1` in
`Contents/Info.plist` and `AdiumSetVersion = 1` in `Icons.plist`. It must use
error-reporting `NSFileManager` directory/copy APIs and fail the save on a
missing resource or failed write, rather than leaving a silently partial
bundle. A loaded plain-text ReadMe should remain plain text when saved without
an attached editor view.

The runtime readers must select the resource root from `XtraBundleVersion`:
legacy packs use their root and current packs use `NSBundle.resourcePath`.
`AIStatusIcons` already had this behaviour; `AIServiceIcons` needs the same
normalisation for activation, preview generation, and fallback/default icon
loading. Keep the `AdiumSetVersion` validation after resolving that root.

For reproducible manual fixtures, use the Candyball Status Icons package
(Xtra ID 2010) and Up2Date Aqua Service Icons (Xtra ID 3743) from
<https://www.adiumxtras.com/>. Keep downloaded third-party Xtras out of the
repository.

### Icon Keys outline view (implemented crash fix; UI rewrite deferred)

The `Icon keys` tab uses an `NSOutlineView`, which remains the appropriate
AppKit control for a two-level category/key hierarchy. Do not replace it with
a custom tree widget merely to address a crash.

Its 2005 cell-based data source must use `NSInteger`/`NSUInteger` for every
outline index. In particular, never narrow the result of
`indexOfObjectIdenticalTo:` to `unsigned` before comparing it to `NSNotFound`.
On 64-bit macOS that turns the sentinel into a different value, so an
`AXCIconPackEntry` is misclassified as a category and passed directly to an
`NSTextFieldCell`; current AppKit then aborts while retaining the invalid cell
value. Return a string for the key column and an `NSNumber` resource index for
an entry, and reject edits to category rows.

The old NIB, cell-based pop-up column, hand-managed column width, and immediate
menu population are awkward but separate from this correctness fix. A later,
reviewable UI change may convert this one interface to an XIB and a view-based
`NSOutlineView` using `outlineView:viewForTableColumn:item:`. Preserve the
existing category expansion, resource selection, and drag/drop semantics while
doing so; it is not a drop-in switch of view classes.

### Acceptance criteria

- `xcodebuild -project Other/XtrasCreator/XtrasCreator.xcodeproj -scheme
  XtrasCreator -configuration Debug build` succeeds for arm64.
- A flat legacy and a current package for **both** Status Icons and Service
  Icons load successfully. Re-saving each yields a package with
  `Contents/Info.plist`, `Contents/Resources/Icons.plist`, both version
  markers, all referenced resources, and the original plain/rich ReadMe mode.
- `AIServiceIcons` resolves and loads an icon from both a flat legacy Service
  Icons package and a current package; `AIStatusIcons` continues to do so.
- With a loaded Status Icons package, expanding `Icon keys` displays category
  rows and child entries without an exception. A child entry returns a string
  for the key column and an `NSNumber` for the resource column; an edit event
  for a category row is ignored safely.
- Create each of the two functional Xtra types and open it in Finder: it is
  recognised as a package and displays the selected custom icon after Finder
  refresh/relaunch.
- `rg 'Carbon/|IconFamily|CarbonFSSpec' Other/XtrasCreator` returns no
  production source or project reference after the migration.

## M10: Remove the obsolete Spotlight-importer subproject

### Why

`Frameworks/AIUtilities/Other/Adium Spotlight Importer/AdiumSpotlightImporter.xcodeproj`
is not the importer that Adium builds or embeds. The shipped product comes from
the `Spotlight Importer` target in `Frameworks/AIUtilities/AIUtilities.xcodeproj`
and is copied by `Adium.xcodeproj` to `Contents/Library/Spotlight`. That active
target compiled successfully for arm64 against the current SDK during this
audit.

The old subproject remains only as a project-group/reference-proxy graph. It
contains an Intel-only `VALID_ARCHS = x86_64` setting and inactive
`AISpotlightImporterTest` and `AdiumFauxSpotlightImporter` targets. Keeping two
build descriptions for the same source directory creates misleading search
results and encourages edits in the wrong target.

### Implementation plan

1. Confirm the product dependency chain before editing: Adium depends on
   AIUtilities' `Spotlight Importer` target, and its Copy Files phase consumes
   AIUtilities' `AdiumSpotlightImporter.mdimporter` product. Do not remove the
   source, schema, Info.plist, or localisation files in the directory; the
   active target owns them.
2. Delete the old nested `AdiumSpotlightImporter.xcodeproj` and remove only
   its `PBXFileReference`, `PBXContainerItemProxy`, `PBXReferenceProxy`, and
   display-group entries from `AIUtilities.xcodeproj`. A project-file-aware
   editor is preferable to broad text replacement.
3. Decide separately whether the faux app and command-line test sources are
   worth preserving. They are not part of the active build graph. Keep them
   only after making either one a supported automated test; otherwise remove
   them in a later, separately reviewed change.
4. Correct the active target's misspelled bundle identifier
   `com.adiumX.adiumX.spotlightImpoter` only after checking release signing,
   installed importer replacement behaviour, and any updater assumptions.
   This is metadata cleanup, not a reason to change the importer protocol.

### Acceptance criteria

- `xcodebuild -project Frameworks/AIUtilities/AIUtilities.xcodeproj -scheme
  'Spotlight Importer' -configuration Debug build` succeeds on arm64.
- A clean Adium build still embeds exactly one
  `AdiumSpotlightImporter.mdimporter` in `Contents/Library/Spotlight`.
- `mdimport -r <path-to-AdiumSpotlightImporter.mdimporter>` followed by a
  representative HTML and XML transcript exercises the importer on a
  development machine.
- The project graph contains one authoritative build target for the importer
  and no `VALID_ARCHS` setting remains in this source area.

## M11: Replace the obsolete release and update-publishing pipeline

### Why

`Release/Makefile` is an unfit release path for the current repository. Its
default `all` target invokes Mercurial, creates old DSA Sparkle signatures,
prints an appcast using MD5 and a macOS 10.6 minimum version, and force-signs
the entire app with `codesign --deep`. `Utilities/Build/buildDaily.sh` has a
separate SVN-based daily-build path. The DMG scripts also reference removed
`/Developer/Tools` utilities.

These are not harmless historical conveniences: a maintainer following the
documented release command can update the wrong working copy or ship a bundle
that has not gone through a supported signing and notarization workflow.
This is the same underlying problem reported by upstream issue
[adium/adium#17](https://github.com/adium/adium/issues/17); the release work
must cover every embedded framework and Purple plug-in rather than relying on
`codesign --deep` to conceal an incomplete signing graph.

Apple explicitly advises against using `--deep` while signing nested code:
<https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac>.
Apple's current custom notarization workflow uses `notarytool` and `stapler`:
<https://developer.apple.com/documentation/security/customizing-the-notarization-workflow>.

### Release scope and product decisions

The first supported distribution channel is a stable GitHub Release containing
one DMG. It is Developer ID signed, notarized, and stapled. The release
workflow must create a draft GitHub Release; a maintainer publishes the draft
only after the fresh-machine acceptance check below.

Do not make Sparkle, an appcast, nightlies, an updater bridge, or a custom
Finder DMG layout part of the first release. The current fork deliberately has
no working auto-updater, so an EdDSA appcast would create a second release
system and an untested security promise. Revisit it only in a dedicated
updater item with a public key, feed hosting, rollback policy, and update-path
test. Likewise, do not reactivate the old daily-build scripts merely because a
signed stable release now exists.

This plan assumes the Apple team selected for public distribution has accepted
responsibility for Adium's releases. If the `Mike Gerber` team is used, the
Account Holder creates or authorizes the Developer ID certificate and the team
API key; the resulting developer identity is what users will see in
Gatekeeper. A different team later means a different public signing identity
and must be a deliberate continuity decision.

The approach is informed by the useful parts of AdiumY's release design, but
not its `fastlane` dependency:
<https://github.com/phaedrus1992/AdiumY/blob/main/docs/releasing.md> and
<https://github.com/phaedrus1992/AdiumY/blob/main/Release/sign-bundle.sh>.
Use small, reviewable shell scripts around the existing Xcode project rather
than adding Ruby tooling solely for release orchestration.

### Deliverables

- `Makefile` (the `latest` target)
- `Release/Makefile`
- `Release/make-diskimage.sh`
- `Release/sign_update.rb`
- `Release/upload-nightly.sh`
- `Utilities/Build/buildDaily.sh`
- `Utilities/AppcastReplaceItem.py`
- `Release/Readme-codesigning.txt`
- New `Release/preflight.sh`, `Release/sign-bundle.sh`, and `Release/make-dmg.sh`
- New `.github/workflows/release.yml` and a concise `Release/README.md`

### One-time GitHub and Apple setup

1. Decide whether the first public version remains arm64-only or the project
   will first be made universal. Do not imply Intel support in a release title
   or documentation while `ARCHS` remains arm64. The semantic tag after its
   leading `v` must equal `CFBundleShortVersionString`; define a monotonic
   build-number policy before publishing.
2. In the selected Apple Developer team, create one **Developer ID
   Application** certificate. Export its private key as a password-protected
   `.p12`, retain an encrypted offline backup, and do not use automatic
   certificate-creation tooling that could revoke an in-use identity.
3. Create an **App Store Connect Team API key** for notarization. An individual
   API key is not a substitute. Record its key ID and issuer ID; download the
   `.p8` exactly once and retain an encrypted offline recovery copy.
4. Create a protected GitHub environment named `release`, restricted to the
   release maintainers. Store these environment secrets there:
   `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`,
   `ASC_KEY_P8_BASE64`, `ASC_KEY_ID`, and `ASC_ISSUER_ID`. Store `TEAM_ID` and
   the full `Developer ID Application: ...` identity as non-secret repository
   variables. The workflow creates its temporary keychain password at runtime.
5. Protect `v*` tags and require a signed, annotated tag from a release
   maintainer. The signing job has `contents: read`; only the final draft
   publishing job receives `contents: write`. Do not expose release secrets to
   pull-request jobs.

### Implemented release flow

1. `Release/preflight.sh` receives the tag and changes no files. It verifies
   that the tag points at the checked-out commit, that the tag and bundle
   version agree, that the configured signing identity is present, and that
   `notarytool` can authenticate. Run this before a long archive. The signing
   stage emits the Mach-O manifest after the app exists.
2. The workflow builds a clean archive with the shared `Adium - Release`
   scheme and `CODE_SIGNING_ALLOWED=NO`. It records the Xcode version, SDK,
   commit, tag, architecture set, and build settings in `BUILD-INFO.json`.
   Select the runner's Xcode explicitly after a successful dry run; do not
   depend on whichever Xcode happens to be the image default.
3. `Release/sign-bundle.sh` signs the finished app from the leaves upward:
   loose Mach-O executables, `.dylib` and `.so` files, frameworks, nested apps,
   XPC services, plug-ins, and the Spotlight importer, followed by the outer
   `.app`. Every signature uses the Developer ID identity, secure timestamp,
   and hardened runtime. Apply `Adium.entitlements` only to the main app; give
   a helper a separate minimal entitlement file only if it demonstrably needs
   one. Never sign with `--deep`.
4. The signing script verifies the sealed bundle with
   `codesign --verify --strict --deep --verbose=2`, then audits every Mach-O
   file with `codesign --display --verbose=2`. The audit fails for an ad-hoc,
   linker-only, unsigned, or wrong-team executable. It explicitly covers the
   bundled Purple `.so` plug-ins. Keep
   `com.apple.security.cs.disable-library-validation` only as an explicit
   policy for native third-party plug-ins; test that policy in the signed app
   and document the supported external-plug-in signing requirements.
5. Zip the signed app with `ditto -c -k --keepParent`, submit it with
   `xcrun notarytool submit --wait`, staple the accepted ticket to the app,
   and validate it with `xcrun stapler validate`. Persist the submission ID and
   signed app archive as workflow artifacts so an unusually slow Apple queue
   can be resumed without rebuilding or re-signing different bytes.
6. `Release/make-dmg.sh` stages only the stapled app, a current license/change
   note, and an `/Applications` alias, then creates the DMG with maintained
   `hdiutil`/`ditto` primitives. Start with this plain reproducible layout; a
   background image or pre-baked Finder layout is optional follow-up work, not
   a reason to retain resource-fork tooling.
7. Sign the DMG, submit the DMG for notarization, staple and validate it. Emit
   `SHA256SUMS` for the DMG and the `BUILD-INFO.json` manifest. Create a draft
   GitHub Release from the version tag and attach those three artifacts. A
   GitHub Actions artifact attestation may be added after the basic path is
   proven; it supplements, but does not replace, Apple code signing.
8. Download the DMG on a Mac that has never built Adium, mount it, copy the
   app to `/Applications`, launch it, create an IRCv3 account, and inspect the
   release identity with Gatekeeper. Publish the already-created draft only
   after that succeeds. The first stable release should have a written record
   of this check.

### GitHub workflow shape

`release.yml` triggers on protected `v*` tag pushes and supports
`workflow_dispatch` with an existing tag for recovery. It contains a single
release build job and a dependent draft-publish job. Both use the protected
`release` environment. Pin third-party actions by commit SHA, use
`persist-credentials: false` for checkout, and grant the smallest permissions
required by each job.

The release build has no reusable dependency or Bundler cache. Build inputs
are the tagged checkout and explicitly verified local artifacts, so an
untrusted PR cannot poison a cache subsequently consumed by a signing job. A
separate unsigned CI workflow may cache normal build work, but its artifacts
are never release candidates.

### Implementation plan

1. Build and validate `preflight.sh` and `sign-bundle.sh` locally with the
   designated Developer ID identity before adding publication. Use an
   unpublished test artifact; do not mint unnecessary Developer ID
   certificates. Inventory the actual final bundle rather than guessing from
   Xcode copy phases.
2. Build the plain DMG and complete app plus DMG notarization locally. Treat a
   rejection as a bundle-inventory bug and fix the exact nested code reported
   by Apple's log; do not add `--deep` or broad entitlements as a workaround.
3. Add the protected GitHub workflow, temporary-keychain import, no-cache
   release build, and draft release upload. Test first with
   `workflow_dispatch` on a non-production tag, then protect the `v*` trigger.
4. Retire the historical Mercurial/SVN/Appcast entry points after the first
   successful draft release. Preserve only a short migration note explaining
   that old DSA/MD5 feeds and unsigned nightlies are intentionally unsupported.

### Acceptance criteria

- A release build starts from the protected version tag, makes no checkout
  changes, and records its Xcode/SDK/commit/version inputs.
- Every Mach-O file in the distribution app has the expected Developer ID team
  signature; strict recursive verification, `spctl`, and stapler validation
  all pass for both app and DMG.
- A fresh macOS 11 or later machine can open the stapled DMG and launch the
  app without a Gatekeeper workaround.
- The GitHub Release is a draft until the fresh-machine acceptance result is
  recorded. Its DMG, checksum, and build manifest match the tag.
- No release credential appears in project settings, source, shell history,
  output artifacts, or an unprotected workflow. PR builds remain unsigned.
- Sparkle/appcast and nightlies remain absent until a separately approved
  product and security design exists.

## M12: Retire or rebuild unusable developer utilities

### Why

Several standalone scripts are neither part of the build graph nor executable
with current developer tools. The Analyzer directory requires Python 2,
`ccc-analyzer`, and an SVN revision; `Utilities/RunUnitTests.zsh` invokes the
removed `RunUnitTests` OCUnit tool from `/Developer/Tools`; and the old
localisation script depends on `nibtool`, `polyglot`, and `.svn` directories.
Some Python generators also use Python-2-only syntax.

Keeping them without ownership makes it unclear which checks a developer can
actually rely on. Do not mechanically translate every old script: many generate
tests for removed `AIWired*` types or refer to obsolete project paths.

### Primary code

- `Makefile` (the `astest` and `localizable-strings` targets)
- `ASUnitTests/` and `unittest runner.applescript`
- `Utilities/Analyzer/{clang-analyze.py,compare-summaries.py,reports.py,wikify-summary.py}`
- `Utilities/RunUnitTests.zsh`
- `Utilities/{GenerateColorTests.py,GenerateWiredStringTests.py,FindMacroMisuses.py}`
- `Utilities/Localization Utility Scripts/i18n.sh`
- `Utilities/manual_nib_update`

### Implementation plan

1. Make a short inventory with one row per utility: purpose, current caller,
   input/output, owner, and whether it succeeds on the supported toolchain.
   Search CI, Makefiles, Xcode phases, and developer documentation before
   deleting a file; repository search currently finds no in-tree caller for
   the standalone test runner or Analyzer entry point.
2. Delete unowned utilities with no still-relevant input or output. Preserve a
   concise README record of a deliberately retired workflow instead of keeping
   executable-looking dead code.
3. Replace a still-valued static-analysis workflow with Xcode's `analyze`
   action in CI and collect its result in a current CI artifact format. Use
   current Clang analyzer build settings rather than the obsolete
   `ccc-analyzer` interception protocol:
   <https://developer.apple.com/documentation/xcode/build-settings-reference>.
4. Move tests that still matter to the supported test target and XCTest, then
   remove `RunUnitTests.zsh`. Treat `make astest` independently: its
   AppleScript runner currently assumes an AIM service and live hard-coded
   accounts. Retain it only as an explicitly provisioned UI smoke test, or
   replace the covered assertions with deterministic XCTest coverage. Coordinate
   the AutoHyperlinks OCUnit removal with M04 rather than creating another
   temporary test runner.
5. For an actively used generator, port only that script to Python 3 with
   explicit fixtures and deterministic output. Do not alter generated test
   sources until their target has been confirmed current.
6. Replace the localisation script with Xcode localisation export/import or,
   where legacy `.strings` files must remain, `xcstringstool`. Current Xcode
   supports `xcodebuild -exportLocalizations` and `-importLocalizations`:
   <https://developer.apple.com/documentation/xcode/importing-localizations>.
   First round-trip one locale without changing translations or resource
   layout; migration to String Catalogs is a separate product decision.

### Acceptance criteria

- Every retained utility has a documented invocation, owner, and a CI or local
  smoke test on the supported Xcode/Python toolchain.
- No maintained tool requires `/Developer`, Python 2, SVN, Mercurial, OCUnit,
  `ccc-analyzer`, `polyglot`, or a version-control metadata directory.
- The static-analysis job reports actionable source paths and fails only on
  explicitly configured severity thresholds.
- A localisation export/import round trip does not delete translations,
  re-encode existing string tables unexpectedly, or change interface files
  outside the selected locale.

## M13: Audit the shipped in-app help against supported functionality

### Why

`AdiumHelp` is copied into the application bundle, so it is user-facing product
content rather than historical source material. It currently contains account
and troubleshooting pages for services and OS versions such as AIM, MobileMe,
Twitter, Google Talk, Growl, and pre-macOS-11 system behaviours. It also tells
users about the old Address Book integration covered by M01.

The problem is not that every old page must disappear. The problem is that the
help has no checked relationship to the services and features that the shipped
build actually exposes. Incorrect local help is worse than no help when a user
is restoring an old account or troubleshooting a modern macOS restriction.

### Primary code

- `AdiumHelp/`
- `Utilities/tosupportpage.sh`
- `Adium.xcodeproj/project.pbxproj` (resource copy)

### Implementation plan

1. Generate a reviewed support matrix from the built application: account
   types in the current configuration, Xtras, notification paths, transcript
   formats, and macOS permissions. Do not infer support from an old help page
   or a libpurple source file alone.
2. Compare every help navigation link and service page with that matrix. Update
   a page when the feature remains supported with changed terminology or UI;
   remove its navigation and troubleshooting advice when it is not shipped.
   In particular, do not retain an account-creation link merely for historical
   interest.
3. Replace Address Book terminology and instructions only as part of M01, so
   the help describes the shipped Contacts behaviour rather than an interim
   design. Avoid a separate broad rewrite of screenshots during that API port.
4. Add a local-link and asset check for the help bundle, then decide whether
   offline Apple Help remains a product requirement. Keep the existing bundled
   format if it does; an online documentation migration is a separate release
   and availability decision.
5. Update or retire `Utilities/tosupportpage.sh` together with the chosen
   publishing path. It currently performs a brittle chain of HTML `sed`
   substitutions and must not become a second authoritative copy of help
   structure.

### Acceptance criteria

- Help navigation advertises only features enabled in the shipped build, and
  every advertised account type has a current configuration path.
- All internal help links, images, and anchors resolve in the bundled help
  viewer without network access.
- Support articles contain no instructions for obsolete OS compatibility modes
  or an API migration that has not yet shipped.
- The release workflow has a documented owner and check for the bundled help
  content.

## M14: Make the application appearance-correct in Dark Mode

### Why

Upstream issue [adium/adium#49](https://github.com/adium/adium/issues/49)
remains applicable. The fork has dark-aware tab-bar styles and the settings
form reacts to an effective-appearance change, but it has no app-wide
appearance policy. Custom drawing still uses fixed light colours in the
contact list, list cells, borderless-list filter bar, account UI, tooltips,
and message-related views. The result can be a mixed dark window with light
surfaces or unreadable text rather than an intentional Dark Mode experience.

This does not mean imposing a dark colour scheme on user-installed Xtras.
Message styles and list themes are user content with their own contracts; the
host must first make its own chrome and default rendering appearance-correct.

### Primary code

- `Frameworks/Adium/Source/{AIListCell,AIListContactCell,AIListOutlineView+Drawing}.m`
- `Frameworks/AIUtilities/Source/{AIAlternatingRowOutlineView,AIImageTextCell}.m`
- `Source/{AIBorderlessListWindowController,AIInfoInspectorPane}.m`
- custom toolbar, tooltip, search, and message-window drawing code found by a
  fixed-colour audit
- `Resources/` image assets that are rendered as non-template AppKit images

### Implementation plan

1. Define a screenshot-based appearance matrix before changing colours:
   contact list, chat window, account editor, settings, contact inspector,
   tooltips, contextual menus, file transfers, and image pickers. Cover light,
   dark, and high-contrast appearances on the supported macOS baseline.
2. Replace fixed application-chrome colours with semantic dynamic AppKit
   colours (`labelColor`, `secondaryLabelColor`, `textBackgroundColor`,
   `controlBackgroundColor`, `separatorColor`, and selection colours) where
   that expresses the intent. Use named colour assets with light/dark variants
   only where a product-specific colour is genuinely required.
3. Retain an explicit user-selected theme colour when it has one; derive its
   contrast against the actual background and provide a safe default when the
   theme did not specify a dark variant. Do not invert arbitrary Xtra CSS,
   bitmap images, or HTML content.
4. Make M02a's public selection rendering a prerequisite for changing list
   selection colours, so selection, inactive selection, and accessibility
   settings continue to come from AppKit rather than a second hard-coded
   palette.
5. Audit WebKit message rendering separately. Advertise `prefers-color-scheme`
   to styles that opt in, but preserve legacy message styles which intentionally
   specify their own background and foreground colours.

### Acceptance criteria

- Switching the system appearance while each matrix screen is open updates
  Adium-owned chrome without reopening the application.
- Text, selections, separators, focus rings, and disabled controls meet
  contrast expectations in light, dark, and high-contrast appearances.
- Existing light-only Xtras remain readable and are not silently recoloured;
  a style that opts into `prefers-color-scheme` receives the appropriate
  appearance.
- A screenshot comparison records the expected result for every matrix screen
  and flags an accidental return to fixed light colours in application chrome.

## M15: Reject invalid plug-in registration enum values at runtime

### Why

An AdiumY code audit found unchecked enum values used as C-array indices in
plug-in-facing registration APIs. The same code is present here:

- `Source/AIStatusController.m` indexes
  `statusDictsByServiceCodeUniqueID[type]` before validating `type`.
- `Source/ESContactAlertsController.m` indexes
  `globalOnlyEventHandlersByGroup[inGroup]` and
  `eventHandlersByGroup[inGroup]` before validating `inGroup`.

An invalid value can write outside the array. The normal caller paths use
valid constants, but the APIs are intended for plug-ins and a release build
must reject bad input rather than rely on a debug-only assertion. This is a
small, independent correctness fix and should land before public releases.

### Primary code

- `Source/AIStatusController.m`
- `Source/ESContactAlertsController.m`
- Their public headers and existing unit-test target, if a suitable target can
  exercise the methods without a live account.

### Implementation plan

1. At every registration and unregistration entry point, validate the enum
   against its declared count before accessing the array. Log the invalid
   caller and return without modifying registration state. Keep an
   `NSParameterAssert` as a development diagnostic only; it is not the
   release-time safety check.
2. Audit adjacent APIs that consume the same enums so the registration and
   removal paths have identical bounds rules. Do not change status semantics,
   event ordering, or valid plug-in behavior.
3. Add focused tests, or a deterministic debug harness if the legacy test
   target cannot host the controllers. Cover negative and equal-to-count
   values, followed by a valid registration to prove state remained usable.

### Acceptance criteria

- Invalid enum input cannot write outside an array in Debug or Release.
- The invalid call is diagnosable in the log and leaves existing registrations
  intact.
- Existing services can register their statuses and event handlers unchanged.

## M16: Add deterministic smoke coverage for controllable transports

### Why

The current fork ships IRCv3 and Jabber/XMPP alongside several externally
operated services. An application that merely launches cannot demonstrate that
the libpurple bridge still connects, exchanges messages, handles TLS failure,
or survives a dependency update. AdiumY's transport-test proposal has the
right principle: test against disposable local infrastructure rather than a
public server or a maintainer's personal account:
<https://github.com/phaedrus1992/AdiumY/blob/main/docs/design/issue-133-self-contained-smoke-tests-for-each-supported-transport-epic.md>.

Only adopt that principle. This fork does not ship AdiumY's SIMPLE or Bonjour
transport implementations, and Telegram, Signal, WhatsApp, and Teams cannot
be made deterministic against a local compatible service.

### Primary code

- New test harness under `Tests/Integration/` or another documented,
  non-product directory selected after a test-runner spike.
- IRCv3 and Jabber/XMPP account setup paths under `Plugins/Purple Service/`.
- CI documentation/workflow only after the local harness is repeatable.

### Implementation plan

1. First prove a local developer command that starts an ephemeral IRC server
   (for example Ergo) and an XMPP server (for example Prosody) on random local
   ports, creates two disposable identities, and removes all state afterward.
   Do not add Docker or a service manager to the release job merely to make
   this first experiment work.
2. Start Adium with an isolated preferences and data directory. For each
   transport, assert connect, outbound marker delivery, inbound marker
   delivery, disconnect, and cleanup. A process that only exits successfully
   is not a smoke test.
3. Add a TLS-negative case for IRCv3 and Jabber once M02b is complete. It must
   demonstrate that an expired or self-signed certificate cannot silently
   connect.
4. Decide separately how a macOS GitHub runner can provision those servers.
   Until that is reliable, keep the harness a documented local release gate
   rather than a flaky required CI job. Cloud services retain a small manual
   account matrix with no credentials in the repository or Actions.

### Acceptance criteria

- One documented local command runs an isolated IRCv3 and XMPP round trip.
- Each test proves both directions of message exchange and tears down all
  temporary accounts and files.
- The certificate-negative cases fail closed after M02b.
- Adding the harness does not contact a public network or alter a developer's
  real Adium profile.

## M17: Define the next XMPP capability work from evidence

### Why

AdiumY proposes message carbons (XEP-0280), archive management (XEP-0313),
HTTP upload (XEP-0363), receipts, chat markers, and OMEMO. Those are not one
feature: they have different server requirements, privacy implications, UI
models, and dependency risk. This fork already contains receive-side hooks for
XEP-0184 receipts and XEP-0333 markers, but receipts currently log by message
ID and markers are conversation status lines rather than a per-message state.

Before adding another XMPP patch, create an honest capability matrix. The
highest-value candidates after that matrix are Carbons and MAM: they address
messages sent or read on another client and history continuity. HTTP upload is
a later file-transfer project. OMEMO is a security-sensitive protocol and is
explicitly not a follow-up to OTR without an independently reviewed
cryptographic design, dependency lifecycle, device-verification UX, and test
network.

### Primary code

- `Plugins/Purple Service/ESPurpleJabberAccount.m`
- `Plugins/Purple Service/adiumPurpleSignals.m`
- `Plugins/Purple Service/SLPurpleCocoaAdapter.m`
- `Plugins/WebKit Message View/` only after a per-message state model exists.
- New `docs/xmpp-capability-matrix.md` or an equivalent maintained source of
  truth.

### AdiumY reference implementations

AdiumY has completed the following feature series.  Use the links as source
references, not as `git cherry-pick` candidates: its ARC conversion, XMPP
adapter APIs, project files, and message-view implementation differ from this
tree.  A port starts from the final commit in each series and includes its
tests or a new equivalent test here.

| XEP | AdiumY implementation series | Porting note |
| --- | --- | --- |
| XEP-0280 Message Carbons | [initial implementation](https://github.com/phaedrus1992/AdiumY/commit/186103ce043bc1ba88738aeff0da32dc608dec5f), [mandatory protocol fixes](https://github.com/phaedrus1992/AdiumY/commit/3512b2b8c345f06c5ac9e1daa82495f47f0cf201), [review cleanup](https://github.com/phaedrus1992/AdiumY/commit/694060996fb11defe3ba826ed5cdff8e204fad22) | High user value, but raw XML interception and duplicate suppression need an end-to-end test before porting. |
| XEP-0313 Message Archive Management | [implementation](https://github.com/phaedrus1992/AdiumY/commit/b9d0287c22f249604681f23d71c0028fb4fdc315), [IQ error handling](https://github.com/phaedrus1992/AdiumY/commit/4d05e0c4b7f7255ea2e063cc728d701401937d08), [outgoing-message fix](https://github.com/phaedrus1992/AdiumY/commit/d53438bef637711e19762689bd4608ffc2f1f37f) | Requires a defined local-history and reconnect model; do not turn it on merely because a server advertises MAM. |
| XEP-0363 HTTP File Upload | [implementation](https://github.com/phaedrus1992/AdiumY/commit/69c31e33bc0d414c1c8c4dfa3534d884531dabfb), [review corrections](https://github.com/phaedrus1992/AdiumY/commit/780886c45d9f0fc2a6664d04d0c808b9477c6dfa) | A large file-transfer and URL-security project, not a small XMPP capability switch. |
| XEP-0308 Message Correction | [implementation](https://github.com/phaedrus1992/AdiumY/commit/519392892906c43a9d782351b3a4c105c742bab0), [pending-DOM fix](https://github.com/phaedrus1992/AdiumY/commit/7276459baabefd073abb26c0b88e34cfa70801aa) | AdiumY modifies its old `AIWebKitMessageViewController`; this tree uses `AIWebKitMessageViewWKController`, so this is a design reference rather than transferable code. |
| XEP-0048 Private XML Bookmarks | [implementation and tests](https://github.com/phaedrus1992/AdiumY/commit/3fce7ba84cd1d0eaad272c100022f7a6a5c5feb7) | A comparatively bounded bookmark/MUC preference candidate. |
| XEP-0402 PubSub Bookmarks | [implementation and tests](https://github.com/phaedrus1992/AdiumY/commit/407ebcf6e9ea505b7196ac07c5005f520dcd8a35) | Depends on a sound XEP-0048 migration and server capability fallback. |
| XEP-0352 Client State Indication | [implementation](https://github.com/phaedrus1992/AdiumY/commit/a54fe6099534ed39bd4083c1a1092b69a742940d), [handshake correction](https://github.com/phaedrus1992/AdiumY/commit/29901c557de79ace54ccf071c867058d97ba912e) | Small on paper, but needs an explicit macOS active/idle policy and protocol test. |
| XEP-0393 Message Styling | [implementation](https://github.com/phaedrus1992/AdiumY/commit/1c6b014702def640817914cb39b4d54da4bd26da), [review fixes](https://github.com/phaedrus1992/AdiumY/commit/c4736510bebd1d6e9ebc025c8fddd0026e7294fc), [follow-up fixes](https://github.com/phaedrus1992/AdiumY/commit/e9b9b83c62a35d2ee037b20fd2c10c258d15c537) | Broad message-rendering change; keep it behind Carbons, MAM, and the message-view test work. |

AdiumY also calls XEP-0184 delivery receipts and XEP-0333 chat markers
complete only at a partial UI level: [initial implementation](https://github.com/phaedrus1992/AdiumY/commit/7588f8e06b78799ff74e6b1a7ca2085bc06499bc)
and [capability-gating follow-up](https://github.com/phaedrus1992/AdiumY/commit/ee350e07b337587c34598abbd3a8c2f8f18f3523).
This tree already has equivalent receive-side handling.  Do not import that
series; use it only when designing a genuine per-message state model.

### Implementation plan

1. Use the M16 XMPP server to record the current behavior for standard IMs,
   group chats, receipts, markers, reconnect, file transfer, Carbons, MAM,
   and HTTP upload. Record whether each capability is absent in the current
   libpurple patch set, available but not bridged, or already visible to users.
2. Verify protocol behavior against the relevant XEP before writing code. Do
   not declare support merely because the client advertises a namespace.
3. Open at most one implementation item at a time. Prefer Carbons or MAM only
   after defining duplicate suppression, local log interaction, reconnect
   behavior, account settings, and an end-to-end test. Start from the final
   AdiumY commit series above, then port deliberately with tests rather than
   cherry-picking its project and ARC-era assumptions. Treat per-message
   receipt rendering as a separate UI/data-model item.
4. Keep OMEMO, broad XEP feature parity, and video/calling out of this item.

### Acceptance criteria

- The capability matrix distinguishes advertised, received, sent, persisted,
  and user-visible behavior.
- The next implementation item has a concrete XEP reference, failure model,
  account migration decision, and deterministic test.
- No encryption, message-history, or upload feature is advertised before its
  end-to-end behavior is verified.

## M18: Assess modern Xtra type registration without breaking bundles

### Why

The XtrasCreator work now reads current and legacy functional Xtras and writes
current bundles. A separate AdiumY proposal suggests replacing legacy
package-type handling with declared UTIs and URL schemes. The useful next step
is an assessment, not a rewrite: existing `.Adium*` bundles and Finder
drag-and-drop behavior are part of the compatibility contract.

### Primary code

- `Source/AIXtrasManager.m`
- `Source/AIAppearancePreferences.m`
- `Resources/Info.plist`
- XtrasCreator's document type declarations

### Implementation plan

1. Inventory every active Xtra package type, its bundle metadata, the current
   `com.adiumx.*` identifier construction, Finder association, installer path,
   and drag-and-drop consumer.
2. Decide whether each type needs an imported or exported `UTType` declaration
   in the active app plist. A declaration must conform to the existing bundle
   format; it cannot require an installed Xtra to change extension or metadata.
3. Add a compatibility reader and Finder/drag test before changing a writer.
   Do not add application URL schemes unless there is a real, documented
   deep-link workflow; URL schemes do not replace Xtra bundle discovery.

### Acceptance criteria

- The assessment names an owner and a migration path for every active type.
- Existing legacy and current Xtras continue to install and open unchanged in
  the test matrix.
- No URL scheme or UTI is added solely as cosmetic modernization.

## M19: Make dependency acquisition verifiable and maintainable

### Why

`Dependencies/phases/utility.sh` currently downloads source archives with
`curl -Lfo` and the phase scripts contain several remote URLs without a
checked SHA-256 manifest. A later dependency rebuild must not turn the signed
release pipeline into a trust-on-first-download process. AdiumY's checksum and
Renovate proposals are useful references, but our dependency layout differs:
<https://github.com/phaedrus1992/AdiumY/blob/main/docs/design/issue-255-get-sparklesh-downloads-sparkle-with-no-checksum-verificatio.md>.

### Primary code

- `Dependencies/phases/utility.sh`
- `Dependencies/phases/build_*.sh`
- New checked-in dependency manifest and verification tests
- Future `.github/renovate.json5`, only after the manifest exists

### Implementation plan

1. Inventory every remotely acquired archive: canonical URL, version, SHA-256,
   license/source provenance, consuming phase, and whether it is already
   tracked in Git. Make this manifest the sole input to a download helper.
2. Download to a temporary file with `curl --fail --location`, verify its
   SHA-256, then move it into the cache atomically. A missing or incorrect hash
   is an error, never a warning or an `|| true` path.
3. Make a clean dependency build verify that produced frameworks and Purple
   plug-ins contain no checkout-absolute loader paths and still pass strict
   code-signature verification after any `install_name_tool` edit.
4. Only then consider Renovate for pinned GitHub Actions and version-notice PRs
   for dependencies. Do not auto-merge a native dependency update: a human
   must update the hash, rebuild, inspect licenses, and run M16 coverage.

### Acceptance criteria

- Every network download has an explicit version, source, and verified digest.
- A corrupted archive aborts before extraction or compilation.
- A clean rebuild produces relocatable frameworks and plug-ins suitable for
  M11 signing.
- Dependency update PRs cannot bypass build and transport verification.

## M20: Restore automated unit tests by migrating SenTestingKit to XCTest

### Why

The existing test target is still an `octest` bundle and links the removed
`SenTestingKit.framework`. Eleven surviving test headers plus the shared prefix
header import SenTestingKit, and the suite has roughly 979 `STAssert...`
calls. The shared `Adium - Debug` scheme has an empty `TestAction`, so even a
successful app build proves none of
those tests. This is a direct obstacle to M16 and to safe, small regression
fixes.

The `jas8522/adium` fork completed a useful source migration in
[50f1bb7c2008c069af1d8bc50c9a536e843e2edc](https://github.com/jas8522/adium/commit/50f1bb7c2008c069af1d8bc50c9a536e843e2edc).
It converts the main and AutoHyperlinks suites, their assertions, targets, and
scheme. Treat it as a mapping reference, not a project-file cherry-pick: this
tree has different framework paths, targets, and current build settings.

### Primary code

- `UnitTests/`
- `Frameworks/AutoHyperlinks Framework/UnitTests/`
- `Adium.xcodeproj/project.pbxproj`
- `Frameworks/AutoHyperlinks Framework/AutoHyperlinks.framework.xcodeproj/project.pbxproj`
- Shared test scheme(s), starting with `Adium - Debug`

### Implementation plan

1. Create XCTest bundle targets for the main unit tests and AutoHyperlinks.
   Remove the legacy `com.apple.product-type.bundle.ocunit-test` targets and
   `SenTestingKit.framework` links only after their XCTest replacements are in
   the scheme.
2. Mechanically replace imports, `SenTestCase`, and every `STAssert...` macro
   with its XCTest equivalent. Review assertion forms with format strings,
   floating-point values, and asynchronous stress tests individually; do not
   turn failures into log-only checks.
3. Add both bundles to `Adium - Debug`'s `TestAction` and make
   `xcodebuild test -project Adium.xcodeproj -scheme 'Adium - Debug'` the
   documented baseline command. Keep application launch and protocol smoke
   tests out of this deterministic unit-test target.
4. Run the converted suite on a clean checkout, then add only stable test
   execution to ordinary pull-request CI. M16's local IRC/XMPP integration
   tests remain a separate opt-in or dedicated job.

### Acceptance criteria

- No tracked source or project file refers to SenTestingKit, OCUnit, or
  `com.apple.product-type.bundle.ocunit-test`.
- `Adium - Debug` runs both converted test bundles through XCTest and fails
  the command on an intentional assertion failure.
- Existing test coverage is preserved or explained case by case; no suite is
  silently dropped merely to obtain a green build.

## Candidates considered from the AdiumY design documents

- Contacts, private-AppKit cleanup, ARC, WKWebView, XtrasCreator, and help
  content already map to M01, M02, the separate ARC effort, completed work,
  M09, and M13 respectively. M13 remains deliberately paused while the Help
  menu is disabled.
- XEP-0184 and XEP-0333 are partially present here, so they are not new
  protocol projects. Their remaining per-message UI work is captured by M17.
- The proposed Bonjour EZV transfer fixes do not apply: this fork has no
  `EKEzvIncomingFileTransfer` source. Do not copy patches for a transport that
  is not shipped.
- Do not schedule Discord as an Adium account type. Discord's own policy
  forbids automating normal user accounts outside its OAuth2/bot API, which is
  incompatible with a general-purpose user chat client:
  <https://support.discord.com/hc/en-us/articles/115002192352-Automated-User-Accounts-Self-Bots>.
  Slack, Matrix, Bluesky, ActivityPub, RSS, Meshtastic, and revived AIM/ICQ
  are separate product proposals, not modernization work. Matrix is the only
  one worth a future feasibility spike if there is confirmed demand and a
  maintained, legally usable client library.
- Do not remove old preference/keychain migration readers on the assumption
  that nobody upgrades from prior Adium versions. This fork retains the Adium
  identity and existing user data; a compatibility-policy decision and tested
  migration are prerequisites.
- The comparable fork's broad framework-build and coverage targets are useful
  audit prompts, but its failure findings do not describe this tree's current
  framework layout. M19 requires a fresh local audit rather than importing its
  proposed rewrite.

## Explicit non-goals

- **ARC:** owned by the separate ARC migration. Do not add or remove ARC flags
  in any item here unless its owner requests a coordinated change.
- **NSURLSession:** `AIProgressDataUploader` and `XtrasInstaller` already use
  it. Do not rewrite them as part of this roadmap.
- **Archive compatibility:** the `NSUnarchiver` fallback is intentional for
  old Adium preferences. A secure-coding migration needs format versioning and
  is a distinct future project.
- **MMTabBarView:** `NSTabView` is not a drop-in replacement for vertical tabs,
  tear-off, reordering, overflow, and chat indicators. Limit work to removing
  dead pre-macOS-11 branches after M03, unless requirements change.
- **NSTextView placeholders:** AppKit has no equivalent native placeholder API
  for `NSTextView`; retain `AITextViewWithPlaceholder` unless its own behaviour
  is intentionally redesigned.

## Suggested agent hand-off

Start with M02a, M02b, M05, or M09 for bounded changes. Assign M01, M04, M06,
and M07 only to agents prepared to add tests and manually validate behavioural
compatibility. Assign M11 only with the release owner and signing credentials;
assign M13 only after a support matrix is available. M15 is a small
release-blocking safety change; M16 and M17 require protocol-test ownership;
M18 is assessment-only; M19 requires a clean dependency rebuild; and M20
should precede broad test additions. Mark the corresponding row in the status
table when work begins and record any intentionally changed behaviour in the
change description.
