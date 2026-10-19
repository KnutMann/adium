# Every interface file is a flat xib

**Decision.** Every interface file the application loads is a flat `.xib` in
the tree, and the build compiles it into the `.nib` that lands in the bundle.
No `.nib` directory is checked in for anything the application builds. The one
left, `LinkDriver/MainMenu.nib` in the AutoHyperlinks project, belongs to a test
driver target that no build of the application has ever produced.

Settings panes went one step further: all seventeen build their view in code
with `AISettingsFormView` and load no interface file at all. A xib is the form
for a window or a sheet; a pane that is a list of labelled rows is code.

**Why.** "Nib" names two different things. As a build product, `.nib` is what
Interface Builder's compiler emits, and that is still so. As a source format,
before Xcode 4, `.nib` was a directory holding `keyedobjects.nib`, a binary keyed
archive, beside `designable.nib`, which is XIB XML in disguise but pinned to the
system it was saved on (`SystemTarget 1060`, macOS 10.6) and liftable only by
`ibtool --upgrade`. The tree was that: 1,011 such directories, one per dialog per
language, against 9 flat xibs on 9 August 2026, when the conversion began; it
ran in eight waves over two days.

A flat xib is text. It diffs, it can be grepped for an outlet name, it can be
reviewed in a pull request, and it can be read and edited by a tool that is not
Interface Builder, which includes the agent sessions this fork is built with. A
binary archive can be opened by one program and compared by none. The comparison
of 87 interface files against another fork on 19 August 2026 was possible for
that reason alone.

**What it costs.** Three things, each found by being bitten.

Translations lived inside the localized nibs. Deleting those dropped 28
languages back to English for every migrated dialog, until `2efd5a7ec` mined
3,731 blobs out of the history and wrote 5,145 pairs back into the strings
files. Interface text goes through `AILocalizedString` and the string tables,
never into a localized interface file.

A missing interface file is not a build error. The build was green on 1 October
2026 when nine xibs were deleted as dead, and four of them were alive: their
panes override `-view`, and the first thing the override does is load the nib.
`Testing/ui/nibs/nib-audit.sh` checks every name handed to a nib loader against
the built bundle. Before deleting an interface file, run it, and ask whether a
class loads the name itself, not whether anybody mentions it.

A xib still has opinions of its own. A text colour set on an `NSTextView` in a
xib never arrives; set it in code (`ae12f2130`).

**Verified** 19 October 2026: `find . -name '*.xib'` outside `build/` is 76 and
`find . -name '*.nib'` is one directory, the LinkDriver one; neither
`build/Debug` nor `build/Release` contains a `LinkDriver.app`.
