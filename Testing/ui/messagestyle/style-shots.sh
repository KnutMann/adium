#!/bin/bash -eu
#
# Photographs a message style without running Adium: a short made-up conversation,
# one-to-one and as a group chat with a topic, in the light and the dark appearance,
# at each font size asked for.
#
# The style's templates are filled the way the application fills them and loaded into
# a WKWebView through the plugin's own Template.html; what is missing is the
# application behind it (accounts, contacts, filters), which the pictures do not need.
# Made for judging a style change by eye, such as a dark appearance added in a pull
# request, before it is merged.
#
# Usage:  Testing/ui/messagestyle/style-shots.sh [style bundle] [output folder]
#
#   style bundle    an .AdiumMessageStyle; default Resources/Message Styles/Stockholm
#   output folder   default build/style-shots
#   STYLE_SHOTS_SIZES    font sizes, default "11 14"
#   STYLE_SHOTS_VARIANT  the variant, default the style's DefaultVariant
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
STYLE="${1:-$ROOT/Resources/Message Styles/Stockholm.AdiumMessageStyle}"
OUT="${2:-$ROOT/build/style-shots}"
SIZES="${STYLE_SHOTS_SIZES:-11 14}"
[ -d "$STYLE/Contents/Resources" ] || { echo "No message style at $STYLE" >&2; exit 2; }
VARIANT="${STYLE_SHOTS_VARIANT:-$(plutil -extract DefaultVariant raw -o - "$STYLE/Contents/Info.plist" 2>/dev/null || true)}"
[ -n "$VARIANT" ] || { echo "The style names no DefaultVariant; pass STYLE_SHOTS_VARIANT" >&2; exit 2; }
mkdir -p "$OUT"
BIN="$OUT/styleshots"
clang -fobjc-arc -framework Cocoa -framework WebKit -o "$BIN" "$ROOT/Testing/ui/messagestyle/main.m"
STYLE_PATH="$STYLE" STYLE_TEMPLATE="$ROOT/Plugins/WebKit Message View/Template.html" \
	STYLE_VARIANT="$VARIANT" STYLE_SIZES="$SIZES" STYLE_OUT="$OUT" "$BIN"
rm -f "$OUT/page.html"
echo
echo "The pictures are in $OUT"
