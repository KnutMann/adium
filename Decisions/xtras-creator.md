# XtrasCreator is built with Adium and ships inside it

**Decision.** The companion application for making xtras is a target the
Adium target depends on. The one xcodebuild that builds the application builds
it too, and a copy phase puts it into the bundle at
`Contents/Helpers/XtrasCreator.app`, signed as nested code with the same
identity, hardened runtime and timestamp as everything around it. There is no
separate download of it.

**Why.** The upstream project kept the creator of 2005 as its own Xcode
project under `Other/`, never a dependency of the application and never
packaged by the release Makefile; it was a download of its own, and a thread
on the developers' list in March 2007 argued for exactly that separation, so
that Adium itself stays an end user's program. That worked in its day: the
many xtras on adiumxtras.com say that the people who wanted to make one
managed, separate download or not. What has changed is Adium. It is a niche
program now, and the people who still run it stand much closer to the people
who make things for it, so keeping the maker's tool out of the user's download
protects a distinction that has lost its weight. The owner's reason for the
move is as plain as that: the creator is in the tool, and there is nothing
else to download. It sits beside the shipped xtras, which have always been
inside the bundle under `Contents/Resources`. One build, one signature, one
notarisation, one download.

Three things were turned down. A second release asset: two artefacts to sign,
notarise, version and keep in step, one of which nobody downloads. Putting it
under `Contents/Resources`: codesign seals what is under Resources as data,
not as nested code, and Apple's places for nested code are Frameworks,
PlugIns, XPCServices, Helpers, Library and MacOS; Helpers is where a helper
application goes and it is just as visible to "Show Package Contents". And a
menu item that only says where to download it, which is the old arrangement
with an extra step.

**What it costs.** About a megabyte in every copy and every update.

A second application with document types inside the bundle: Launch Services
lists it as a handler for every xtra type it declares, and an xtra that opens
in the creator instead of installing into Adium would be a regression. So each
of the creator's twelve types carries `LSHandlerRank` = `Alternate`, while
Adium's fifteen carry no rank, which means Default, and Default outranks
Alternate. A double-clicked xtra still installs; "Open With" on an xtra now
also offers the creator, which is right.

The creator inherits the hardened runtime from the build settings
`install.sh --sign` passes to every target. Its sources use no JavaScriptCore,
AppleScript, NSTask or dlopen (checked by grep on 30 October 2026), so it
needs no entitlement for that.

`install.sh` refuses a build in which the helper is missing or does not verify,
so continuous integration catches a broken embedding on every push.

Xcode validates an embedded application against the parent's certificate, so
the creator's project names the same identity as Adium's targets, "Adium
Local Signing", and the overrides `install.sh` passes replace both at once:
ad hoc on any other machine, Developer ID for a release. The first Debug build
from the project alone, with the creator still signing ad hoc on its own,
stopped at exactly that check (30 October 2026). The Debug
build builds and embeds it as well, so the first Debug build after this change
is longer than usual. Xcode's archive action would stage two applications,
because the creator does not set `SKIP_INSTALL`; nothing here uses that
action.

The creator's own tests still build a runner with clang; they write under the
repository's `build/XtrasCreator`, not beside the sources, since the creator
no longer has a build folder of its own.

**How it is reached.** The Xtras settings card, the place where xtras are
managed in this fork, has a row for it under the website and the folder rows:
"XtrasCreator", with an Open button, and a second line saying what it is. The
row is built only when the helper is actually in the bundle, so a build
without it shows nothing rather than a button that does nothing. There is no
menu item: somebody who wants to make an xtra is already looking at that card,
and the creator is a program of its own, not a window of Adium's (decided
30 October 2026). The old creator had no icon, in the tree or in its history;
this one has Adiumy with a paintbrush and an apron, drawn by the owner. The
picture lives under `Other/Artwork/XtrasCreator`, and
`Utilities/make-app-icon.sh` turns it into the `.icns` committed beside the
creator's Info.plist, the same sips and iconutil recipe install.sh uses for
Adium's own icon. Beside the `.icns` sits `XtrasCreator.icon`, the layered
form macOS 26 draws, made and compiled the same way as Adium's; that pair and
its costs are on application-icon.md.

**Verified** 30 October 2026, on the first signed Release build with the
creator inside (`./install.sh --build-only --sign="Developer ID Application"`,
a full build since the intermediates had just been cleared):
`Contents/Helpers/XtrasCreator.app` is 1.0 MB and arm64; `codesign -dv` on it
reports `flags=0x10000(runtime)`, the team identifier and a timestamp;
`codesign --verify --deep --strict` on Adium.app says "satisfies its
Designated Requirement"; the built Info.plist carries twelve `Alternate`
ranks; `install.sh` printed "XtrasCreator.app in Contents/Helpers verifies".
Launched from inside the bundle (`open -g -j`), the creator ran under the
hardened runtime and quit cleanly on request, with no crash report.
