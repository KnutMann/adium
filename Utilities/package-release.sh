#!/bin/bash
# Package a built Adium.app for people to download: a zip and a disk image.
#
# Both, because they answer different questions. The disk image is what somebody
# downloading Adium expects: mount it, drag the application onto the Applications
# folder beside it, done. The zip is what an updater wants later, and it is what
# anybody scripting an install would rather have.
#
# Neither is signed here. Signing and notarising need a paid Apple membership and
# belong in the release workflow once there is one; this script deliberately knows
# nothing about them, so that adding them later changes the workflow and not this.
#
# The disk image is plain: no background picture, no arranged icons. The old
# Release/ machinery did that with an AppleScript that talks to the Finder, which
# needs a logged-in desktop and therefore cannot run where releases are built.
# A pre-arranged .DS_Store could bring the layout back without the Finder, and
# Release/RightDS_Store is one, but it was arranged for a window from 2013.
#
#   Utilities/package-release.sh <Adium.app> <version> [output directory]
set -euo pipefail

APP=${1:?usage: package-release.sh <Adium.app> <version> [output directory]}
VERSION=${2:?usage: package-release.sh <Adium.app> <version> [output directory]}
OUT=${3:-dist}

[ -d "$APP" ] || { echo "no application at $APP" >&2; exit 1; }

# Refuse to package something Gatekeeper will refuse to open. This caught a real
# one the first time it ran: an empty Versions/7 left inside libffi.framework made
# the whole bundle fail to verify.
if ! codesign --verify "$APP" 2>/dev/null; then
	echo "the application does not verify, so there is no point packaging it:" >&2
	codesign --verify "$APP" 2>&1 | sed 's/^/  /' >&2
	exit 1
fi
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

ZIP="$OUT/Adium-$VERSION.zip"
DMG="$OUT/Adium-$VERSION.dmg"
rm -f "$ZIP" "$DMG"

# ditto rather than zip, because a bundle carries resource forks and extended
# attributes that zip drops, and a dropped one is a signature that no longer
# verifies.
echo "==> $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> $DMG"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -srcfolder "$STAGE" -volname "Adium $VERSION" \
	-fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"

echo
for f in "$ZIP" "$DMG"; do
	printf "%-40s %7s  %s\n" "$(basename "$f")" \
		"$(du -h "$f" | cut -f1)" "$(shasum -a 256 "$f" | cut -d' ' -f1)"
done
