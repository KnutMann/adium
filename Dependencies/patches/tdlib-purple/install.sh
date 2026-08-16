#!/bin/bash
#
# Install a freshly built libtelegram-tdlib.so, but not over a session it cannot read.
#
# tdlib keeps its session in a binlog, and every event in it carries the writing tdlib's internal
# format number. A tdlib refuses to parse an event numbered at or above its own, which it reports as
#
#     [LogEvent.h:156][!Td][&version() < static_cast<int32>(Version::Next)]	Wrong version 60
#
# and then gives up on the account. Worse, it does not give up cleanly: an older tdlib that gets that
# far has already touched the log, and the newer one that wrote it will not read it afterwards
# either. So installing a plugin built against an older tdlib than the one that wrote the session
# does not merely fail, it ends the session for both, and the only way out is to log in again.
#
# Nothing warns about this on its own. The plugin's CMakeLists checks the tdlib it is built against,
# not the tdlib that wrote the session on this machine, and the two have no reason to agree: the
# libraries live in Dependencies/build, the session lives in Application Support, and a stale build
# directory is enough to pair them wrongly. This happened on 2026-08-16 and cost the account.
#
# So the version that wrote the session is recorded beside it, and this script compares.
#
# Usage:
#   install.sh <built .so> <build directory>     install if the versions allow it
#   install.sh --record <version>                write the stamp for a session already in use
#
set -uo pipefail

ADIUM="$(cd "$(dirname "$0")/../../.." && pwd)"
SESSION="$HOME/Library/Application Support/Adium 2.0/Users/Default/libpurple/tdlib"
STAMP="$SESSION/.tdlib-version"

version_number() { # 1.8.65 -> 10865, so string compare never decides this
	local IFS=.
	set -- $1
	echo $(( 10000*${1:-0} + 100*${2:-0} + ${3:-0} ))
}

if [ "${1:-}" = "--record" ]; then
	[ -n "${2:-}" ] || { echo "usage: install.sh --record <version>" >&2; exit 2; }
	mkdir -p "$SESSION"
	printf '%s\n' "$2" > "$STAMP"
	echo "recorded: the session in $SESSION was written by tdlib $2"
	exit 0
fi

SO="${1:-}"
BUILDDIR="${2:-}"
[ -f "$SO" ] || { echo "no plugin at '$SO'" >&2; exit 2; }
[ -d "$BUILDDIR" ] || { echo "no build directory at '$BUILDDIR'" >&2; exit 2; }

# Which tdlib this plugin was built against. Taken from the package cmake found, not from the
# plugin, because the plugin reports its tdlib only once it is loaded and running.
TD_DIR="$(sed -n 's/^Td_DIR[^=]*=//p' "$BUILDDIR/CMakeCache.txt" | head -1)"
[ -n "$TD_DIR" ] || { echo "no Td_DIR in $BUILDDIR/CMakeCache.txt" >&2; exit 1; }
BUILT_WITH="$(sed -n 's/^set(PACKAGE_VERSION "\(.*\)").*/\1/p' "$TD_DIR/TdConfigVersion.cmake" | head -1)"
[ -n "$BUILT_WITH" ] || { echo "no version in $TD_DIR/TdConfigVersion.cmake" >&2; exit 1; }
echo "plugin built against tdlib $BUILT_WITH"

HAVE_SESSION=0
find "$SESSION" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -q . && HAVE_SESSION=1

if [ "$HAVE_SESSION" = 1 ]; then
	if [ ! -f "$STAMP" ]; then
		cat >&2 <<EOF

REFUSING: there is a session in
    $SESSION
and no record of which tdlib wrote it. Installing the wrong one destroys it.

The running plugin says so itself in the debug log, as

    (Libpurple: telegram-tdlib) version <x>, tdlib <y>

Read <y> there and record it once:

    $0 --record <y>

EOF
		exit 1
	fi

	WROTE_SESSION="$(tr -d '[:space:]' < "$STAMP")"
	echo "session was written by tdlib $WROTE_SESSION"

	if [ "$(version_number "$BUILT_WITH")" -lt "$(version_number "$WROTE_SESSION")" ]; then
		cat >&2 <<EOF

REFUSING: this plugin is built against tdlib $BUILT_WITH, older than the tdlib $WROTE_SESSION that
wrote the session. It would fail to read it and leave it unreadable for both.

Build against tdlib $WROTE_SESSION or newer, or move the session aside first and accept logging in
again:

    mv "$SESSION"/+* ~/Documents/

EOF
		exit 1
	fi
fi

# A copy before the install, every time, whatever the versions say. A newer tdlib may upgrade the
# session in place on first run, and then going back is only possible from a copy.
if [ "$HAVE_SESSION" = 1 ]; then
	COPY="$HOME/Documents/Adium-tdlib-vor-$(date +%Y%m%d-%H%M%S)"
	cp -a "$SESSION" "$COPY" || { echo "could not copy the session aside" >&2; exit 1; }
	echo "session copied to $COPY"
fi

cp "$SO" "$ADIUM/PurplePlugins/libtelegram-tdlib.so" || exit 1
bash "$ADIUM/Dependencies/patches/tdlib-purple/relink_for_bundle.sh" \
	"$ADIUM/PurplePlugins/libtelegram-tdlib.so" || exit 1

printf '%s\n' "$BUILT_WITH" > "$STAMP"
echo "installed, and the session is now recorded as tdlib $BUILT_WITH"
