# Converting a file to automatic reference counting

Adium is written for manual retain release. A few files are not, and the two live side by side in
the same target, one file at a time. This is how a file is moved across, and what to watch for.

## The mechanics

Put `-fobjc-arc` on the **build file**, not on the file reference:

```
/* AIDockNameOverlay.m in Sources */ = {isa = PBXBuildFile; fileRef = ...; settings = {COMPILER_FLAGS = "-fobjc-arc"; }; };
```

The file reference is shared by every target that compiles the file; the build file belongs to one
target. Annotating the wrong one changes more than intended and is easy to miss in review.

Never set `CLANG_ENABLE_OBJC_ARC` in a build configuration while the tree is mostly manual, and in
particular never in `Frameworks/AIUtilities/xcconfigs/Base.xcconfig`, which is the project level base
of AIUtilities.xcodeproj and would take the Spotlight importer with it.

## Prove it took

The compiler accepts a file with no retains and no releases either way, so a build that succeeds
proves nothing. Two checks that do:

```sh
# the object file must reference the ARC runtime
nm -u build/Adium.build/Debug/Adium.build/Objects-normal/arm64/<name>.o | grep objc_storeStrong

# and a release put back must now be refused
# expect: "ARC forbids explicit message send of 'release'"
```

A neighbouring manual file references no `objc_storeStrong` at all, which makes the first check a
comparison rather than a guess.

The window between removing the retains and adding the flag is the dangerous one: in that state the
file compiles, and every object it used to own is left dangling. Do both in one commit.

## Reviewing the diff

- **Read every deleted retain.** Some of them were bookkeeping and some were documenting an
  intention. `[self retain]` before an asynchronous callback, a retain that is given back on two of
  three exits, an object kept alive for a C function to find later: none of these survive
  translation, and the compiler will say so. If a retain disappears without complaint, ask what it
  was for before letting it go.
- **`grep` the diff for `[self retain]` and `[self release]`.** An object that owns itself has no
  owner, and reference counting will free it at the end of the statement that made it. It needs an
  owner invented before the file can move. See `AIFloater.h` for one written down.
- **Look at what `-dealloc` did.** Reference counting frees the object ivars for you, so a dealloc
  that only released ivars can go. One that unregisters an observer, tears down a connection or
  tells something else it is going away must stay, minus the releases.
- **`@property (assign)` on an object** becomes unsafe unretained, which is not what most of them
  meant. Where the ivar was retained by hand behind an `assign` property, the property is wrong and
  should become `strong`; letting the migrator delete the retains instead leaves it dangling.
- **`NSCell` subclasses.** `-copyWithZone:` on a cell is a memberwise copy, so the copy already
  holds an unretained duplicate of every ivar. Assigning to one under reference counting releases
  that duplicate out from under the original. Those ivars need `__unsafe_unretained`.
- **A `__block` object variable is not retained under manual counting and is retained under
  automatic.** Where `__block __typeof__(self) bself = self` was the trick for getting into a block
  without an ownership cycle, it silently becomes the cycle.

## What stays behind

Two subsystems are meant to remain manual, and their build files should say so with an explicit
`-fno-objc-arc` rather than relying on the absence of a flag:

- **Plugins/Purple Service.** Objects are handed to libpurple through `void *ui_data` under three
  different ownership conventions that coexist on purpose. Reference counting cannot see any of
  them, and confusing two is a double free.
- **Plugins/Bonjour, including libezv.** `-dealloc` hands a dying object across into the account
  layer. The moment the receiving side counts references it retains something that is already going
  away, which ends the process.

## Order

Leaves first: plugins with no C interop, then AIUtilities, then AutoHyperlinks, then the
application, then Frameworks/Adium. Each file should be shippable on its own, and worth running for
a few days before the next one, because nothing in this tree tests object lifetime.

## The one that looks like bookkeeping and is not

A window controller that ends `-windowWillClose:` with

```objc
sharedInstance = nil;
[self autorelease];
```

is not doing two things, it is doing one. Under manual counting the file static holds no reference,
so the first line frees nothing; the second hands the object to the pool, and it dies at the end of
the run loop turn. That delay is the whole scheme, because `-windowWillClose:` runs from inside
`-[NSWindow close]`, which keeps talking to the controller as the window's delegate and window
controller after the notification returns.

Counted automatically, the static owns what it points at. Deleting the autorelease and keeping the
assignment turns a deferred free into a synchronous one, in the middle of the teardown, and the
retain count balances perfectly so nothing is diagnosed. Keep the deferral:

```objc
CFAutorelease(CFBridgingRetain(sharedInstance));
sharedInstance = nil;
```

