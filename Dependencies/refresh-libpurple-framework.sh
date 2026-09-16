#!/bin/zsh
# Put a freshly built libpurple into the framework the application actually loads.
#
# The jabber protocol is linked into libpurple itself rather than shipped as a plug-in, so a
# change to anything under protocols/jabber only reaches Adium once this binary is replaced.
# The full dependency build does that as one step of many and takes minutes; this does only
# that step, and takes about a second.
#
# What has to happen beyond the copy: libtool leaves absolute paths to the build directory in
# the binary, and the framework wants paths relative to the executable. Every such reference is
# rewritten here, and every rewritten target is checked to exist, because a path that is merely
# wrong produces an application that builds, launches, and cannot sign on.
#
#   Dependencies/refresh-libpurple-framework.sh
#
# Run Dependencies/build.sh for the real thing; this is the inner loop while working on the
# protocol itself.

set -e
cd "$(dirname "$0")/.."

BUILT="Dependencies/source/libpurple/libpurple/.libs/libpurple.0.dylib"
FRAMEWORK="Frameworks/libpurple.framework/Versions/0/libpurple"
SELF="@executable_path/../Frameworks/libpurple.framework/Versions/0/libpurple"

[ -f "$BUILT" ] || { echo "no freshly built libpurple at $BUILT; run make in Dependencies/source/libpurple" >&2; exit 1; }
[ -f "$FRAMEWORK" ] || { echo "no framework binary at $FRAMEWORK" >&2; exit 1; }

# Whatever the build tree currently holds is what gets installed. Comparing timestamps was
# tried and thrown out: they sit within the same second of each other and the answer came out
# differently on identical runs, which is worse than no guard at all. Build first.

cp "$BUILT" "$FRAMEWORK"
chmod u+w "$FRAMEWORK"
install_name_tool -id "$SELF" "$FRAMEWORK" 2>/dev/null

# Every absolute path that points into the build tree or into Homebrew becomes the framework
# beside us that carries the same library.
#
# The loop variable is deliberately not called "path": zsh ties $path to $PATH, so assigning a
# file name to it empties the command search path and every command after the first iteration
# is not found. The failure looks like a missing tool rather than like a shell mistake.
otool -L "$FRAMEWORK" | tail -n +2 | awk '{print $1}' \
	| grep -E "Dependencies/build/lib/|/opt/homebrew/|/usr/local/opt/" \
	| while read -r dependency; do
	file="${dependency##*/}"           # libgobject-2.0.0.dylib
	stem="${file%.dylib}"        # libgobject-2.0.0
	name="${stem%-*}"            # libgobject, and libjson-glib from libjson-glib-1.0.0
	version="${stem##*-}"        # 2.0.0

	if [ "$name" = "$stem" ]; then          # libintl.8, which separates with a dot
		name="${stem%.*}"
		version="${stem##*.}"
	fi

	target="Frameworks/$name.framework/Versions/$version/$name"
	if [ ! -f "$target" ]; then
		echo "error: $dependency would become $target, which is not in this tree" >&2
		exit 1
	fi

	install_name_tool -change "$dependency" "@executable_path/../$target" "$FRAMEWORK"
done

# Nothing absolute may be left, or the application will look outside itself at runtime.
leftover=$(otool -L "$FRAMEWORK" | tail -n +2 | awk '{print $1}' | grep -E "Dependencies/build/lib/|/opt/homebrew/|/usr/local/opt/" || true)
if [ -n "$leftover" ]; then
	echo "error: absolute paths left in the framework:" >&2
	echo "$leftover" >&2
	exit 1
fi

codesign -f -s - "$FRAMEWORK" >/dev/null 2>&1 || true
echo "libpurple.framework refreshed from the build ($(stat -f %z "$FRAMEWORK") bytes)"
