#!/bin/bash
#
# Point a freshly built libwhatsmeow at the libraries Adium ships, and install it as the .so the
# project copies into the bundle.
#
# cmake records whatever pkg-config found, which is the dylibs under Dependencies/build plus
# Homebrew, as absolute paths. Loading the plugin then pulls second copies of glib, libpurple and
# gettext into a process that already has the bundled ones. Two copies of a library mean two sets of
# global tables, and the symptoms are never a clean error: the prpl registers itself into one table
# while libpurple reads the other. The vendored binary in PurplePlugins/ has always carried
# @executable_path names; this restores them after a rebuild.
#
# libintl matters as much as the rest even though nothing here calls gettext directly. Adium sets
# libpurple's output encoding once, with bind_textdomain_codeset, and that setting lives inside
# whichever libintl the caller was linked against. A plugin holding a different copy translates
# through a table where the encoding was never set, and its German comes out transliterated to
# ASCII. Everything in the bundle has to agree on libintl.framework.
#
# Usage: relink_for_bundle.sh [path-to-built-libwhatsmeow.dylib]
#        Defaults to the usual cmake output location.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DYLIB="${1:-$ROOT/Dependencies/source/purple-gowhatsapp/build/glue/libwhatsmeow.dylib}"
DEST="$ROOT/PurplePlugins/libwhatsmeow.so"

[ -f "$DYLIB" ] || { echo "not a file: $DYLIB" >&2; exit 1; }

cp "$DYLIB" "$DEST"
SO="$DEST"

FW='@executable_path/../Frameworks'
BUILD="$ROOT/Dependencies/build/lib"

relink() {
	local from="$1" to="$2"
	if otool -L "$SO" | grep -qF "$from"; then
		install_name_tool -change "$from" "$to" "$SO"
		echo "  $from"
		echo "    -> $to"
	fi
}

# The build-tree dylibs.
relink "$BUILD/libpurple.0.dylib"      "$FW/libpurple.framework/Versions/0/libpurple"
relink "$BUILD/libglib-2.0.0.dylib"    "$FW/libglib.framework/Versions/2.0.0/libglib"
relink "$BUILD/libgobject-2.0.0.dylib" "$FW/libgobject.framework/Versions/2.0.0/libgobject"

# Homebrew's copies of libraries Adium bundles itself.
relink /opt/homebrew/opt/gettext/lib/libintl.8.dylib            "$FW/libintl.framework/Versions/8/libintl"
relink /opt/homebrew/opt/gdk-pixbuf/lib/libgdk_pixbuf-2.0.0.dylib "$FW/libgdk_pixbuf-2.0.0.dylib"

# Anything still absolute would load a second copy of something; say so rather than ship it.
if otool -L "$SO" | tail -n +2 | grep -qE '^\s+/(Users|opt|usr/local)/'; then
	echo "WARNING: absolute paths remain:" >&2
	otool -L "$SO" | tail -n +2 | grep -E '^\s+/(Users|opt|usr/local)/' >&2
	exit 1
fi

codesign --force --sign - "$SO"
echo "signed. $(basename "$SO") now resolves everything through the bundle."
