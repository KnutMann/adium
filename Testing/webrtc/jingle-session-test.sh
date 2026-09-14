#!/bin/zsh
# Build and run the two-machine conversation checks: a whole call talked
# through in one process, the wire and the media layer played by the test.
set -e
cd "$(dirname "$0")"
clang -fobjc-arc -framework Foundation -I "../../Plugins/Purple Service" \
	"../../Plugins/Purple Service/AIJingleEngine.m" \
	"../../Plugins/Purple Service/AIJingleSessionMachine.m" \
	jingle-session-test.m -o /tmp/adium-jingle-session-test
exec /tmp/adium-jingle-session-test
