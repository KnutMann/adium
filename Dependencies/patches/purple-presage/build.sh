#!/bin/bash
#
# Build purple-presage for the bundle and install it as PurplePlugins/libsignal-presage.so.
#
# Unlike the Telegram and WhatsApp plugins this one needs no relink afterwards, because it is linked
# against the libraries in Frameworks/ directly. Those already carry @executable_path install names,
# so the names the linker records are the ones that resolve inside the bundle, and there is no window
# in which a second copy of glib or libpurple can be pulled in.
#
# The alternative, and what an upstream build produces, is -undefined dynamic_lookup: leave every
# libpurple and glib symbol unresolved and let dyld find them in whatever is already loaded. That
# works for libpurple, which is by definition loaded before any protocol plugin, but this plugin also
# calls gdk-pixbuf to draw the linking QR code, and gdk-pixbuf is only in the process because another
# plugin happens to link it. Linking it here is the difference between that working and depending on
# which plugin loaded first.
#
# The Rust half is built separately and takes a long time. It is not rebuilt here unless its archive
# is missing:
#
#     cd Dependencies/source/purple-presage/src/rust && cargo build --release
#
# Usage: build.sh

set -uo pipefail

export MACOSX_DEPLOYMENT_TARGET=11.0

ADIUM="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="$ADIUM/Dependencies/source/purple-presage"
CDIR="$SRC/src/c"
RUSTLIB="$SRC/src/rust/target/release/libpurple_presage_backend.a"
FW="$ADIUM/Frameworks"
OUT="$ADIUM/PurplePlugins/libsignal-presage.so"

[ -d "$CDIR" ] || { echo "no source at $CDIR" >&2; exit 1; }
[ -f "$RUSTLIB" ] || { echo "no Rust archive at $RUSTLIB; run cargo build --release first" >&2; exit 1; }

export PKG_CONFIG_PATH="$ADIUM/Dependencies/build/lib/pkgconfig:/opt/homebrew/opt/glib/lib/pkgconfig:/opt/homebrew/opt/gdk-pixbuf/lib/pkgconfig:/opt/homebrew/opt/qrencode/lib/pkgconfig:/opt/homebrew/lib/pkgconfig"

# The version string upstream's CMake composes, reproduced so that what Adium reports about the
# plugin matches what an ordinary build of it would report: back-end version, commit date, revision
# count, and the commit of the presage crate it was built against.
BACKEND_VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' "$SRC/src/rust/Cargo.toml" | head -1)"
COMMIT_DATE="$(git -C "$SRC" log -1 --date=format:%Y%m%d --format=%ad)"
REVISION_COUNT="$(git -C "$SRC" rev-list --count HEAD)"
PRESAGE_COMMIT="$(sed -n 's/.*presage.*rev = "\([0-9a-f]*\)".*/\1/p' "$SRC/src/rust/Cargo.toml" | head -1)"
PLUGIN_VERSION="${BACKEND_VERSION}_${COMMIT_DATE}_${REVISION_COUNT}_${PRESAGE_COMMIT}"
echo "PLUGIN_VERSION: $PLUGIN_VERSION"

cd "$CDIR"
read -r -a CFLAGS < <(pkg-config --cflags purple glib-2.0 gdk-pixbuf-2.0 libqrencode)

rm -f ./*.o
fail=0
for c in *.c; do
	if ! /usr/bin/clang -O2 -fPIC -Wall -DPLUGIN_VERSION="\"$PLUGIN_VERSION\"" "${CFLAGS[@]}" -c "$c" -o "${c%.c}.o"; then
		fail=$((fail+1))
	fi
done
[ "$fail" -eq 0 ] || { echo "$fail source files failed to compile" >&2; exit 1; }

# qrencode is linked statically so the bundle needs no copy of it: the whole of it that this plugin
# uses is one encode call, and the archive is what Homebrew ships beside the dylib.
QRENCODE_A="$(pkg-config --variable=libdir libqrencode)/libqrencode.a"
[ -f "$QRENCODE_A" ] || { echo "no static qrencode at $QRENCODE_A" >&2; exit 1; }

/usr/bin/clang -bundle -o "$OUT" ./*.o "$RUSTLIB" "$QRENCODE_A" \
	"$FW/libpurple.framework/Versions/0/libpurple" \
	"$FW/libglib.framework/Versions/2.0.0/libglib" \
	"$FW/libgobject.framework/Versions/2.0.0/libgobject" \
	"$FW/libgdk_pixbuf-2.0.0.dylib" \
	-framework Security -framework CoreFoundation -framework SystemConfiguration \
	-framework CoreServices -framework CoreGraphics \
	-liconv -lresolv -lc++ || { echo "link failed" >&2; exit 1; }

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
