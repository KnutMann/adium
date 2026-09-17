#!/bin/zsh
# Build and run the voice note encoder's checks: does the reader that decides say yes?
set -e
cd "$(dirname "$0")"
DEPS="../../Dependencies/build"

clang -fobjc-arc -framework Foundation \
	-I ../../Source -I "$DEPS/include" -I "$DEPS/include/opus" \
	opus-test.m ../../Source/AIOpusEncoder.m \
	"$DEPS/lib/libopusfile.a" "$DEPS/lib/libopus.a" "$DEPS/lib/libogg.a" \
	-o /tmp/adium-opus
exec /tmp/adium-opus
