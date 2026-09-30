#!/bin/bash -eu
#
# Put what build.sh produced where Adium.xcodeproj looks for it.
#
# build.sh writes into Dependencies/Frameworks: one .subproj directory per framework,
# plus a dylibs directory for the seven libraries that travel as bare dylibs. The
# application reads ../Frameworks, one level up. This is the copy between the two.

ROOTDIR=$(pwd)
if ! expr "$ROOTDIR" : '.*/Dependencies$' &> /dev/null; then
	echo "Please run this script from the Dependencies directory." >&2
	exit 1
fi

ADIUM="$(cd "$(dirname "$0")/.." && pwd)"

if ! compgen -G "$ROOTDIR/Frameworks/*.subproj/*.framework" > /dev/null; then
	echo "No frameworks in $ROOTDIR/Frameworks. Run build.sh first." >&2
	exit 1
fi

echo "Copying frameworks"
# The destination goes first. cp -Rf merges into a framework that is already there, and a
# library whose number has moved then keeps both: libffi went from 7 to 8, and a merge
# would leave Versions/7 sitting beside Versions/8 with nothing naming it any more. The
# stale one is not merely clutter, it is a second copy of the library stamped for
# whatever macOS built it, which is exactly what this build exists to stop shipping.
for framework in "$ROOTDIR"/Frameworks/*.subproj/*.framework; do
	rm -rf "$ADIUM/Frameworks/$(basename "$framework")"
done
cp -Rf "$ROOTDIR"/Frameworks/*.subproj/*.framework "$ADIUM/Frameworks/"

# The bare dylibs, if this was a libpurple build rather than an OTR one. They are
# staged with the names they carry inside the bundle already; see stage_bundled_dylibs.
if compgen -G "$ROOTDIR/Frameworks/dylibs/*.dylib" > /dev/null; then
	echo "Copying the bundled dylibs"
	cp -f "$ROOTDIR"/Frameworks/dylibs/*.dylib "$ADIUM/Frameworks/"
fi

# There used to be three rm lines here for libgstreamer plug-ins that "cause problems in
# gst_init". Nothing has built gstreamer since the video and voice phase was commented
# out, so under -eu those lines removed files that were not there and stopped the script
# on its fourth line. They are gone rather than guarded: a guard would keep alive the
# suggestion that gstreamer is still part of this.

echo "Cleaning the Adium built products"

# The application copies these in at build time. Leaving the old ones behind means a
# rebuild can pick up a library this script has just replaced.
if [ -d "$ADIUM/build" ]; then
	rm -rf "$ADIUM"/build/*/AdiumLibpurple.framework
	rm -rf "$ADIUM"/build/*/*/Adium.app/Contents/Frameworks/lib*
fi

echo "Done - now build Adium"
