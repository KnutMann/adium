#!/bin/bash
#
# Put a freshly built libpurple into Frameworks/libpurple.framework, which is what Adium links and
# ships.
#
# The full dependency build regenerates every framework, which is a long job and overwrites more
# than one wants after a one file change. This does the same thing for libpurple alone: autotools
# records absolute paths to whatever it linked against, and the framework needs @executable_path
# names instead, or the bundle loads second copies of glib and gettext alongside its own.
#
# Usage: install_libpurple_framework.sh
#        Run after "make -C libpurple install-libLTLIBRARIES" in Dependencies/source/libpurple.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD="$ROOT/Dependencies/build/lib"
DEST="$ROOT/Frameworks/libpurple.framework/Versions/0/libpurple"

[ -f "$BUILD/libpurple.0.dylib" ] || { echo "no built libpurple in $BUILD" >&2; exit 1; }
[ -f "$DEST" ] || { echo "no framework at $DEST" >&2; exit 1; }

FW='@executable_path/../Frameworks'

cp "$BUILD/libpurple.0.dylib" "$DEST"
install_name_tool -id "$FW/libpurple.framework/Versions/0/libpurple" "$DEST"

relink() {
	local from="$1" to="$2"
	if otool -L "$DEST" | grep -qF "$from"; then
		install_name_tool -change "$from" "$to" "$DEST"
		echo "  $(basename "$from") -> $to"
	fi
}

relink "$BUILD/libgobject-2.0.0.dylib"   "$FW/libgobject.framework/Versions/2.0.0/libgobject"
relink "$BUILD/libgmodule-2.0.0.dylib"   "$FW/libgmodule.framework/Versions/2.0.0/libgmodule"
relink "$BUILD/libgthread-2.0.0.dylib"   "$FW/libgthread.framework/Versions/2.0.0/libgthread"
relink "$BUILD/libglib-2.0.0.dylib"      "$FW/libglib.framework/Versions/2.0.0/libglib"
relink "$BUILD/libjson-glib-1.0.0.dylib" "$FW/libjson-glib.framework/Versions/1.0.0/libjson-glib"
relink /opt/homebrew/opt/gettext/lib/libintl.8.dylib "$FW/libintl.framework/Versions/8/libintl"

if otool -L "$DEST" | tail -n +2 | grep -qE '^\s+/(Users|opt|usr/local)/'; then
	echo "WARNING: absolute paths remain:" >&2
	otool -L "$DEST" | tail -n +2 | grep -E '^\s+/(Users|opt|usr/local)/' >&2
	exit 1
fi

codesign --force --sign - "$DEST"
echo "installed. libpurple.framework now carries the freshly built library."
