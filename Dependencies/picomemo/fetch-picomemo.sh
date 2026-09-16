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

if [ -f "$LIBRARY" ] && [ "$(git -C "$SOURCE" rev-parse HEAD 2>/dev/null)" = "$REVISION" ]; then
	echo "picomemo ($REVISION) liegt schon gebaut da"
	exit 0
fi

if [ ! -d "$SOURCE" ]; then
	git clone -q https://github.com/mierenhoop/picomemo.git "$SOURCE"
fi
git -C "$SOURCE" fetch -q origin "$REVISION" 2>/dev/null || git -C "$SOURCE" fetch -q origin
git -C "$SOURCE" checkout -q "$REVISION"

SSL="$(brew --prefix openssl@3 2>/dev/null || echo /opt/homebrew/opt/openssl@3)"
[ -f "$SSL/include/openssl/evp.h" ] || {
	echo "OpenSSL 3 Kopfdateien fehlen; erwartet unter $SSL"; exit 1; }

# Only the static library: the shared one wants GNU ld's -soname, which macOS spells
# differently, and embedding a static library is what we want anyway.
cd "$SOURCE"
DRIVERS="c25519.c openssl.c" CFLAGS="-O2 -I$SSL/include" make o/libpicomemo.a >/dev/null

echo "picomemo ($REVISION) gebaut: $(cd .. && ls -lh "$LIBRARY" | awk '{print $5}'), $(lipo -info o/libpicomemo.a | sed 's/.*: //')"
