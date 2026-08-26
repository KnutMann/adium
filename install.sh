#!/bin/bash
# Builds and installs Adium from a fresh checkout, in one command:
#
#   ./install.sh
#
# Everything the application needs beyond Xcode is checked into this
# repository: the frameworks under Frameworks/ and the protocol plug-ins under
# PurplePlugins/ are prebuilt arm64 binaries. This script verifies those
# artifacts, builds the application, verifies the result, and puts it into
# /Applications. Rebuilding the dependencies themselves from source is the
# separate, maintainer-only Dependencies/build.sh.
#
# The verification is not decoration. A protocol plug-in can be broken in a
# way nothing reports: linked against a stray copy of libpurple it loads
# cleanly, registers its protocol where the application never looks, and the
# only symptom is an account that will not connect. Utilities/
# verify-purple-plugins.sh asks the bundle's own libpurple whether every
# plug-in's protocol actually arrives, before and after the build.
#
# Options:
#   --debug        build the Debug configuration instead of Release
#   --build-only   build and verify, do not touch /Applications
#   --force        replace /Applications/Adium.app even if it is a symlink
#                  (a symlink there usually means a developer setup pointing
#                  at their build directory; refusing protects it)

set -eu
cd "$(dirname "$0")"
REPO="$PWD"

CONFIGURATION=Release
SCHEME="Adium - Release"
INSTALL=yes
FORCE=no
for option in "$@"; do
	case "$option" in
		--debug) CONFIGURATION=Debug; SCHEME="Adium - Debug" ;;
		--build-only) INSTALL=no ;;
		--force) FORCE=yes ;;
		-h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown option: $option (try --help)"; exit 2 ;;
	esac
done

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

step "Preflight"
if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find xcodebuild >/dev/null 2>&1; then
	echo "Xcode (or its command line tools) is required: https://developer.apple.com/xcode/"
	exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
	echo "This build targets Apple Silicon; the bundled frameworks are arm64 only."
	exit 1
fi
echo "Xcode: $(xcodebuild -version | head -1), machine: $(uname -m)"

step "Verifying the checked-in protocol plug-ins"
"$REPO/Utilities/verify-purple-plugins.sh"

step "Building Adium ($CONFIGURATION)"
xcodebuild -project Adium.xcodeproj -scheme "$SCHEME" \
	SYMROOT="$REPO/build" OBJROOT="$REPO/build/Intermediates" \
	build | grep -E "^\*\* BUILD|error:" || { echo "Build failed; run xcodebuild yourself for the full log."; exit 1; }

APP="$REPO/build/$CONFIGURATION/Adium.app"
[ -d "$APP" ] || { echo "FAIL: no application at $APP"; exit 1; }

step "Verifying the built application"
"$REPO/Utilities/verify-purple-plugins.sh" --app "$APP"

if [ "$INSTALL" = "no" ]; then
	step "Done (build only)"
	echo "The verified application is at: $APP"
	exit 0
fi

step "Installing to /Applications"
DEST="/Applications/Adium.app"
if [ -L "$DEST" ] && [ "$FORCE" = "no" ]; then
	echo "$DEST is a symlink (a developer setup?); leaving it alone."
	echo "The verified application is at: $APP"
	echo "Pass --force to replace the symlink with a real installation."
	exit 0
fi
rm -rf "$DEST"
ditto "$APP" "$DEST"

step "Done"
echo "Installed: $DEST"
