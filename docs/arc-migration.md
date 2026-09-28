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

## Round two: Source/

All 233 files of `Source/` that the application target compiles, in two commits, on a branch of
its own. The clusters were sixteen agents working the rules above; none of the files defeated
them. What recurred, beyond what batch one already recorded:

- **Back-pointers the headers had already documented.** A good many ivars carried a comment
  saying "not retained" and an `assign` property to match. Those became `__unsafe_unretained`
  rather than quietly strong, because the comment was usually right about a cycle.
- **Two methods that hand out a reference from a name the compiler cannot read as owning.**
  `+[XtrasInstaller installer]` and `-[AIAccount confirmationDialogForAccountDeletion]` are
  spelled with `objc_method_family(new)`, which is what makes the +1 legal; their callers'
  conversions depend on the attribute staying there.
- **`goto` over a strong local is an error, not a warning.** Two `goto ohno` statements in
  `AIXMLChatlogConverter` jumped past the initialisation of six locals that ARC now owns.

Three things only the flag revealed, all of them silent beforehand: a `for-in` variable being
reassigned inside its own loop; `[NSValue valueWithPointer:]` given an object pointer, which
needs the cast that says the pointer is an identity and not a reference; and a message sent to a
class the file had only ever seen forward-declared, which counting turns from a warning into an
error.

## Round three: the rest of Frameworks/Adium

Fourteen files of `Frameworks/Adium/Source` had been left behind by batch one, which skipped what a
concurrent pass was editing, and "Where this stands" below said for a month that the framework was
done. It was not; measure, do not remember. Five agents converted them in a worktree, each file was
compiled alone with the flag before the build (a script that reuses the baseline build's own compile
line with `-fobjc-arc -fsyntax-only` added; the response file in Intermediates carries the include
paths), and five more agents reviewed the diffs against every caller. What recurred and what was new:

- **A `switch` case that holds a block literal needs braces.** The block's lifetime reaches the next
  label, and the jump into it is refused ("cannot jump from switch statement to this case label").
  Twice in one afternoon, in a file of this round and in one written the same day.
- **`setReleasedWhenClosed:YES` on a window a strong ivar owns is one release too many.** The
  legacy preferences window had it; NO, and the window handed to the pool in `windowWillClose:`
  so that it outlives `-[NSWindow close]` the way the old scheme's timing did.
- **`CFAutorelease(CFBridgingRetain(nil))` traps.** `[nil autorelease]` was a no-op, so a deferral
  written as its replacement needs the guard the original never needed; measured, exit 133.
- **A redeclared `@dynamic` delegate keeps `assign` or `unsafe_unretained`.** NSTextView's own
  weak slot is the storage; the redeclaration exists to narrow the protocol type, and the compiler
  compares only copy, retain and atomic when it checks it against the superclass.
- **An object that retains itself across its own close** (the preferences controller around
  `-[NSWindow close]`) is the pool deferral again, not a new owner: the static in its caller already
  owns it and defers the same way.
- **Two cycles predate the conversion and were left.** The emoticon pack and its emoticons hold
  each other since the manual code retained both ways; an emoticon can outlive a pack reset in the
  emoticon menu's represented objects, so an unsafe back-pointer is not provably safe, and a weak one
  is barred from the header by the rule above (the escape would be a class extension in the .m). The
  emoticon menu controller's nib objects leak once per opening, as they did under manual counting;
  its unowned +1 is what keeps the menu alive while it tracks inside `init`, so consuming it at the
  load site would free the menu mid-tracking. A fix has to hold the top level objects and release
  them in a restored dealloc.

## Round four: the Purple service, the files that never touch the boundary

The service was named above as the one part meant to stay manual, and the reason still holds
for the part that hands objects to libpurple as `void *`. It does not hold for the other part.
A scan of the seventy files for `ui_data`, `ui_handle`, `user_data`, `(void *)`, `gpointer`
and bridging casts split them 41 to 29; the 41 (services, accounts that subclass the manual
CBPurpleAccount, join-chat panes, account plans, the XMPP helpers for forms, ad-hoc commands
and service discovery, four callback tables that own nothing) were converted the way rounds
two and three were, five converters and four reviewers, each converter told to stop on any
file where an object crosses after all. Four did cross and stayed manual: the request window
controllers, whose instance is the request's `ui_handle`, created at +1 by manual code and
consumed by their own `[self release]` when libpurple closes the request. The subclass
AMPurpleRequestFieldsController converted regardless, since the +1 is created and consumed
entirely in the manual code around it; its own self-retain, for the time the form is open,
became a static set with the pool deferral at the exit, as the precedents have it.

What this round taught:

- **A helper that was never freed can have a dealloc nobody ever ran.** The MAM helper
  disconnected its libpurple signal handler by a file-static handle shared by every instance;
  under manual counting the account dropped it without a release, so the dealloc never ran and
  the leak hid the bug. Counted, the old instance dies on every reconnect and its dealloc would
  have disconnected the new instance's handler and every other account's. The handle is the
  instance now. Read the dealloc of anything a conversion makes mortal for the first time.
- **A helper that holds its owner is a cycle the moment both sides count.** The same helper
  held its account in a plain ivar, retained since the helper's own conversion in an earlier
  batch, harmless only while the account never released it. Unsafe unretained, with the
  comment, and the account lets it go on disconnect like its siblings. Three more helpers
  (ad-hoc server, HTTP upload, external services) carry the same unqualified back-pointer and
  are harmless only while they stay manual; qualify them the day they convert.
