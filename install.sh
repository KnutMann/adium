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
#   --sign=IDENTITY
#                  sign for distribution: with the named identity (a prefix such
#                  as "Developer ID Application" is enough), the hardened
#                  runtime and a trusted timestamp, which is what notarisation
#                  requires. Without it the build signs with the local
#                  certificate if there is one and ad hoc otherwise, and runs
#                  on this machine only.
#   --icon=NAME    build the application with the icon of the dock icon set
#                  NAME (one of Resources/Dock Icons, say "Adiumy Red") as its
#                  own, so the Finder and the Dock show it while Adium is
#                  closed. The icon goes into the bundle before it is signed,
#                  which is the one way it can change without breaking the
#                  signature; Adium 1.x changed it at run time and did. NAME
#                  may also be a path to a .png or an .icns.
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
ICON_CHOICE=""
SIGN_IDENTITY=""
for option in "$@"; do
	case "$option" in
		--debug) CONFIGURATION=Debug ;;
		--build-only) INSTALL=no ;;
		--install) INSTALL=yes ;;
		--force) FORCE=yes ;;
		--rebuild-dependencies) REBUILD_DEPENDENCIES=yes ;;
		--icon=*) ICON_CHOICE="${option#--icon=}" ;;
		--sign=*) SIGN_IDENTITY="${option#--sign=}" ;;
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
	# Everything under Frameworks/ is a prebuilt binary; these steps make those
	# binaries again from pinned sources and overwrite them in place.
	#
	# Two runs of build.sh, because it branches: the first builds libpurple and
	# everything the bundle loads beside it, the second builds libotr, libgcrypt
	# and libgpg-error, which are the three frameworks the first run does not
	# touch. This used to be one run without --build-otr, so the switch never
	# rebuilt the three libraries its own description named, and one without
	# --download-libpurple, which on a fresh clone walked into a source
	# directory that was not there.
	step "Rebuilding libpurple, glib and everything the bundle loads"
	( cd Dependencies && ./build.sh --download-libpurple )

	step "Rebuilding libotr and the two libraries under it"
	( cd Dependencies && ./build.sh --build-otr )

	step "Putting the rebuilt libraries where the application looks for them"
	( cd Dependencies && ./copy_frameworks.sh )

	step "Rebuilding libogg, libopus and libopusfile from source"
	Dependencies/opus/build-opus.sh
fi

step "Verifying the checked-in protocol plug-ins"
"$REPO/Utilities/verify-purple-plugins.sh"

# The application's own icon, when one was asked for. A dock icon set carries a 512 px
# ApplicationIcon.png for exactly this; sips scales it to the sizes an .icns holds and
# iconutil packs them. The result is handed to the build as ADIUM_APP_ICON, and the
# project's "Pick the Application Icon Before Signing" phase copies it over Adium.icns in
# the bundle before the signature is made. A Finder custom icon set at run time, which is
# what Adium 1.x did, is detritus to codesign --strict; an icon sealed into the bundle is
# not. The Finder and the Dock cache icons, so the Dock may show the old one until its tile
# is made anew or the Dock is restarted.
ICON_OVERRIDE=()
if [ -n "$ICON_CHOICE" ]; then
	step "Making the application icon from $ICON_CHOICE"
	case "$ICON_CHOICE" in
		*.icns) ICON_SOURCE="$ICON_CHOICE" ;;
		*.png)  ICON_SOURCE="$ICON_CHOICE" ;;
		*)      ICON_SOURCE="$REPO/Resources/Dock Icons/$ICON_CHOICE.AdiumIcon/ApplicationIcon.png" ;;
	esac
	[ -f "$ICON_SOURCE" ] || { echo "No icon at $ICON_SOURCE; the sets are: $(cd "$REPO/Resources/Dock Icons" && ls -d *.AdiumIcon | sed 's/\.AdiumIcon$//' | tr '\n' ',' | sed 's/,$//; s/,/, /g')"; exit 2; }
	ICON_DIR="$REPO/build/icon"
	rm -rf "$ICON_DIR" && mkdir -p "$ICON_DIR/Adium.iconset"
	case "$ICON_SOURCE" in
		*.icns) cp "$ICON_SOURCE" "$ICON_DIR/Adium.icns" ;;
		*)
			# Every size an .icns names, each scaled straight from the source. The @2x
			# of 512 would be 1024 and the source has 512, so it is left out, as it is
			# in the shipped icon.
			for entry in 16x16:16 16x16@2x:32 32x32:32 32x32@2x:64 128x128:128 128x128@2x:256 256x256:256 256x256@2x:512 512x512:512; do
				sips -z "${entry#*:}" "${entry#*:}" "$ICON_SOURCE" --out "$ICON_DIR/Adium.iconset/icon_${entry%:*}.png" >/dev/null
			done
			iconutil -c icns -o "$ICON_DIR/Adium.icns" "$ICON_DIR/Adium.iconset"
			;;
	esac
	[ -f "$ICON_DIR/Adium.icns" ] || { echo "iconutil produced no Adium.icns"; exit 1; }
	ICON_OVERRIDE=(ADIUM_APP_ICON="$ICON_DIR/Adium.icns")
	echo "icon: $ICON_SOURCE"
