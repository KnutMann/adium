#!/bin/bash
#
# Point a freshly built libteams.so at the libraries inside Adium.app.
#
# The plugin is linked against the build prefix, whose paths exist only on the
# machine that built it. Worse, a plugin that keeps them pulls a second copy of
# glib and of libpurple into a process that already has one, and then two
# libraries disagree about the same global state.
#
# Usage: relink_for_bundle.sh <path to libteams.so>

set -euo pipefail

PLUGIN="${1:?Usage: $0 <path to libteams.so>}"
FRAMEWORKS='@executable_path/../Frameworks'

map() {
	local from="$1" to="$2"
	local current
	current=$(otool -L "$PLUGIN" | awk -v n="$from" '$1 ~ n { print $1; exit }')

	if [ -n "$current" ]; then
		install_name_tool -change "$current" "$to" "$PLUGIN"
	fi
}

map 'libpurple\.0\.dylib'      "$FRAMEWORKS/libpurple.framework/Versions/0/libpurple"
map 'libglib-2\.0\.0\.dylib'   "$FRAMEWORKS/libglib.framework/Versions/2.0.0/libglib"
map 'libgio-2\.0\.0\.dylib'    "$FRAMEWORKS/libgio.framework/Versions/2.0.0/libgio"
map 'libgobject-2\.0\.0\.dylib' "$FRAMEWORKS/libgobject.framework/Versions/2.0.0/libgobject"
map 'libjson-glib-1\.0\.0\.dylib' "$FRAMEWORKS/libjson-glib.framework/Versions/1.0.0/libjson-glib"
map 'libintl\.8\.dylib'        "$FRAMEWORKS/libintl.framework/Versions/8/libintl"

# Nothing may point outside the bundle afterwards. A single absolute path is
# enough to load a second glib, and the symptoms of that are not obvious.
if otool -L "$PLUGIN" | tail -n +2 | grep -vE '@executable_path|@rpath|^\s*/usr/lib/|^\s*/System/' | grep -q .; then
	echo "Still pointing outside the bundle:" >&2
	otool -L "$PLUGIN" | tail -n +2 | grep -vE '@executable_path|@rpath|/usr/lib/|/System/' >&2
	exit 1
fi

codesign --force --sign - "$PLUGIN"
echo "Relinked $(basename "$PLUGIN")"
