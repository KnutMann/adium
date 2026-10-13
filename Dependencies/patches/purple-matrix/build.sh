#!/bin/bash
#
# Build purple-matrix for the bundle and install it as PurplePlugins/libmatrix.so.
#
# Like purple-presage this links against the libraries in Frameworks/ directly rather than through
# pkg-config: those carry @executable_path install names already, so the plugin resolves everything
# inside the bundle and no relink is needed afterwards. It also means a checkout that has never
# built Dependencies/build can still build this, which is the usual state of a machine that only
# builds Adium.
#
# The source is not in the repository. It is fetched here, pinned by commit, and checked against
# the pin: upstream calls itself unmaintained since 2022, so what builds today has to be exactly
# what was looked at. Two trees are needed:
#
#   purple-matrix   the plugin, https://github.com/matrix-org/purple-matrix
#   http-parser     the HTTP response parser it uses, https://github.com/nodejs/http-parser. That
#                   project is archived and macOS ships no copy of it, so its one source file is
#                   compiled straight into the plugin instead of becoming a bundled library.
#
# End-to-end encryption is compiled out (MATRIX_NO_E2E). Upstream only ever got as far as decrypting,
# it needs libolm, which is itself retired, and sqlite for the key store, and nothing this is built
# for (public rooms) is encrypted.
#
# Usage: build.sh

set -euo pipefail

export MACOSX_DEPLOYMENT_TARGET=13.0

ADIUM="$(cd "$(dirname "$0")/../../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCES="$ADIUM/Dependencies/source"
SRC="$SOURCES/purple-matrix"
HTTP_PARSER="$SOURCES/http-parser"
FW="$ADIUM/Frameworks"
OUT="$ADIUM/PurplePlugins/libmatrix.so"

MATRIX_URL=https://github.com/matrix-org/purple-matrix.git
MATRIX_REV=2792d4db0916ad821886de1f8de3a5e46c66ca37   # 2023-04-24, the last commit upstream
HTTP_PARSER_URL=https://github.com/nodejs/http-parser.git
HTTP_PARSER_REV=2343fd6b5214b2ded2cdcf76de2bf60903bb90cd   # v2.9.4

# Clone at the pin, or check that what is there is the pin. A tree at any other commit is an
# error rather than something to silently build, because the patch below was written for this one.
fetch() {
	local url="$1" rev="$2" dir="$3"
	if [ ! -d "$dir/.git" ]; then
		echo "fetching $(basename "$dir") at ${rev:0:7}"
		git clone -q "$url" "$dir"
		git -C "$dir" checkout -q "$rev"
	fi
	local head
	head="$(git -C "$dir" rev-parse HEAD)"
	[ "$head" = "$rev" ] || { echo "$dir is at ${head:0:7}, expected ${rev:0:7}" >&2; exit 1; }
}

mkdir -p "$SOURCES"
fetch "$MATRIX_URL" "$MATRIX_REV" "$SRC"
fetch "$HTTP_PARSER_URL" "$HTTP_PARSER_REV" "$HTTP_PARSER"

# The local changes, kept beside this script. Applying twice is not an error; a tree that has
# neither the patch nor a clean state is.
if git -C "$SRC" apply --reverse --check "$HERE/adium.patch" 2>/dev/null; then
	: # already applied
elif git -C "$SRC" apply --check "$HERE/adium.patch" 2>/dev/null; then
	git -C "$SRC" apply "$HERE/adium.patch"
	echo "applied adium.patch"
else
	echo "adium.patch fits neither the clean source nor a patched one; see git -C $SRC status" >&2
	exit 1
fi

# json-glib's headers sit at the top of the framework, while the plugin includes them as
# <json-glib/...>; http_parser.h is in its own checkout. One include directory with two links
# answers both.
INCLUDE="$(mktemp -d)"
trap 'rm -rf "$INCLUDE"' EXIT
ln -s "$FW/libjson-glib.framework/Headers" "$INCLUDE/json-glib"
ln -s "$HTTP_PARSER/http_parser.h" "$INCLUDE/http_parser.h"

CFLAGS=(
	-O2 -fPIC -Wall -Wno-deprecated-declarations
	-DPURPLE_PLUGINS -DMATRIX_NO_E2E -DGLIB_DISABLE_DEPRECATION_WARNINGS
	-I"$INCLUDE"
	-I"$FW/libpurple.framework/Headers"
	-I"$FW/libglib.framework/Headers"
	-I"$FW/libgobject.framework/Headers"
)

cd "$SRC"
rm -f ./*.o
fail=0
for c in *.c "$HTTP_PARSER/http_parser.c"; do
	if ! /usr/bin/clang "${CFLAGS[@]}" -c "$c" -o "$(basename "${c%.c}").o"; then
		fail=$((fail+1))
	fi
done
[ "$fail" -eq 0 ] || { echo "$fail source files failed to compile" >&2; exit 1; }

/usr/bin/clang -bundle -o "$OUT" ./*.o \
	"$FW/libpurple.framework/Versions/0/libpurple" \
	"$FW/libglib.framework/Versions/2.0.0/libglib" \
	"$FW/libgobject.framework/Versions/2.0.0/libgobject" \
	"$FW/libjson-glib.framework/Versions/1.0.0/libjson-glib" \
	|| { echo "link failed" >&2; exit 1; }

rm -f ./*.o
/usr/bin/strip -x "$OUT"

# Anything absolute would load a second copy of something; say so rather than ship it.
if otool -L "$OUT" | tail -n +2 | grep -qE '^[[:space:]]+/(Users|opt|usr/local)/'; then
	echo "WARNING: absolute paths remain:" >&2
	otool -L "$OUT" | tail -n +2 | grep -E '^[[:space:]]+/(Users|opt|usr/local)/' >&2
	exit 1
fi

codesign --force --sign - "$OUT"
echo "built $(basename "$OUT"): $(ls -lh "$OUT" | awk '{print $5}'), $(lipo -archs "$OUT")"
