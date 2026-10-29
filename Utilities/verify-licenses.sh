#!/bin/bash
# Every binary Adium ships must have a licence beside it.
#
# The failure this catches is quiet: a library is added to the bundle, nobody
# adds its licence, and the application ships somebody else's code without the
# terms it came with. That is how License.txt ended up naming one library,
# libezv, which had been gone for years while two dozen others arrived unnamed.
#
#   Utilities/verify-licenses.sh [--app <path to Adium.app>]
set -u

cd "$(dirname "$0")/.."
APP="build/Release/Adium.app"
[ "${1:-}" = "--app" ] && APP="$2"
[ -d "$APP" ] || { echo "no application at $APP"; exit 1; }

LIC="$APP/Contents/Resources/Licenses"
[ -d "$LIC" ] || { echo "FAIL: the bundle carries no Licenses folder"; exit 1; }

# Which licence file covers which shipped binary. Several libraries share one,
# because they come out of one source tree and one licence: that is why this is
# a map and not a filename comparison.
covers() {
	case "$1" in
	Adium|AdiumLibpurple|AIUtilities)            echo "SELF" ;;
	AutoHyperlinks)                              echo "AutoHyperlinks" ;;
	libcrypto.3.dylib|libssl.3.dylib)            echo "openssl" ;;
	libffi)                                      echo "libffi" ;;
	libgcrypt)                                   echo "libgcrypt" ;;
	libgpgerror)                                 echo "libgpg-error" ;;
	libgdk_pixbuf-2.0.0.dylib)                   echo "gdk-pixbuf" ;;
	libgio|libglib|libgmodule|libgobject|libgthread) echo "glib" ;;
	libintl)                                     echo "gettext-runtime" ;;
	libjpeg.8.dylib)                             echo "libjpeg-turbo" ;;
	libjson-glib)                                echo "json-glib" ;;
	libotr)                                      echo "libotr" ;;
	libpng16.16.dylib)                           echo "libpng" ;;
	libpurple)                                   echo "libpurple" ;;
	libsharpyuv.0.dylib|libwebp.7.dylib)         echo "libwebp" ;;
	MMTabBarView)                                echo "MMTabBarView" ;;
	WebRTC)                                      echo "WebRTC" ;;
	Sparkle)                                     echo "Sparkle" ;;
	libircv3.so)                                 echo "purple2-ircv3" ;;
	libmatrix.so)                                echo "purple-matrix-rs" ;;
	libsignal-presage.so)                        echo "purple-presage" ;;
	libteams.so|libteams-personal.so)            echo "purple-teams" ;;
	libtelegram-tdlib.so)                        echo "tdlib-purple" ;;
	libwhatsmeow.so)                             echo "purple-gowhatsapp" ;;
	*)                                           echo "" ;;
	esac
}

shipped=0; uncovered=0
for f in "$APP/Contents/Frameworks/"*.framework "$APP/Contents/Frameworks/"*.dylib \
         "$APP/Contents/PlugIns/purple-2/"*.so; do
	[ -e "$f" ] || continue
	name=$(basename "$f"); name=${name%.framework}
	shipped=$((shipped + 1))
	want=$(covers "$name")
	if [ -z "$want" ]; then
		echo "  UNKNOWN   $name is in the bundle and this script does not know it"
		uncovered=$((uncovered + 1))
	elif [ "$want" = "SELF" ]; then
		:
	elif [ ! -s "$LIC/$want.txt" ]; then
		echo "  MISSING   $name needs Licenses/$want.txt"
		uncovered=$((uncovered + 1))
	fi
done

echo "  $shipped shipped binaries checked against $(ls "$LIC" | wc -l | tr -d ' ') licence files"
if [ "$uncovered" -gt 0 ]; then
	echo "FAIL: $uncovered without a licence. Run Utilities/collect-licenses.sh and fix its manifest."
	exit 1
fi
echo "== every shipped binary has its licence"
