#!/bin/zsh
# Fetch everything the build needs that is not in this repository.
#
# Four things are not checked in, for four different reasons, and a fresh clone cannot be
# built without all four. Until this script existed each of them was somebody's job to
# remember, which meant each of them was a build that failed at a compiler error naming a
# header, with nothing to suggest that a download was what was missing.
#
#   MMTabBarView   a submodule, so git has it but only after being asked a second time
#   WebRTC         a 200 MB binary framework, carrying the media of a call
#   picomemo       the cryptographic half of OMEMO, fetched and built from pinned source
#   libogg/libopus the codec voice notes are recorded in, built from pinned source
#
# Everything here is idempotent and quiet when there is nothing to do, so calling it before
# every build costs a second and saves the failure.

set -e
cd "$(dirname "$0")/.."

# A tarball of the repository has no git and therefore no submodules. Say so rather than
# failing obscurely three steps later, when the tab bar will not build.
if [ -d .git ] || git rev-parse --git-dir >/dev/null 2>&1; then
	echo "==> Submodules"
	git submodule update --init --recursive
elif [ ! -f Dependencies/MMTabBarView/README.md ]; then
	echo "error: this is not a git checkout and Dependencies/MMTabBarView is empty." >&2
	echo "       Clone the repository with git rather than downloading an archive." >&2
	exit 1
fi

echo "==> WebRTC framework"
Dependencies/webrtc/fetch-webrtc.sh

echo "==> picomemo"
Dependencies/picomemo/fetch-picomemo.sh

echo "==> libogg und libopus"
Dependencies/opus/fetch-opus.sh
