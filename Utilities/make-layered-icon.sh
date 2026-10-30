#!/bin/bash
# Write a layered application icon, Icon Composer's .icon package, from a duck picture.
#
# macOS 26 draws an application's classic .icns small on a grey tile. The form it
# draws properly is this one: a package of icon.json and a layer picture, which the
# system renders itself. The look was decided on 30 October 2026 and is fixed here:
# a tile in the grass green of the disk image's picture pulled towards Apple's light
# glass (seven parts grass, three parts glass, lighter at the top), and the duck as
# a portrait, face in the middle, cut as tight as the head allows with two percent
# headroom and shifted five percent down, so that it stands large on the tile. The
# cut is made by make-layered-icon.m beside this script, from the eyes down.
#
# The package is committed; this is run again when the picture or the look changes.
# Utilities/compile-layered-icon.sh turns the package into the Assets.car a build
# ships, and the classic .icns stays beside it for older systems.
#
#   Utilities/make-layered-icon.sh <picture.png> <Name.icon>
#
# The two in the tree:
#   Utilities/make-layered-icon.sh Other/Artwork/Application\ Icon/Adium.png Resources/Adium.icon
#   Utilities/make-layered-icon.sh Other/Artwork/XtrasCreator/XtrasCreator.png Other/XtrasCreator/XtrasCreator.icon
set -euo pipefail

PNG=${1:?usage: make-layered-icon.sh <picture.png> <Name.icon>}
OUT=${2:?usage: make-layered-icon.sh <picture.png> <Name.icon>}
case "$OUT" in *.icon) ;; *) echo "$OUT: the package is named Name.icon" >&2; exit 1 ;; esac
[ -f "$PNG" ] || { echo "no picture at $PNG" >&2; exit 1; }

HEADROOM=0.02
SHIFT=0.05
CANVAS=1024
# sRGB, top and bottom of the tile.
FILL_TOP="srgb:0.70180,0.79880,0.70830,1.00000"
FILL_BOTTOM="srgb:0.59650,0.72000,0.60830,1.00000"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
clang -fobjc-arc -framework Cocoa "$(dirname "$0")/make-layered-icon.m" -o "$WORK/cut"

rm -rf "$OUT"
mkdir -p "$OUT/Assets"
"$WORK/cut" "$PNG" "$HEADROOM" "$SHIFT" "$CANVAS" "$OUT/Assets/duck.png"

# One group, one layer, no glass effects on the drawing itself: the duck carries its own
# shading, and the system's specular highlight on top of it looked like a second light.
cat > "$OUT/icon.json" <<EOF
{
  "fill" : {
    "linear-gradient" : [
      "$FILL_TOP",
      "$FILL_BOTTOM"
    ],
    "orientation" : {
      "start" : { "x" : 0.5, "y" : 1.0 },
      "stop" : { "x" : 0.5, "y" : 0.0 }
    }
  },
  "groups" : [
    {
      "name" : "Duck",
      "layers" : [
        {
          "name" : "duck",
          "image-name" : "duck.png"
        }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : false, "value" : 0.5 },
      "specular" : false
    }
  ],
  "supported-platforms" : {
    "circles" : [ "watchOS" ],
    "squares" : "shared"
  }
}
EOF
echo "==> $OUT ($(du -sh "$OUT" | cut -f1))"
