#!/bin/bash -e
# Builds Adium from a fresh checkout (Apple Silicon, Xcode 15+).
#
# The main project expects the AIUtilities and MMTabBarView frameworks and
# the generated PlistMacros.h to be prebuilt and staged in build/Release;
# historically that was done by long-lost setup scripts. This script does
# the whole sequence:
#
#   git clone --recursive <repo> && cd adium && ./bootstrap.sh
#
# The resulting app is build/Release/Adium.app (ad-hoc signed).
#
# The libraries Adium links against (libpurple, glib, libotr, opus and the
# rest) are prebuilt binaries in the repository, so this needs nothing but
# Xcode. To build them from source instead, which needs a Homebrew toolchain
# and takes the better part of an hour:
#
#   ./bootstrap.sh --rebuild-dependencies

CONFIGURATION="${CONFIGURATION:-Release}"
cd "$(dirname "$0")"

REBUILD_DEPENDENCIES=false
for option in "$@"; do
	case $option in
		--rebuild-dependencies)
			REBUILD_DEPENDENCIES=true
			;;
		-h|-help|--help)
			echo 'Usage: ./bootstrap.sh [--rebuild-dependencies]

  --rebuild-dependencies  Build libpurple, glib, libotr, opus and the other
                          bundled libraries from source before building the
                          application, instead of using the prebuilt binaries
                          in the repository. Needs a Homebrew toolchain
                          (autoconf, automake, libtool, pkg-config).
  --help                  This text

  CONFIGURATION=Debug ./bootstrap.sh builds the Debug configuration.'
			exit 0
			;;
		*)
			echo "Unknown option $option. Run $0 --help for a list." >&2
			exit 1
			;;
	esac
done

# The project pins its signature to "Adium Local Signing", a self-created
# certificate that only exists in the original development keychain; it keeps
# the app's identity stable across rebuilds so the keychain does not ask for
# the account passwords after every build. On any other machine codesign
# cannot find it and the whole build would die on the last step, so fall back
# to ad-hoc signing there. To get the stable identity on a new machine,
# create a self-signed code signing certificate named "Adium Local Signing"
# in Keychain Access and build again.
SIGNING_OVERRIDES=()
if ! security find-identity -p codesigning -v 2>/dev/null | grep -q '"Adium Local Signing"'; then
	echo "==> No 'Adium Local Signing' certificate in this keychain; signing ad hoc"
	SIGNING_OVERRIDES=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
fi

echo "==> Fetching what is not in the repository"
# The submodule, the WebRTC framework and picomemo; see Dependencies/fetch.sh
Dependencies/fetch.sh

if [ "$REBUILD_DEPENDENCIES" = true ]; then
	# Everything under Frameworks/ is a prebuilt binary; these two steps make
	# those binaries again from pinned sources, and overwrite them in place.
	echo "==> Rebuilding libpurple, glib, libotr and friends from source"
	( cd Dependencies && ./build.sh && ./copy_frameworks.sh )

	echo "==> Rebuilding libogg and libopus from source"
	Dependencies/opus/build-opus.sh
fi

echo "==> Building AIUtilities"
xcodebuild -project "Frameworks/AIUtilities/AIUtilities.xcodeproj" \
	-configuration "$CONFIGURATION" build

echo "==> Building MMTabBarView"
xcodebuild -project "Dependencies/MMTabBarView/MMTabBarView/MMTabBarView.xcodeproj" \
	-target MMTabBarView -configuration "$CONFIGURATION" build

echo "==> Staging prebuilt products into build/$CONFIGURATION"
mkdir -p "build/$CONFIGURATION/include"

# A framework built from the main project replaces its own build folder with
# a symlink to the shared one (its "Setup Build Directory" phase does that),
# so the product may already sit exactly where staging would put it. Copying
# it onto itself fails, and so does merging into a bundle staged by an
# earlier run; stage only what really lives elsewhere, freshly each time.
stage_framework() {
	local product="$1"
	local destination_dir="build/$CONFIGURATION"

	if [ "$(cd "$(dirname "$product")" && pwd -P)" = "$(cd "$destination_dir" && pwd -P)" ]; then
		return 0
	fi
	rm -rf "$destination_dir/$(basename "$product")"
	cp -R "$product" "$destination_dir/"
}

stage_framework "Frameworks/AIUtilities/build/$CONFIGURATION/AIUtilities.framework"
stage_framework "Dependencies/MMTabBarView/MMTabBarView/build/$CONFIGURATION/MMTabBarView.framework"

if [ "$(cd "Frameworks/AIUtilities/build/$CONFIGURATION/include" && pwd -P)" != "$(cd "build/$CONFIGURATION/include" && pwd -P)" ]; then
	cp "Frameworks/AIUtilities/build/$CONFIGURATION/include/"*.h "build/$CONFIGURATION/include/"
fi

echo "==> Building Adium"
# Finder metadata on a previously-run bundle breaks codesign ("detritus")
xattr -cr "build/$CONFIGURATION/Adium.app" 2>/dev/null || true
xcodebuild -project Adium.xcodeproj -target Adium \
	-configuration "$CONFIGURATION" "${SIGNING_OVERRIDES[@]}" build

echo "==> Done: build/$CONFIGURATION/Adium.app"
