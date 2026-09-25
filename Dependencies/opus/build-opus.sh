#!/bin/zsh
# Rebuild libogg and libopus, the codec voice notes are recorded in.
#
# Adium records a voice note as Opus in an Ogg container. Both libraries are linked statically
# into the application (see OTHER_LDFLAGS in Frameworks/AIUtilities/xcconfigs/Adium.xcconfig),
# so nothing of them is shipped beside it.
#
# The built archives and headers are IN the repository, under Frameworks/opus, the way
# libpurple, glib and the rest are. This script is therefore not part of a normal build; it is
# how those files are made, for an upgrade or a rebuild from source. It writes exactly where
# the build reads.
#
# The tarballs are pinned by checksum. The checksums are the ones the Xiph download server
# served on 25.09.2026; they are here so that what is downloaded tomorrow is what was
# downloaded then, not as a claim that they were checked against a second source.
#
# Needs a working autotools toolchain, which a plain Xcode installation does not have.

set -e
cd "$(dirname "$0")/../.."

ROOT="$PWD"
TARGET="$ROOT/Frameworks/opus"
STAGE="$ROOT/Dependencies/build"
SOURCE="$ROOT/Dependencies/source"

mkdir -p "$SOURCE" "$TARGET/lib" "$TARGET/include"

# The same floor the application is built with. Without it the compiler stamps whatever the
# machine happens to be running, and the linker then warns once per object file that it is
# joining something built for a newer macOS than it is linking for.
export MACOSX_DEPLOYMENT_TARGET="$(sed -n 's/^MACOSX_DEPLOYMENT_TARGET *= *//p' \
	"$ROOT/Frameworks/AIUtilities/xcconfigs/Base.xcconfig" | head -1)"
: "${MACOSX_DEPLOYMENT_TARGET:=12.0}"
echo "gebaut fuer macOS $MACOSX_DEPLOYMENT_TARGET aufwaerts"

build_xiph () {
	local name="$1" version="$2" url="$3" checksum="$4"
	shift 4

	local archive="$SOURCE/$name-$version.tar.gz"
	local tree="$SOURCE/$name-$version"

	if [ ! -f "$archive" ]; then
		echo "==> $name $version wird geladen"
		curl -sfL -o "$archive.part" "$url"
		mv "$archive.part" "$archive"
	fi

	local got="$(shasum -a 256 "$archive" | awk '{print $1}')"
	if [ "$got" != "$checksum" ]; then
		echo "error: $name-$version.tar.gz hat die Pruefsumme $got, erwartet war $checksum." >&2
		echo "       Das Archiv wurde nicht ausgepackt. Loeschen und erneut versuchen, oder" >&2
		echo "       die Pruefsumme hier nachziehen, wenn die Fassung absichtlich wechselt." >&2
		exit 1
	fi

	rm -rf "$tree"
	tar -xzf "$archive" -C "$SOURCE"

	echo "==> $name $version wird gebaut"
	(cd "$tree" && ./configure --prefix="$STAGE" "$@" >/dev/null && make -j"$(sysctl -n hw.ncpu)" >/dev/null && make install >/dev/null)
}

# Ogg first: opus is built against it.
build_xiph libogg 1.3.6 \
	https://downloads.xiph.org/releases/ogg/libogg-1.3.6.tar.gz \
	83e6704730683d004d20e21b8f7f55dcb3383cdf84c0daedf30bde175f774638 \
	--disable-shared --enable-static

build_xiph opus 1.5.2 \
	https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz \
	65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1 \
	--disable-shared --enable-static --disable-doc --disable-extra-programs

# Only what the build reads: the two archives and the headers. The libtool .la files and the
# pkg-config data describe a machine that is not the one this will be built on.
rm -rf "$TARGET/include/ogg" "$TARGET/include/opus"
cp "$STAGE/lib/libogg.a" "$STAGE/lib/libopus.a" "$TARGET/lib/"
cp -R "$STAGE/include/ogg" "$STAGE/include/opus" "$TARGET/include/"

echo "nach Frameworks/opus gelegt: $(lipo -info "$TARGET/lib/libopus.a" | sed 's/.*: //'), $(du -sh "$TARGET" | awk '{print $1}')"
