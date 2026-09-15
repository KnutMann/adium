#!/bin/zsh
# Build and run the check on the OMEMO wire form: one payload, one wrapped key per device, the
# authentication tag carried in the key rather than on the payload, and the cases where a
# message must not open.
set -e
cd "$(dirname "$0")"

PICO=../../Dependencies/picomemo
"$PICO/fetch-picomemo.sh"

SSL="$(brew --prefix openssl@3 2>/dev/null || echo /opt/homebrew/opt/openssl@3)"
xcrun clang -fobjc-arc -framework Foundation \
	-I"$PICO/picomemo/gen" -I"../../Plugins/Purple Service" -I"$SSL/include" \
	message-test.m "../../Plugins/Purple Service/AIOMEMOStore.m" \
	"../../Plugins/Purple Service/AIOMEMOMessage.m" \
	"$PICO/picomemo/o/libpicomemo.a" -L"$SSL/lib" -lcrypto -o /tmp/adium-omemo-message
exec /tmp/adium-omemo-message
