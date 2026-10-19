#!/bin/zsh
# Fetch and build picomemo, the cryptographic half of OMEMO (XEP-0384).
#
# picomemo carries X3DH, the double ratchet and the protobuf encoding needed for OMEMO, and
# nothing else: device lists, bundles, stanzas and trust stay Adium's own work. It is ISC
# licensed, which is why it was chosen over the alternatives, all of which are GPL v3 or AGPL
# and would have taken the GPL v2 option away from the finished application.
#
# The crypto backend is OpenSSL rather than the bundled HACL*, because this application ships
# an OpenSSL 3 already for Telegram, and because that keeps eight thousand lines of vendored
# verified C out of the tree.
#
# Pinned by commit, and the tree is checked against it: a cryptographic library that silently
# became a different cryptographic library is precisely the thing nobody notices.

set -e
cd "$(dirname "$0")"

REVISION=616b7014ea293a1fd5f785b2535db5bdaa0acfdf
SOURCE=picomemo
LIBRARY="$SOURCE/o/libpicomemo.a"

# The same number as MIN_OS_VERSION in ../build.sh, and it has to be spelled out for
# this build too: clang left to itself stamps the objects for the machine it runs on,
# and the application, which is built for 12.0, then gets a linker warning for every
# member it pulls out of the archive.
MIN_OS_VERSION=13.0

# Which OpenSSL's headers this is compiled against. It has to be the one the archive will
# be linked against, which is Frameworks/libcrypto.3.dylib, and its headers are checked in
# beside it under Frameworks/openssl/include: ../phases/build_openssl.sh builds both from a
# pinned release of OpenSSL's long term support branch, and copy_frameworks.sh places them.
# Homebrew used to stand behind this as a fallback for a checkout that had not built the
# dependencies, and that was the trap: it tracks the newest branch, so this compiled against
# the headers of 3.6.4 over a 3.5.9 library on the very machine this was written on. What
# drift produces is not a compiler error but a symbol that is missing when Adium starts. So
# there is one place, and a missing header there is an error, not a reason to look elsewhere.
SSL="$(cd ../.. && pwd)/Frameworks/openssl"
[ -f "$SSL/include/openssl/evp.h" ] || {
	echo "No OpenSSL headers at $SSL/include/openssl; they are checked in beside Frameworks/libcrypto.3.dylib" >&2
	exit 1; }

# An archive built before a flag existed is the right revision and still wrong, so the
# minimum and the OpenSSL it was compiled against are both part of what "already built"
# means. Otherwise every checkout that has one keeps it, and the mismatch comes back with
# no way to tell why. The note lives in o/, which is the build output, so removing that
# directory forgets it along with everything else it describes.
BUILT_AGAINST="$SOURCE/o/.built-against"
archive_is_current() {
	[ -f "$LIBRARY" ] || return 1
	[ "$(git -C "$SOURCE" rev-parse HEAD 2>/dev/null)" = "$REVISION" ] || return 1
	[ "$(cat "$BUILT_AGAINST" 2>/dev/null)" = "$SSL" ] || return 1
	local stamps
	stamps=$(otool -l "$LIBRARY" 2>/dev/null \
		| awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; f=0}' | sort -u)
	[ "$stamps" = "$MIN_OS_VERSION" ]
}

if archive_is_current; then
	echo "picomemo ($REVISION) is already built"
	exit 0
fi
rm -rf "$SOURCE/o"

if [ ! -d "$SOURCE" ]; then
	git clone -q https://github.com/mierenhoop/picomemo.git "$SOURCE"
fi
git -C "$SOURCE" fetch -q origin "$REVISION" 2>/dev/null || git -C "$SOURCE" fetch -q origin
git -C "$SOURCE" checkout -q "$REVISION"

# Only the static library: the shared one wants GNU ld's -soname, which macOS spells
# differently, and embedding a static library is what we want anyway.
cd "$SOURCE"
DRIVERS="c25519.c openssl.c" \
	CFLAGS="-O2 -mmacosx-version-min=$MIN_OS_VERSION -I$SSL/include" \
	make o/libpicomemo.a >/dev/null
echo "$SSL" > o/.built-against

echo "picomemo ($REVISION) built: $(cd .. && ls -lh "$LIBRARY" | awk '{print $5}'), $(lipo -info o/libpicomemo.a | sed 's/.*: //'), macOS $MIN_OS_VERSION, OpenSSL headers from $SSL"
