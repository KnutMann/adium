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

CONFIGURATION="${CONFIGURATION:-Release}"
cd "$(dirname "$0")"

echo "==> Building AIUtilities"
xcodebuild -project "Frameworks/AIUtilities/AIUtilities.xcodeproj" \
	-configuration "$CONFIGURATION" build

echo "==> Building MMTabBarView"
if [ ! -f "Dependencies/MMTabBarView/README.md" ]; then
	echo "error: MMTabBarView submodule is missing; run: git submodule update --init" >&2
	exit 1
fi
xcodebuild -project "Dependencies/MMTabBarView/MMTabBarView/MMTabBarView.xcodeproj" \
	-target MMTabBarView -configuration "$CONFIGURATION" build

echo "==> Staging prebuilt products into build/$CONFIGURATION"
mkdir -p "build/$CONFIGURATION/include"
cp -R "Frameworks/AIUtilities/build/$CONFIGURATION/AIUtilities.framework" "build/$CONFIGURATION/"
cp -R "Dependencies/MMTabBarView/MMTabBarView/build/$CONFIGURATION/MMTabBarView.framework" "build/$CONFIGURATION/"
cp "Frameworks/AIUtilities/build/$CONFIGURATION/include/"*.h "build/$CONFIGURATION/include/"

echo "==> Building Adium"
# Finder metadata on a previously-run bundle breaks codesign ("detritus")
xattr -cr "build/$CONFIGURATION/Adium.app" 2>/dev/null || true
xcodebuild -project Adium.xcodeproj -target Adium \
	-configuration "$CONFIGURATION" build

echo "==> Done: build/$CONFIGURATION/Adium.app"
