#!/bin/zsh
# Build and run the voice note encoder's checks: does the reader that decides say yes?
#
# The three archives come from Frameworks/opus, where they are checked in, and not from
# Dependencies/build, which is a staging directory that only exists on a machine that has
# rebuilt the dependencies. This used to read the staging directory, so the check ran here
# and nowhere else.
set -e
cd "$(dirname "$0")"
OPUS="../../Frameworks/opus"

clang -fobjc-arc -framework Foundation \
	-I ../../Source -I "$OPUS/include" -I "$OPUS/include/opus" \
	opus-test.m ../../Source/AIOpusEncoder.m \
	"$OPUS/lib/libopusfile.a" "$OPUS/lib/libopus.a" "$OPUS/lib/libogg.a" \
	-o /tmp/adium-opus
exec /tmp/adium-opus