fi

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
if [ -n "$SIGN_IDENTITY" ]; then
	# Distribution. The identity is looked up in the keychain so that a prefix
	# will do, and the team comes out of its name. Manual style everywhere,
	# because two of the subprojects are set to automatic signing and refuse a
	# hand-picked identity otherwise. The hardened runtime and the timestamp
	# are what notarisation checks on every Mach-O in the bundle; the copy
	# phases re-sign what they copy with the same settings.
	line=$(security find-identity -p codesigning -v 2>/dev/null | grep -F "\"$SIGN_IDENTITY" | head -1)
	[ -n "$line" ] || { echo "No signing identity matching \"$SIGN_IDENTITY\" in this keychain."; exit 2; }
	SIGN_NAME=$(echo "$line" | sed -E 's/^[^"]*"([^"]*)".*/\1/')
	SIGN_TEAM=$(echo "$SIGN_NAME" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')
	echo "signing as $SIGN_NAME (team $SIGN_TEAM), hardened runtime, timestamped"
	SIGNING_OVERRIDES=(CODE_SIGN_IDENTITY="$SIGN_NAME" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$SIGN_TEAM" ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp)
elif ! security find-identity -p codesigning -v 2>/dev/null | grep -q '"Adium Local Signing"'; then
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
# The whole log goes to build/xcodebuild.log on the way past, because the grep
# throws away everything that is not a failure, and the warnings are worth
# counting. Continuous integration reads that file; so can you.
set -o pipefail
if ! xcodebuild -project Adium.xcodeproj -scheme "$SCHEME" \
	-destination "platform=macOS,arch=arm64" \
	SYMROOT="$REPO/build" OBJROOT="$REPO/build/Intermediates" \
	${SIGNING_OVERRIDES[@]+"${SIGNING_OVERRIDES[@]}"} \
	${ICON_OVERRIDE[@]+"${ICON_OVERRIDE[@]}"} \
	build | tee "$REPO/build/xcodebuild.log" | grep -E "^\*\* BUILD|error:"
then
	echo "Build failed; run xcodebuild yourself for the full log."
	exit 1
fi
set +o pipefail

APP="$REPO/build/$CONFIGURATION/Adium.app"
[ -d "$APP" ] || { echo "FAIL: no application at $APP"; exit 1; }

step "Verifying the built application"
"$REPO/Utilities/verify-purple-plugins.sh" --app "$APP"

# The application's own signature, which nothing checked until October 2026. It
# was invalid for months and nobody could see it: libffi.framework kept an empty
# Versions/7 beside its Versions/8 after the library moved, and codesign rejects a
# framework with a version directory nothing names. Gatekeeper would have refused
# the result, and notarisation will refuse it later, so it is checked here where a
# person is already watching.
if ! codesign --verify "$APP" 2>/dev/null; then
	echo "FAIL: the built application does not verify:"
	codesign --verify "$APP" 2>&1 | sed 's/^/  /'
	exit 1
fi
echo "== the application's signature verifies"

# XtrasCreator rides inside the bundle as nested code with a signature of its
# own, and a broken one fails notarisation the way a broken framework would.
HELPER="$APP/Contents/Helpers/XtrasCreator.app"
if [ ! -d "$HELPER" ]; then
	echo "FAIL: no XtrasCreator.app in Contents/Helpers; the Adium target no longer embeds it"
	exit 1
fi
if ! codesign --verify "$HELPER" 2>/dev/null; then
	echo "FAIL: XtrasCreator.app in Contents/Helpers does not verify:"
	codesign --verify "$HELPER" 2>&1 | sed 's/^/  /'
	exit 1
fi
echo "== XtrasCreator.app in Contents/Helpers verifies"

# The layered icons macOS 26 draws, one per bundle, compiled by the build from the .icon
# packages. A chosen icon switches Adium's off on purpose, so only the plain build is checked.
if [ -z "$ICON_CHOICE" ]; then
	for bundle in "$APP" "$HELPER"; do
		if [ ! -f "$bundle/Contents/Resources/Assets.car" ]; then
			echo "FAIL: no Assets.car in $(basename "$bundle"); the layered icon was not compiled"
			exit 1
		fi
	done
	echo "== both layered icons are compiled in"
fi

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
