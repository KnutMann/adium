#!/bin/bash
# Builds Adium from a fresh checkout, verifies it, and installs it:
#
#   ./install.sh
#
# Almost everything the application needs beyond Xcode is checked into this
# repository: the frameworks under Frameworks/ and the protocol plug-ins under
# PurplePlugins/ are prebuilt arm64 binaries. Three things are not, and this
# script fetches them first through Dependencies/fetch.sh: the MMTabBarView
# submodule, the WebRTC framework a call needs, and picomemo, the cryptographic
# half of OMEMO. Then it verifies those artifacts, builds the application,
# verifies the result, and puts it into /Applications.
#
# The verification is not decoration. A protocol plug-in can be broken in a
# way nothing reports: linked against a stray copy of libpurple it loads
# cleanly, registers its protocol where the application never looks, and the
# only symptom is an account that will not connect. Utilities/
# verify-purple-plugins.sh asks the bundle's own libpurple whether every
# plug-in's protocol actually arrives, before and after the build.
#
# Options:
#   --install      install to /Applications without asking
#   --build-only   build and verify, do not touch /Applications
#   --debug        build the Debug configuration instead of Release
#   --force        replace /Applications/Adium.app even if it is a symlink
#                  (a symlink there usually means a developer setup pointing
#                  at their build directory; refusing protects it)
#   --rebuild-dependencies
#                  build libpurple, glib, libotr, opus and the other bundled
#                  libraries from source first, instead of using the prebuilt
#                  binaries in the repository. Needs a Homebrew toolchain
#                  (autoconf, automake, libtool, pkg-config) and takes the
#                  better part of an hour.
#
# Given neither --install nor --build-only it asks, and only if there is a
# terminal to ask at. Without one it builds and verifies and installs nothing,
# because a build script waiting for an answer nobody can give is worse than
# one that does too little.
#
# ./bootstrap.sh is this script with --build-only.

set -eu
cd "$(dirname "$0")"
REPO="$PWD"

CONFIGURATION="${CONFIGURATION:-Release}"
INSTALL=ask
FORCE=no
REBUILD_DEPENDENCIES=no
for option in "$@"; do
	case "$option" in
		--debug) CONFIGURATION=Debug ;;
		--build-only) INSTALL=no ;;
		--install) INSTALL=yes ;;
		--force) FORCE=yes ;;
		--rebuild-dependencies) REBUILD_DEPENDENCIES=yes ;;
		-h|-help|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown option: $option (try --help)"; exit 2 ;;
	esac
done

case "$CONFIGURATION" in
	Release|Debug) ;;
	*) echo "CONFIGURATION must be Release or Debug, not $CONFIGURATION"; exit 2 ;;
esac
SCHEME="Adium - $CONFIGURATION"

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

# Asked before anything is built, so the answer is given once and the rest runs
# unattended. Both -t tests matter: a pipeline can leave one of the two open.
if [ "$INSTALL" = ask ]; then
	if [ -t 0 ] && [ -t 1 ]; then
		printf 'Install to /Applications when the build is done? [Y/n] '
		# An answer, an empty line, or nothing at all. The last is not the same
		# as the second: a closed input is nobody agreeing, so it installs
		# nothing, while a person pressing return has agreed.
		if read -r answer; then
			case "$answer" in
				[nN]*) INSTALL=no ;;
				*)     INSTALL=yes ;;
			esac
		else
			echo
			INSTALL=no
		fi
	else
		INSTALL=no
		echo "Nothing here to ask at, so building only. Pass --install to install."
	fi
fi

step "Preflight"
if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find xcodebuild >/dev/null 2>&1; then
	echo "Xcode (or its command line tools) is required: https://developer.apple.com/xcode/"
	exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
	echo "This build targets Apple Silicon; the bundled frameworks are arm64 only."
	exit 1
fi
echo "Xcode: $(xcodebuild -version | head -1), machine: $(uname -m), configuration: $CONFIGURATION"

