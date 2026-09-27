#!/bin/bash -eu
#
# Writes into the built Info.plist what this build is: when it was made, to the
# minute, and which commit it was made from.
#
# Why it exists: an evening was spent on a fix that was already in the running
# application, and another on one that was not, and neither the About window nor
# the debug log could say which. A date alone cannot: several builds a day is
# normal here. The commit alone cannot either, because a build from changed but
# uncommitted sources carries the commit it was started from.

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
[ -f "$PLIST" ] || exit 0

stamp=$(date "+%Y-%m-%d %H:%M")

if hash=$(git -C "$SRCROOT" rev-parse --short HEAD 2>/dev/null); then
	# A build from a working copy with changes is not the commit it names
	if ! git -C "$SRCROOT" diff --quiet HEAD 2>/dev/null; then
		hash="$hash+"
	fi
else
	hash="no git"
fi

/usr/libexec/PlistBuddy -c "Delete :AIBuildStamp" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :AIBuildStamp string $stamp" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :AIBuildCommit" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :AIBuildCommit string $hash" "$PLIST"

echo "note: built $stamp from $hash"
