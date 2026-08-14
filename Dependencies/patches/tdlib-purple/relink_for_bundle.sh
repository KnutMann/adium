#!/bin/bash
#
# Point a freshly built libtelegram-tdlib.so at the libraries Adium ships.
#
# cmake links the plugin against whatever pkg-config found - the dylibs under Dependencies/build
# and Homebrew - and records those as absolute paths. Loading it then pulls a SECOND copy of glib
# and libpurple into a process that already has the bundled ones, and two glibs mean two sets of
# global tables: the prpl registers itself into one while libpurple reads the other. What that
# looks like from the outside is an account stuck on "Connecting" forever, with
#
#   objc[...]: Class GNotificationCenterDelegate is implemented in both .../libgio.framework/...
#              and .../Dependencies/build/lib/libgio-2.0.0.dylib
#   GLib-CRITICAL **: g_hash_table_lookup: assertion 'hash_table != NULL' failed
#   [purple:account] Invalid status ID 'available' for account ... (telegram-tdlib)
#
# in the debug log and nothing else - no login is ever attempted, so there is no error to show.
# The vendored binary in PurplePlugins/ has always carried @executable_path names; this restores
# them after a rebuild.
#
# Usage: relink_for_bundle.sh <path-to-libtelegram-tdlib.so>

set -euo pipefail

SO="${1:?usage: relink_for_bundle.sh <path-to-libtelegram-tdlib.so>}"
[ -f "$SO" ] || { echo "not a file: $SO" >&2; exit 1; }

FW='@executable_path/../Frameworks'

relink() {
	local from="$1" to="$2"
	if otool -L "$SO" | grep -qF "$from"; then
		install_name_tool -change "$from" "$to" "$SO"
		echo "  $from"
		echo "    -> $to"
	fi
}

# The build-tree dylibs. These two are the ones that actually break the plugin.
relink "$(cd "$(dirname "$0")/../../build/lib" && pwd)/libpurple.0.dylib" \
       "$FW/libpurple.framework/Versions/0/libpurple"
relink "$(cd "$(dirname "$0")/../../build/lib" && pwd)/libglib-2.0.0.dylib" \
       "$FW/libglib.framework/Versions/2.0.0/libglib"

# Homebrew's copies of libraries Adium bundles itself.
# libintl.framework. The bundle used to carry a second copy beside it, and gettext keeps its per-domain
# output encoding in whichever copy was linked, so anything linking the other one set that encoding
# where nobody would read it. There is one now; keep it that way.
relink /opt/homebrew/opt/gettext/lib/libintl.8.dylib  "$FW/libintl.framework/Versions/8/libintl"
relink /opt/homebrew/opt/webp/lib/libwebp.7.dylib     "$FW/libwebp.7.dylib"
relink /opt/homebrew/opt/libpng/lib/libpng16.16.dylib "$FW/libpng16.16.dylib"
relink /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib "$FW/libssl.3.dylib"
relink /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib "$FW/libcrypto.3.dylib"

# Anything still absolute would load a second copy of something; say so rather than ship it.
if otool -L "$SO" | tail -n +2 | grep -qE '^\s+/(Users|opt|usr/local)/'; then
	echo "WARNING: absolute paths remain:" >&2
	otool -L "$SO" | tail -n +2 | grep -E '^\s+/(Users|opt|usr/local)/' >&2
	exit 1
fi

codesign --force --sign - "$SO"
echo "signed. $(basename "$SO") now resolves everything through the bundle."
