#!/bin/bash
# Package a built Adium.app for people to download: a zip and a disk image.
#
# Both, because they answer different questions. The disk image is what somebody
# downloading Adium expects: mount it, drag the application onto the Applications
# folder beside it, done. The zip is what the updater installs from, and it is
# what anybody scripting an install would rather have.
#
# Neither is signed here. Signing and notarising belong to the release workflow,
# and this script deliberately knows nothing about them.
#
# The disk image opens on a picture, Release/Artwork/dmgBackground.png, with
# Adium on the left and the Applications folder on the right, and the mounted
# volume wears the application's icon. The Finder reads such a layout from a
# .DS_Store file; Utilities/make-dmg-layout.sh writes that file once, without
# a Finder, and it is committed as Release/Artwork/DS_Store. Two things follow
# from how the Finder finds the picture, through an alias that names the volume
# and the file: the volume is always called "Adium", whatever the version, since
# a volume of another name opens on a white window (measured 29 October 2026),
# and the picture goes in under the name the layout was written with, at both
# resolutions in one TIFF. The flag that makes the Finder look for the volume's
# icon lives in the volume root's Finder information, which a folder cannot
# carry into an image, so the image is made writable first, flagged, and then
# compressed.
#
#   Utilities/package-release.sh <Adium.app> <version> [output directory]
set -euo pipefail

APP=${1:?usage: package-release.sh <Adium.app> <version> [output directory]}
VERSION=${2:?usage: package-release.sh <Adium.app> <version> [output directory]}
OUT=${3:-dist}
ART=$(cd "$(dirname "$0")/.." && pwd)/Release/Artwork

[ -d "$APP" ] || { echo "no application at $APP" >&2; exit 1; }
for f in "$ART/dmgBackground.png" "$ART/DS_Store"; do
	[ -f "$f" ] || { echo "the disk image's layout is incomplete: no $f" >&2; exit 1; }
done

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
RW="$STAGE.rw.dmg"
MOUNT="$STAGE.mnt"
# The detach in the trap fails whenever the image was detached in the normal
# course, and under set -e a failing command in the trap becomes the script's
# exit status: the first run on GitHub's runner produced both files and exited 1.
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$STAGE" "$RW" "$MOUNT"' EXIT
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"

# The picture at one and at two points per pixel, made from the 2x picture the
# way make-dmg-layout.sh made it; then the layout, and the volume's icon.
read -r W H < <(sips -g pixelWidth -g pixelHeight "$ART/dmgBackground.png" | awk '/pixel/ {printf "%s ", $2} END {print ""}')
sips -z $((H / 2)) $((W / 2)) "$ART/dmgBackground.png" --out "$STAGE/background.png" > /dev/null
if ! out=$(tiffutil -cathidpicheck "$STAGE/background.png" "$ART/dmgBackground.png" -out "$STAGE/.background.tiff" 2>&1); then
	echo "$out" >&2; exit 1
fi
rm "$STAGE/background.png"
cp "$ART/DS_Store" "$STAGE/.DS_Store"
cp "$APP/Contents/Resources/Adium.icns" "$STAGE/.VolumeIcon.icns"

hdiutil create -quiet -srcfolder "$STAGE" -volname "Adium" -fs HFS+ -format UDRW "$RW"
mkdir -p "$MOUNT"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$MOUNT" "$RW"
SetFile -a C "$MOUNT"
hdiutil detach "$MOUNT" -quiet
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"

echo
for f in "$ZIP" "$DMG"; do
	printf "%-40s %7s  %s\n" "$(basename "$f")" \
		"$(du -h "$f" | cut -f1)" "$(shasum -a 256 "$f" | cut -d' ' -f1)"
done
