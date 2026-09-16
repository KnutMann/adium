#!/bin/zsh
# Build and run the check on the durable half of OMEMO: identity, sessions, skipped keys and
# what the user decided, all of it across a simulated restart.
set -e
cd "$(dirname "$0")"

PICO=../../Dependencies/picomemo
"$PICO/fetch-picomemo.sh"

SSL="$(brew --prefix openssl@3 2>/dev/null || echo /opt/homebrew/opt/openssl@3)"
xcrun clang -fobjc-arc -framework Foundation \
	-I"$PICO/picomemo/gen" -I"../../Plugins/Purple Service" -I"$SSL/include" \
	store-test.m "../../Plugins/Purple Service/AIOMEMOStore.m" \
	"$PICO/picomemo/o/libpicomemo.a" -L"$SSL/lib" -lcrypto -o /tmp/adium-omemo-store
exec /tmp/adium-omemo-store
