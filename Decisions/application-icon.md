# The application never writes into its own bundle; its icon is chosen when it is built

**Decision.** Adium does not change its own bundle at run time, not even to
stamp the chosen dock icon onto it. The dock tile follows the chosen set while
Adium runs; the icon shown while it is closed is the one the bundle was built
with, and that one can be chosen at build time with `install.sh --icon=NAME`,
which puts the set's `ApplicationIcon.png`, as an `.icns`, over `Adium.icns`
before the bundle is signed.

Since 30 October 2026 the shipped icon has two forms. `Resources/Adium.icns`
is the free-standing duck as it always was. `Resources/Adium.icon` is Icon
Composer's layered package, the form macOS 26 draws properly: a portrait of
the duck, face in the middle, on a tile in the grass green of the disk image's
picture pulled towards Apple's light glass. `Utilities/compile-layered-icon.sh`
turns the package into `Resources/Assets.car`, committed and copied into the
bundle by the resources phase like any other resource, and named by
`CFBundleIconName` in the Info.plist. XtrasCreator carries the same pair, made
from the owner's painting duck. A chosen icon switches the layered form off,
catalogue and key, so that the choice shows on every system.

**Why the second form.** macOS 26 puts every classic `.icns` with a free shape
into a grey rounded tile and shrinks it there; the Finder, the Dock and the
disk image window all show the tile. There is no switch against it short of a
Finder custom icon, which this page rules out above. A layered icon is drawn
large on a tile whose colour is ours. "Only the duck, no tile" is not a thing
macOS 26 offers any application, so the tile was chosen to sit quietly: the
owner picked the tone from five on a comparison sheet and the crop from two,
on 30 October 2026. The package is written by
`Utilities/make-layered-icon.sh`, which holds the tone and the crop, so the
look is reproducible from the pictures under `Other/Artwork`.

**What the second form costs.** Two compiled catalogues in the repository,
2.7 and 4.1 MB, because actool renders the layered icon only on a macOS 26
host: on the macOS 15 runner its helper process died ("The tool closed the
connection", 30 October 2026), and a build must not depend on the machine it
runs on. The catalogue is a resource of the target and not the output of a
script phase, because Xcode signs a bundle again for a changed resource and
not for a file a script wrote into it: done the other way, the creator's seal
went stale on the first incremental build and the helper no longer verified
(30 October 2026). The package must never reach a Copy Bundle Resources phase: Xcode 26
would compile it itself, write a flattened `Adium.icns` over the free-standing
one and point `CFBundleIconFile` at it. actool writes that flattened icon and
seven flattened sizes into the catalogue
whatever it is told (the switch that once suppressed them does nothing in
Xcode 26.1 and later), so a macOS before 26 finds both the classic icon and a
flattened tile, and it takes the tile: measured on 30 October 2026 on the
continuous integration runner, macOS 15.7.9, whose workflow draws both icons
the way that system shows them and keeps the pictures as the `icon-renders`
artifact. `CFBundleIconName` wins over `CFBundleIconFile` there. Three ways
around it were tried the same day and lead nowhere: a classic icon set of the
free-standing duck compiled beside the package under the same name is
ignored by actool 26.6, which renders its own fallback regardless; thinning
the catalogue with `assetutil` for any deployment target removes nothing;
and the catalogue cannot be edited. So the free-standing duck is now what a
system before 26 shows only when the bundle carries no catalogue, which is
the case for a build with a chosen icon. Shown the pictures, the owner chose
the tile on every system over no layered icon at all (30 October 2026): with
Liquid Glass on 26 and flat before, it is the same icon everywhere, and the
grey system tile on 26 would have been the worse duck where most people see
it. The free-standing duck lives on as the disk image's volume icon and in
the dock icon sets. The Adium layer is cut from the 512 pixel icon, scaled
2.24 times, because no larger rendering of the duck exists; the creator's
comes from a 1254 pixel painting. And the disk
image's picture, drawn for a free-standing duck lifted by three hands, now
has a tile standing on the grass on every system.

**Why.** Adium 1.x set the chosen dock icon as a Finder custom icon on its own
bundle with `-[NSWorkspace setIcon:forFile:]`, on every change of the set and
on the first launch after an upgrade. That is the only way an icon can show on
a closed application without rebuilding it, and it was removed on 15 August
2026 (`1ddec379c`) for what it leaves behind: an `Icon\r` file carrying a
resource fork and a flag in the bundle's Finder information. Measured on 25
October 2026 on a copy of the Release build: before, `codesign --verify --deep
--strict` passes; after one `setIcon:`, it says "resource fork, Finder
information, or similar detritus not allowed", `spctl --assess` rejects the
bundle, and codesign will not sign over it. For a build from source that costs
the next build; for a signed and notarised release it is the kind of change
that can make macOS report the application as damaged, right after the user
picked an icon. The feature and the release path exclude each other, and the
release path wins.

A build-time choice has none of that: the icon is part of the sealed bundle,
and the Dock, the Finder and Launchpad show it because it is the bundle's icon,
not a decoration on top. It is what the "Pick the Application Icon Before
Signing" phase of the Adium target does, right before the phase that strips
any Finder custom icon a bundle picked up by hand.

**What it costs.** The closed application's icon follows the build, not the
preference: choosing another set in the preferences changes the dock tile at
once and the bundle's icon at the next build with `--icon`. People who do not
build from source get the shipped icon, which with a signed release is the
only honest answer anyway. And Launch Services caches application icons, so
the Dock may show the previous one until its tile is made anew or the Dock is
restarted. Issue #16 is the request this page answers.

**Verified** 25 October 2026: the measurement above, and `install.sh
--icon="Adiumy Red" --build-only` produces a bundle whose `Adium.icns` differs
from the shipped one and still passes `codesign --verify --deep --strict`.