Measured: a bare `static = nil` deallocates before the next statement, and the pair above survives
until the pool drains, which is exactly what the autorelease did.

## The one file left alone

`Frameworks/AIUtilities/Source/ISO8601DateFormatter.m` stays manual, and on purpose.

It is compiled by two targets from one file reference: the framework and the Spotlight importer. The
source is shared, so it cannot be counted for one and not the other, and converting it converts a
second binary along with it. Inside, the parser reads a `const unichar *` obtained from
`-cStringUsingEncoding:` and walks it for four hundred lines. That is exactly the shape where a
shortened lifetime produces a fault that appears sometimes, on some inputs, with no diagnostic
anywhere.

Eighty-six of the framework's eighty-seven files are converted. This one is worth less than the
afternoon it would take to be sure about.

## Batch 1 of the main project (this session)

113 files: the five small plugins entire, and Frameworks/Adium/Source except the twelve files a
concurrent deprecation pass was editing. Converted by thirteen agents working the rules above,
verified by a green build, `nm -u` spot checks, the reinserted-release positive control, and an
adversarial review pass per cluster. Ten files were skipped for patterns the playbook did not
cover; all ten were then converted by hand, and the solutions are now precedents: a struct member
goes __unsafe_unretained when it only borrows (AISortController); C arrays of object pointers are
strong of themselves under ARC, and inside an NSCell copy the laundering cast clears the memberwise
slot before the counted store (AIListGroupMockieCell); a dealloc swizzle survives by asking
sel_registerName for what the compiler refuses to spell (AIToolbar); a reference crossing into
libpurple as a ui_handle travels via CFBridgingRetain and comes home through CFRelease
(AdiumAuthorization); an integer smuggled through object_setIvar keeps the plain setter, whose
unsafe store is the only correct treatment of a non-pointer, while READING one back must bypass
the id-typed runtime call entirely, via ivar_getOffset, because under ARC every id a function
returns is retained for the statement, integer disguise or not, and retaining 25 was a crash
on every account connect before this sentence existed (ESObjectWithProperties); a controller
that owns itself while shown gets a static set as its ownership home with CF deferrals at every
exit (ESTextAndButtonsWindowController, after ESPresetNameSheetController); a self-retain until a
notification arrives becomes CFRetain at registration and CFAutorelease in the handler
(DCJoinChatViewController); and a sheet's modalDelegate:[self retain] simply becomes the completion
handler's capture of self (AIMessageViewController).

What the review caught, so the next batch looks for it up front:

- **The compiler had already said it.** Three `__unsafe_unretained` ivars assigned a fresh
  alloc/init result were flagged by `-Warc-unsafe-retained-assign` in the build log, as warnings.
  After every batch, grep the log for `-Warc-` before believing a green build.
- **Fast enumeration over a copy.** A getter that answers `[ivar copy]` used to park that copy in
  the autorelease pool; under ARC the copy dies before `countByEnumeratingWithState:` returns and
  the caller walks freed memory. Enumerate the ivar, and know the price: mutation inside the loop
  now aborts, so callers that remove while walking need `[self containedObjects]` snapshots.
- **The nib loader's unowned +1.** `ai_loadNibNamed:` hands every top level object a reference
  that belongs to nobody, by design. MRR takers consumed it with a bare `release` that the
  conversion rightly deleted, so the consumption must come back as
  `CFRelease((__bridge CFTypeRef)view)` at the load site, and only there: panes that build their
  view in code never had the extra reference.
- **The silent twin of the compiler warning.** Assigning a METHOD RESULT to an
  `__unsafe_unretained` ivar produces no warning at all, and it is fine only while the callee is
  MRR: its real autorelease parks the object in the pool. The moment the callee is ARC too, the
  return-value handshake sees the unsafe assignment as `objc_unsafeClaimAutoreleasedReturnValue`
  and frees the object on the spot; the settings-form panes crashed exactly there, on factory
  calls one line above the use. After a batch, sweep every ARC file for `unsafeIvar = [` - the
  alloc/init variant warns, this one does not.
- **Anchor outlets.** Controls that hold IBOutlets to their own window or to sibling views must
  keep them `__unsafe_unretained`, or the nib connection becomes a cycle that keeps whole panels
  alive.

## Where this stands, and what waits

149 of 494 files in the main project count automatically; AIUtilities is done but for its
deliberate exception. The two remaining rounds are Source/ (235 files) and the Purple service
(69 files, where C callbacks and void* contexts cross the language boundary on nearly every
page). Both are deliberately parked: the next step is a stretch of ordinary use of what is
already converted, not more conversion. When a round is picked up again, run it like batch one:
clusters, the playbook, central flag-flipping, the compiler pass, then the adversarial review,
whose finding classes are all recorded above.
