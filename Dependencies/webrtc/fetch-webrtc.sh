#!/bin/zsh
# Fetch the prebuilt WebRTC framework the XMPP calls work links against.
#
# The framework is not committed: the macOS slice alone is tens of megabytes
# and Google rebuilds it monthly. This pins one release by checksum instead,
# the way BeagleIM handles the same framework. stasel/WebRTC repackages the
# official Chromium builds (BSD license) as an xcframework with a macOS
# arm64+x86_64 slice; the loopback probe in Testing/webrtc proves the pinned
# build works end to end on this machine.
set -e
cd "$(dirname "$0")"

VERSION="153.0.0"
ARCHIVE="WebRTC-M153.xcframework.zip"
URL="https://github.com/stasel/WebRTC/releases/download/$VERSION/$ARCHIVE"
CHECKSUM="3e3a8946f27510133e3feed04d05fa23505bbe366e977620503bfc7986c2b78f"

if [ -d WebRTC.xcframework ]; then
	echo "WebRTC.xcframework liegt schon da"
	exit 0
fi

curl -sL -o "$ARCHIVE" "$URL"
echo "$CHECKSUM  $ARCHIVE" | shasum -a 256 -c -
unzip -qo "$ARCHIVE"
rm "$ARCHIVE"
echo "WebRTC.xcframework ($VERSION) bereit"
