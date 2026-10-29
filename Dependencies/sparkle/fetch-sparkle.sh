#!/bin/zsh
# Fetch the Sparkle 2 framework the updater is built on, and its tools.
#
# Sparkle is not committed: it is sixteen megabytes of somebody else's signed
# release, and this pins one of them by checksum instead, the way WebRTC is
# pinned beside it. The tarball carries the framework, which the application
# links and re-signs on copy, and the command line tools: generate_keys, which
# makes the EdDSA key pair once, and generate_appcast, which the release
# workflow runs over the packaged files so that the application can find the
# next version. Sparkle 1.17, which Adium 1.5 shipped, was x86_64 only and left
# in August 2026; this is the rewritten second generation, arm64 and able to
# sign its own feed.
set -e
cd "$(dirname "$0")"
VERSION="2.10.1"
ARCHIVE="Sparkle-$VERSION.tar.xz"
URL="https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/$ARCHIVE"
CHECKSUM="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
if [ -d Sparkle.framework ] && [ "$(plutil -extract CFBundleShortVersionString raw -o - Sparkle.framework/Resources/Info.plist 2>/dev/null)" = "$VERSION" ]; then
	echo "Sparkle.framework $VERSION is already here"
	exit 0
fi
rm -rf Sparkle.framework bin LICENSE
curl -sL -o "$ARCHIVE" "$URL"
echo "$CHECKSUM  $ARCHIVE" | shasum -a 256 -c -
# Only the framework, the tools and the licence; the test application and the
# symbol files in the tarball are not needed here.
tar -xJf "$ARCHIVE" Sparkle.framework bin LICENSE
rm "$ARCHIVE"
echo "Sparkle.framework ($VERSION) bereit"
