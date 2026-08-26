#!/bin/bash
# Rebuilds the WhatsApp protocol plug-in from Dependencies/source/purple-gowhatsapp
# and ships it into PurplePlugins/, verified.
#
# The plug-in's own CMake already does the two things that history proved
# essential: it rewrites every libpurple/glib reference onto the app bundle's
# frameworks (a plug-in bound to build-tree paths loads a SECOND libpurple and
# registers its protocol where Adium never looks - silently), and it applies a
# real ad-hoc signature (Xcode's copy phase strips linker-signed binaries, and
# a stripped Go runtime does not survive). This script exists so nobody has to
# remember the steps around it, and so the result is verified before it lands.
#
# Requires: Go, CMake, pkg-config (Homebrew is fine for the TOOLS; nothing of
# it may end up referenced by the shipped binary - the verifier enforces that).

set -eu
cd "$(dirname "$0")"
REPO="$(cd .. && pwd)"
SRC="$REPO/Dependencies/source/purple-gowhatsapp"

[ -d "$SRC/build" ] || { echo "No configured build at $SRC/build - run cmake there first (see its README)."; exit 1; }

echo "== building"
cmake --build "$SRC/build"

echo "== shipping"
cp "$SRC/build/glue/libwhatsmeow.dylib" "$REPO/PurplePlugins/libwhatsmeow.so"

echo "== verifying"
exec "$REPO/Utilities/verify-purple-plugins.sh"
