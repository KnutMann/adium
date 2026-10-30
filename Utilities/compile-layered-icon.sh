#!/bin/bash
# Compile a layered icon package into the asset catalogue a bundle ships, and commit that.
#
# actool, Xcode 26's asset compiler, turns a .icon package into a catalogue holding the
# layered icon, named after the package, which macOS 26 draws when the bundle's Info.plist
# names it in CFBundleIconName. It renders the icon stack only on a macOS 26 host: on the
# macOS 15 machine continuous integration runs on, its helper process dies (measured 30
# October 2026, "The tool closed the connection (AssetCatalogAgent-AssetRuntime)"). A build
# must not depend on the machine it runs on, so the catalogue is compiled here, once, by a
# person on macOS 26, and committed as Assets.car, a resource of the target like any other.
# A resource rather than the output of a script phase, because Xcode signs the bundle again
# for a changed resource and not for a file a script wrote into it: done the other way, the
# creator's seal went stale after the first incremental build (30 October 2026). Run this
# again after make-layered-icon.sh changed the package.
#
# actool also writes a flattened .icns and a partial Info.plist pointing CFBundleIconFile at
# it; both are left behind on purpose. The bundle keeps its own .icns, the free-standing duck,
# for the systems that cannot read the layered form. Which of the two a macOS before 26 shows
# when it finds both is recorded in Decisions/application-icon.md.
#
# Xcode must not be allowed to compile the package itself: a .icon in a Copy Bundle Resources
# phase makes it do exactly what this script avoids.
#
#   Utilities/compile-layered-icon.sh <Name.icon> <output.car>
#
# The two in the tree:
#   Utilities/compile-layered-icon.sh Resources/Adium.icon Resources/Assets.car
#   Utilities/compile-layered-icon.sh Other/XtrasCreator/XtrasCreator.icon Other/XtrasCreator/Assets.car
set -euo pipefail

ICON=${1:?usage: compile-layered-icon.sh <Name.icon> <output.car>}
OUT=${2:?usage: compile-layered-icon.sh <Name.icon> <output.car>}
NAME=$(basename "${ICON%.icon}")

[ -f "$ICON/icon.json" ] || { echo "error: $ICON is not a layered icon package" >&2; exit 1; }
case "$OUT" in *.car) ;; *) echo "error: the output is a .car file" >&2; exit 1 ;; esac
if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]; then
	echo "error: actool renders a layered icon only on macOS 26 or newer; this is $(sw_vers -productVersion)" >&2
	exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
if ! out=$(xcrun actool "$ICON" --compile "$WORK" --platform macosx --minimum-deployment-target 13.0 \
		--app-icon "$NAME" --output-partial-info-plist "$WORK/partial.plist" 2>&1); then
	echo "$out" >&2
	echo "error: actool could not compile $ICON" >&2
	exit 1
fi
[ -f "$WORK/Assets.car" ] || { echo "$out" >&2; echo "error: actool wrote no Assets.car for $ICON" >&2; exit 1; }
/bin/cp "$WORK/Assets.car" "$OUT"
echo "==> $OUT ($(du -h "$OUT" | cut -f1)) from $ICON"
