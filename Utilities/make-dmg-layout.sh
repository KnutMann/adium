#!/bin/bash
# Write the release disk image's Finder layout: Other/Artwork/Disk Image/DS_Store.
#
# The disk image opens on a picture with Adium on the left and the Applications
# folder on the right. The Finder keeps such a layout in a .DS_Store file, and
# Adium 1.x wrote that file by driving the Finder from an AppleScript, which
# needs somebody logged in at a screen. This writes it without a Finder:
# dmgbuild, a Python tool that knows the file format, builds a throwaway image
# with the layout, and the .DS_Store is copied out of it. The result is
# committed under a name the Finder does not overwrite, so package-release.sh
# and the release workflow need neither Python nor the network. Run this again
# when the picture's size or the positions below change; it takes a minute and
# fetches dmgbuild once, into a virtual environment it throws away.
#
# The picture is dmgBackground.png in the same folder, next to its Photoshop
# source, drawn at twice the window's size: 1536 x 1024 pixels for a window of
# 768 x 512 points. The Finder is given a TIFF holding both resolutions.
# package-release.sh makes that TIFF the same way and under the same name,
# because the layout finds it by that name.
#
#   Utilities/make-dmg-layout.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ART="Other/Artwork/Disk Image"
PNG="$ART/dmgBackground.png"
OUT="$ART/DS_Store"
DMGBUILD_VERSION=1.6.7

[ -f "$PNG" ] || { echo "no picture at $PNG" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'hdiutil detach "$WORK/mnt" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

read -r W H < <(sips -g pixelWidth -g pixelHeight "$PNG" | awk '/pixel/ {printf "%s ", $2} END {print ""}')
if [ $((W % 2)) -ne 0 ] || [ $((H % 2)) -ne 0 ]; then
	echo "$PNG is $W x $H; both sides have to be even, it is the 2x picture" >&2
	exit 1
fi
# The one-point-per-pixel copy comes from the picture itself, so there is one
# source; tiffutil refuses the pair unless the sizes are exactly two to one.
sips -z $((H / 2)) $((W / 2)) "$PNG" --out "$WORK/background.png" > /dev/null
# tiffutil reports its success on stderr, so only a failure is shown.
if ! out=$(tiffutil -cathidpicheck "$WORK/background.png" "$PNG" -out "$WORK/.background.tiff" 2>&1); then
	echo "$out" >&2; exit 1
fi

echo "==> dmgbuild $DMGBUILD_VERSION"
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet --disable-pip-version-check "dmgbuild==$DMGBUILD_VERSION"

# What the Finder is to remember. The window is the picture's size in points
# plus 28 for the title bar, which the Finder counts into the window's bounds;
# the icons stand on the grass, low enough to be whole and high enough that
# their names survive a status bar, which is a Finder-wide setting the layout
# cannot switch off. The positions are centres, in points from the top left.
mkdir "$WORK/Adium.app"
cat > "$WORK/settings.py" <<EOF
files = ["$WORK/Adium.app"]
symlinks = {"Applications": "/Applications"}
background = "$WORK/.background.tiff"
window_rect = ((200, 120), ($((W / 2)), $((H / 2 + 28))))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 14
label_pos = "bottom"
arrange_by = None
show_icon_preview = False
icon_locations = {"Adium.app": (210, 380), "Applications": (558, 380)}
format = "UDZO"
EOF

echo "==> a throwaway image, for its .DS_Store"
"$WORK/venv/bin/dmgbuild" -s "$WORK/settings.py" "Adium" "$WORK/probe.dmg" > /dev/null
mkdir "$WORK/mnt"
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$WORK/mnt" "$WORK/probe.dmg"
cp "$WORK/mnt/.DS_Store" "$OUT"
hdiutil detach "$WORK/mnt" -quiet

echo "==> $OUT"
"$WORK/venv/bin/python" - "$OUT" <<'EOF'
import sys
from ds_store import DSStore
with DSStore.open(sys.argv[1], "r") as store:
    for entry in store:
        code = entry.code.decode()
        if code == "Iloc":
            print(f"    {entry.filename} at {entry.value}")
        elif code == "icvp":
            print(f"    icon size {int(entry.value['iconSize'])}, text size {int(entry.value['textSize'])}")
        elif code == "bwsp":
            print(f"    window {entry.value['WindowBounds']}")
EOF
