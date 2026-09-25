#!/bin/zsh
# Fetch and build libogg and libopus, the codec voice notes are recorded in.
#
# Adium records a voice note as Opus in an Ogg container, which needs two small Xiph
# libraries. They are linked statically into the application (see OTHER_LDFLAGS in
# Frameworks/AIUtilities/xcconfigs/Adium.xcconfig), so nothing of them has to be shipped
# beside it.
#
# Why this script exists: both libraries were built by hand when voice notes were written and
# never added here, while the build kept linking them out of Dependencies/build, which is not
# checked in. On the machine they were built on everything was fine; a fresh clone failed at
#
#     Source/AIOpusEncoder.m:18:10 'opus.h' file not found
#
# which says nothing about a download being what is missing. Reported from the outside as
# KnutMann/adium#5.
#
# The tarballs are pinned by checksum. The checksums are the ones the Xiph download server
# served on 25.09.2026; they are here so that what is downloaded tomorrow is what was
# downloaded then, not as a claim that they were checked against a second source.

set -e
cd "$(dirname "$0")/.."

DEPENDENCIES="$PWD"
BUILD="$DEPENDENCIES/build"
SOURCE="$DEPENDENCIES/source"

if [ -f "$BUILD/lib/libopus.a" ] && [ -f "$BUILD/lib/libogg.a" ] &&
   [ -f "$BUILD/include/opus/opus.h" ] && [ -f "$BUILD/include/ogg/ogg.h" ]; then
	echo "libogg und libopus liegen schon gebaut da"
	exit 0
fi

mkdir -p "$SOURCE"

# The same floor the application is built with. Without it the compiler stamps whatever the
# machine happens to be running, and the linker then warns once per object file that it is
# joining something built for a newer macOS than it is linking for.
export MACOSX_DEPLOYMENT_TARGET="$(sed -n 's/^MACOSX_DEPLOYMENT_TARGET *= *//p' \
	"$DEPENDENCIES/../Frameworks/AIUtilities/xcconfigs/Base.xcconfig" | head -1)"
: "${MACOSX_DEPLOYMENT_TARGET:=12.0}"
echo "gebaut fuer macOS $MACOSX_DEPLOYMENT_TARGET aufwaerts"

# Ogg first: opus is built against it.
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
		echo "       die Pruefsumme in diesem Skript nachziehen, wenn die Fassung absichtlich wechselt." >&2
		exit 1
	fi

	[ -d "$tree" ] || tar -xzf "$archive" -C "$SOURCE"

	echo "==> $name $version wird gebaut"
	(cd "$tree" && ./configure --prefix="$BUILD" "$@" >/dev/null && make -j"$(sysctl -n hw.ncpu)" >/dev/null && make install >/dev/null)
}

build_xiph libogg 1.3.6 \
	https://downloads.xiph.org/releases/ogg/libogg-1.3.6.tar.gz \
	83e6704730683d004d20e21b8f7f55dcb3383cdf84c0daedf30bde175f774638 \
	--disable-shared --enable-static

build_xiph opus 1.5.2 \
	https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz \
	65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1 \
	--disable-shared --enable-static --disable-doc --disable-extra-programs

echo "libogg und libopus gebaut: $(lipo -info "$BUILD/lib/libopus.a" | sed 's/.*: //')"
