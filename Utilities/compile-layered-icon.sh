#!/bin/bash
# Compile a layered icon package into the Assets.car a bundle ships, and nothing else.
#
# Run by a build phase of the Adium and XtrasCreator targets, before signing. actool,
# Xcode 26's asset compiler, turns a .icon package into an asset catalogue that holds
# the layered icon, named after the package, which macOS 26 draws when the bundle's
# Info.plist names it in CFBundleIconName. actool also writes a flattened .icns and a
# partial Info.plist pointing CFBundleIconFile at it; both are left behind on purpose.
# The bundle keeps its own .icns, the free-standing duck, for the systems that cannot
# read the layered form. Which of the two a macOS before 26 shows when it finds both
# is recorded in Decisions/application-icon.md.
#
# Xcode must not be allowed to compile the package itself: a .icon in a Copy Bundle
# Resources phase makes it do exactly what this script avoids.
#
#   Utilities/compile-layered-icon.sh <Name.icon> <Resources directory> [deployment target]
set -euo pipefail

ICON=${1:?usage: compile-layered-icon.sh <Name.icon> <Resources directory> [deployment target]}
RES=${2:?usage: compile-layered-icon.sh <Name.icon> <Resources directory> [deployment target]}
TARGET=${3:-13.0}
NAME=$(basename "${ICON%.icon}")

[ -f "$ICON/icon.json" ] || { echo "error: $ICON is not a layered icon package" >&2; exit 1; }
[ -d "$RES" ] || { echo "error: no resources directory at $RES" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
if ! out=$(xcrun actool "$ICON" --compile "$WORK" --platform macosx --minimum-deployment-target "$TARGET" \
		--app-icon "$NAME" --output-partial-info-plist "$WORK/partial.plist" 2>&1); then
	echo "$out" >&2
	echo "error: actool could not compile $ICON; the layered icon needs Xcode 26 or newer" >&2
	exit 1
fi
[ -f "$WORK/Assets.car" ] || { echo "$out" >&2; echo "error: actool wrote no Assets.car for $ICON" >&2; exit 1; }
/bin/cp "$WORK/Assets.car" "$RES/Assets.car"
echo "layered icon $NAME compiled into $(basename "$(dirname "$RES")")/$(basename "$RES")/Assets.car"
