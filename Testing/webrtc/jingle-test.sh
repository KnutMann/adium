#!/bin/zsh
# Build and run the Jingle engine's round-trip checks. The engine is
# Foundation only, so this compiles it straight from the source tree,
# no Adium and no libpurple involved.
set -e
cd "$(dirname "$0")"
clang -fobjc-arc -framework Foundation -I "../../Plugins/Purple Service" \
	"../../Plugins/Purple Service/AIJingleEngine.m" jingle-roundtrip.m -o /tmp/adium-jingle-test
exec /tmp/adium-jingle-test
