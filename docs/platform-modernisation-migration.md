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
| M10 | P2 | Remove the obsolete Spotlight-importer subproject | proposed |
| M11 | P0 | Replace the obsolete release and update-publishing pipeline | proposed |
| M12 | P2 | Retire or rebuild unusable developer utilities | proposed |
| M13 | P1 | Audit the shipped in-app help against supported functionality | proposed |

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

**Acceptance:** selection, inactive selection, keyboard navigation, high
contrast, dark appearance, and variable-height contact rows still render
correctly. Do not change `AIVariableHeightOutlineView` in the same change set.

### M02b: Certificate trust explanatory text

`AIPurpleCertificateTrustWarningAlert` adds the non-public
`setInformativeText:` selector to `SFCertificateTrustPanel`.

**Implementation:** show the explanatory hostname/error text in an AppKit
alert or sheet owned by Adium, then show the unmodified public certificate
trust panel. Keep the existing allow/deny and certificate-chain behaviour.

**Acceptance:** invalid certificate, self-signed certificate, cancel, and
trust/continue flows preserve their current account outcomes. Never replace
certificate validation with a plain alert.

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

Apple explicitly advises against using `--deep` while signing nested code:
<https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac>.
Apple's current custom notarization workflow uses `notarytool` and `stapler`:
<https://developer.apple.com/documentation/security/customizing-the-notarization-workflow>.

### Primary code

- `Makefile` (the `latest` target)
- `Release/Makefile`
- `Release/make-diskimage.sh`
- `Release/sign_update.rb`
- `Release/upload-nightly.sh`
- `Utilities/Build/buildDaily.sh`
- `Utilities/AppcastReplaceItem.py`
- `Release/Readme-codesigning.txt`

### Implementation plan

1. Replace both historical entry points with one documented CI-oriented
   release command. Its inputs must be an immutable Git commit, version,
   configuration, signing identity, and deployment credentials. It must never
   update, clean, or otherwise mutate the caller's checkout. Delete Mercurial
   and SVN commands rather than translating their destructive semantics.
2. Archive and export the app using current Xcode tooling. Let target build
   settings sign ordinary nested code where possible. If a manual signing step
   remains necessary, enumerate bundles, frameworks, plug-ins, and helper
   executables, sign deepest-first, then sign the app. Use `--deep` only for
   recursive verification, not signing.
3. Add release gates: `codesign -vvv --deep --strict`, an appropriate
   Gatekeeper assessment, notarization with `xcrun notarytool submit --wait`,
   ticket stapling, and post-stapling validation. Store signing and notary
   credentials in CI or a keychain profile, never in files such as
   `~/adium-password` or in the repository.
4. Audit the bundled Sparkle version and the installed-user update matrix
   before replacing the update format. Current Sparkle publishing uses EdDSA
   signatures and recommends `generate_appcast`:
   <https://sparkle-project.org/documentation/publishing/>. A legacy client
   that only understands DSA may need a final bridge update or a documented
   manual-update path. Do not publish an EdDSA-only appcast until that
   transition is explicit.
5. Decide whether a custom DMG SLA or Finder-open-window metadata is still a
   release requirement. If yes, replace `/Developer/Tools/ResMerger`, `CpMac`,
   `Rez`, and the optional `openUp` helper with a maintained, reproducible DMG
   packaging step. If no, delete that branch instead of preserving an
   untestable resource-fork workflow.

### Acceptance criteria

- A release build starts from a detached Git commit and makes no checkout
  changes.
- The distribution DMG contains a signed, hardened and notarized app whose
  nested code passes strict recursive validation.
- A fresh macOS 11 or later machine can open the stapled DMG and launch the
  app without a Gatekeeper workaround.
- The generated appcast validates with the shipped Sparkle framework, offers
  the update to a representative installed version, and verifies its archive
  signature before installation.
- Nightly and stable publication use the same signing, validation, and upload
  primitives; only channel configuration differs.

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
assign M13 only after a support matrix is available. Mark the corresponding row
in the status table when work begins and record any intentionally changed
behaviour in the change description.