- **An interior pointer returned from a method is fine.** `return [temporary UTF8String]`
  looks like it hands out a pointer into an object that dies at the return; it does not, because
  `objc_returns_inner_pointer` makes the compiler retain and autorelease the receiver, which the
  IR shows. Same lifetime the autorelease had.
- **`NSString **` out-parameters must agree across the seam.** An ARC subclass overriding a
  manual superclass's `(NSString **)` method needs `NSString * __strong *` to match the counted
  declaration further up; the bare form reads as autoreleasing under ARC.
- **A method that returns +1 under an ordinary name needs the attribute on the declaration,
  not the definition.** `authorizationRequestWithDict:` carries `ns_returns_retained` in the
  header, so the counted override inherits it and passes the manual +1 through untouched.

Found while reading, and left for their own commits: a request window the user closes is not
closed in libpurple (the adapter compares the wrong handle), so it lives until the account
disconnects, as it always did; the authorization request dictionary leaks once per answered
request in manual CBPurpleAccount; the form generator never frees what xmlnode_get_data hands
it. A join-chat pane held itself through a text field's drag delegate since the AIUtilities
round; that one is fixed here, the delegate is unsafe unretained and the pane clears it.

## Round five: the Purple service files that hand `self` to libpurple

Fifteen files whose objects cross into libpurple as `void *`, converted with the crossing made
explicit rather than avoided. Two shapes covered all of them. A signal handle or callback
user_data that the object itself disconnects on every exit is identity, `(__bridge void *)self`
both ways, no ownership at all: the consoles, the ad-hoc server, the discovery node, the HTTP
upload and the external services helpers. A request or notification `ui_handle` is a +1 that a
manual creator made with alloc/init and never released, given back through a manual callback
that casts it to `id`: the consuming `[self release]` is `CFRelease((__bridge CFTypeRef)self)`
and the consuming `[self autorelease]` is `CFAutorelease((__bridge CFTypeRef)self)`, acting on
the count outside the compiler's view exactly as the message did, with no CFBridgingRetain on
the counted side, since the creator stays manual and already hands +1. The abstract request
window controller carries the single consumption for its whole family.

What this round taught:

- **A factory returning a handle needs its family spelled out.** `+showImageRequestWithTitle:`
  lacked the `objc_method_family(new)` its siblings had; counted, it would have returned +0,
  the manual creator's pool would have drained it, and libpurple would have held a freed pointer
  until the pairing dialog closed. The attribute goes on the declaration.
- **Two consumers need two references, and the count has to be read at the consumer.** The
  notification adapter sends `purpleRequestClose` and then releases the handle a second time;
  the manual init's `return [self retain]` fed that. Counted, the init keeps a `CFRetain` of
  its own with a comment naming both consumers. The cleaner shape, one reference and one
  consumer, is a change to the manual adapter and waits for its own commit.
- **A self-retain that nothing ever gave back** (the certificate viewer) was a leak, not a
  scheme; counted, the object dies when its work is done, which also showed that its sheet has
  been unreachable since the account editor was rebuilt.
- **Read what runs inside a signal emission.** A helper freed inside libpurple's emission of the
  signal it is connected to unlinks a handler mid-walk; libpurple saves the next link before each
  callback, and newer handlers of equal priority sort before older ones, so in the one such place
  here (a replaced commands node) the freed handler has already been visited. The deferral to
  the next run loop turn stays as a guard, with a comment that says why it is only that.
- **A window let go from inside its own close** survives only while something else holds it.
  The console windows lean on the nib's unconsumed +1 and `releasedWhenClosed` NO; the line
  that lets go says so, for whoever consumes that +1 one day.

Found while reading and left for their own commits: the wrong-handle close (a user-closed
request lives until disconnect), the notification adapter's second release, the helpers that
can die off the main thread or outlive their account (HTTP upload, external services), a
discovery browser that never removes itself as a node delegate, the leaked console windows,
and "Show Server Certificate", which shows nothing. Fixed here because the file was open: the
search results window read a freed ivar after libpurple closed it.

## Where this stands, and what waits

`Source/`, `Frameworks/Adium/Source`, AIUtilities (but for its deliberate exception), AutoHyperlinks,
every plugin, and 52 of the 70 files of the Purple service count automatically. The 18 that
remain are the core, manual on purpose and marked `-fno-objc-arc`, as is the date formatter in
AIUtilities: CBPurpleAccount, SLPurpleCocoaAdapter, adiumPurpleSignals, adiumPurpleConversation,
adiumPurpleRequest, adiumPurpleNotify and the other callback tables that store objects in
`ui_data`. Those share three ownership conventions and can only go together, after an inventory
of every store into and read out of a libpurple struct. The Bonjour plugin named above as the second deliberate exception no longer exists; the
protocol is libpurple's now. Left over and not worth a round: the Spotlight importer and the two
helper tools in AIUtilities, and the unit test target.

Run any future round like the three before it: clusters, the playbook, central flag-flipping, the
compiler pass, then the adversarial review, whose finding classes are all recorded above. Two
pieces of logistics learned the hard way in round two: a fresh worktree needs
`git submodule update --init Dependencies/MMTabBarView` before it can build at all, plus the fetched
dependencies (`Dependencies/fetch.sh`, or symlinks to another checkout's WebRTC and picomemo), and
when an agent run dies in the middle, every file it did not report must be taken back with
`git checkout --`, because a file that has given up its retains without the flag owns nothing it
thinks it owns.
