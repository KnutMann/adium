#!/bin/zsh
# Build and run the check on encrypted file sharing (XEP-0454), against a published NIST vector
# rather than against our own encryption, so that a file from somebody else's client is what is
# actually being proved.
set -e
cd "$(dirname "$0")"

SSL="$(brew --prefix openssl@3 2>/dev/null || echo /opt/homebrew/opt/openssl@3)"
xcrun clang -fobjc-arc -framework Foundation -I"$SSL/include" -I"../../Plugins/Purple Service" \
	media-test.m "../../Plugins/Purple Service/AIOMEMOMedia.m" \
	-L"$SSL/lib" -lcrypto -o /tmp/adium-omemo-media
exec /tmp/adium-omemo-media
