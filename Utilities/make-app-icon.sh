#!/bin/bash
# Make an application icon, an .icns, from one square picture.
#
# The picture is the largest rendering, at least 1024 pixels on a side, on a
# transparent background. sips scales it to the ten sizes an icon set holds and
# iconutil packs them; install.sh makes Adium's own icon from a dock icon set the
# same way. This is that recipe for a picture that lives in the tree, so the
# result can be committed and made again whenever the picture changes.
#
#   Utilities/make-app-icon.sh <picture.png> <output.icns>
#
# XtrasCreator's icon is made with
#   Utilities/make-app-icon.sh "Other/Artwork/XtrasCreator/XtrasCreator.png" Other/XtrasCreator/XtrasCreator.icns
set -euo pipefail

PNG=${1:?usage: make-app-icon.sh <picture.png> <output.icns>}
OUT=${2:?usage: make-app-icon.sh <picture.png> <output.icns>}

[ -f "$PNG" ] || { echo "no picture at $PNG" >&2; exit 1; }
read -r W H < <(sips -g pixelWidth -g pixelHeight "$PNG" | awk '/pixel/ {printf "%s ", $2} END {print ""}')
[ "$W" = "$H" ] || { echo "$PNG is $W x $H; an icon's picture is square" >&2; exit 1; }
[ "$W" -ge 1024 ] || { echo "$PNG is $W pixels on a side; the largest size in an icon is 1024" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# iconutil wants the folder named after the icon, with this suffix.
SET="$WORK/$(basename "${OUT%.icns}").iconset"
mkdir "$SET"
for entry in 16x16:16 16x16@2x:32 32x32:32 32x32@2x:64 128x128:128 128x128@2x:256 \
             256x256:256 256x256@2x:512 512x512:512 512x512@2x:1024; do
	sips -z "${entry#*:}" "${entry#*:}" "$PNG" --out "$SET/icon_${entry%:*}.png" > /dev/null
done
iconutil -c icns -o "$OUT" "$SET"
echo "==> $OUT ($(du -h "$OUT" | cut -f1)) from $PNG at $W px"
