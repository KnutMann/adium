#!/bin/zsh
# Build and run the picomemo round trip: does X3DH, the double ratchet and the payload
# encryption work on this machine, against the OpenSSL this application already ships?
#
# This proves the cryptographic half of OMEMO before a single line of XMPP is written, so that
# a later failure can be blamed on stanzas rather than on the ratchet.
set -e
cd "$(dirname "$0")"

PICO=../../Dependencies/picomemo
"$PICO/fetch-picomemo.sh"

SSL="$(brew --prefix openssl@3 2>/dev/null || echo /opt/homebrew/opt/openssl@3)"
clang -O2 -I"$PICO/picomemo/gen" -I"$SSL/include" roundtrip-test.c \
	"$PICO/picomemo/o/libpicomemo.a" -L"$SSL/lib" -lcrypto -o /tmp/adium-omemo-roundtrip
exec /tmp/adium-omemo-roundtrip