# The prebuilt libraries are in the repository, so a file missing here means a
# checkout that did not finish, not a machine that is missing something. Said
# now, by name, instead of three minutes later as a compiler error about a
# header nobody has heard of.
missing=""
for needed in \
	Frameworks/opus/include/opus/opus.h \
	Frameworks/opus/include/ogg/ogg.h \
	Frameworks/opus/lib/libopus.a \
	Frameworks/opus/lib/libogg.a \
	Frameworks/libpurple.framework/Headers/libpurple.h
do
	[ -e "$REPO/$needed" ] || missing="$missing  $needed\n"
done
if [ -n "$missing" ]; then
	echo "These files belong to the repository but are not in this checkout:"
	printf "$missing"
	echo "Run 'git status' and 'git pull' in $REPO, then try again."
	exit 1
fi

step "Fetching what is not in the repository"
"$REPO/Dependencies/fetch.sh"

if [ "$REBUILD_DEPENDENCIES" = yes ]; then
	# Everything under Frameworks/ is a prebuilt binary; these two steps make
	# those binaries again from pinned sources and overwrite them in place.
	step "Rebuilding libpurple, glib, libotr and friends from source"
	( cd Dependencies && ./build.sh && ./copy_frameworks.sh )

	step "Rebuilding libogg, libopus and libopusfile from source"
	Dependencies/opus/build-opus.sh
fi

step "Verifying the checked-in protocol plug-ins"
"$REPO/Utilities/verify-purple-plugins.sh"

step "Building Adium ($CONFIGURATION)"
# One xcodebuild for everything: the application target depends on AIUtilities,
# MMTabBarView, AutoHyperlinks, Adium.framework, AdiumLibpurple and the
# Spotlight importer, so Xcode builds them in the right order by itself. This
# script used to have a twin that built three of them separately and staged the
# products by hand, which is how a fix for the signing fallback below reached
# one script and not the other.
#
# The project settings name a certificate that exists only on the machine this
# fork is developed on. Without it, sign ad hoc: the application then runs here
# but cannot be handed to anybody else, which is what a build from source is for.
SIGNING_OVERRIDES=()
# Guarded with [@]+ below, because bash 3.2, which is the bash on every Mac,
# calls an empty array an unbound variable under set -u.
if ! security find-identity -p codesigning -v 2>/dev/null | grep -q '"Adium Local Signing"'; then
	echo "No 'Adium Local Signing' certificate in this keychain; signing ad hoc"
	SIGNING_OVERRIDES=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
fi

# Finder metadata left on a bundle from an earlier run breaks codesign, which
# calls it detritus and refuses.
xattr -cr "$REPO/build/$CONFIGURATION/Adium.app" 2>/dev/null || true

# The status of xcodebuild, not of the grep it is piped through. Piped, the
# shell reports the last command in the pipe, and grep is happy to have found
# the line that says the build failed. This script used to read that as success
# and carry on to install an application it had not built.
# The destination named outright. A scheme offers two, this Mac and "Any Mac",
# and asked to choose, xcodebuild takes the first and says so in a warning that
# reads as if something went wrong. Nothing did: this Mac is the one meant.
set -o pipefail
if ! xcodebuild -project Adium.xcodeproj -scheme "$SCHEME" \
	-destination "platform=macOS,arch=arm64" \
	SYMROOT="$REPO/build" OBJROOT="$REPO/build/Intermediates" \
	${SIGNING_OVERRIDES[@]+"${SIGNING_OVERRIDES[@]}"} \
	build | grep -E "^\*\* BUILD|error:"
then
	echo "Build failed; run xcodebuild yourself for the full log."
	exit 1
fi
set +o pipefail

APP="$REPO/build/$CONFIGURATION/Adium.app"
[ -d "$APP" ] || { echo "FAIL: no application at $APP"; exit 1; }

step "Verifying the built application"
"$REPO/Utilities/verify-purple-plugins.sh" --app "$APP"

if [ "$INSTALL" = no ]; then
	step "Done (build only)"
	echo "The verified application is at: $APP"
	echo "To install it as well: ./install.sh --install"
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
