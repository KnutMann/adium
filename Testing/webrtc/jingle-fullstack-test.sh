#!/bin/zsh
# Build and run the whole-stack call check: two controllers with real peer
# connections, wired to each other purely through their Jingle strings.
# Synthetic video, no audio, so no device or permission prompt is touched.
set -e
cd "$(dirname "$0")"

../../Dependencies/webrtc/fetch-webrtc.sh
FRAMEWORK="$(cd ../../Dependencies/webrtc/WebRTC.xcframework/macos-x86_64_arm64 && pwd)"

clang -fobjc-arc -Wno-arc-retain-cycles -F "$FRAMEWORK" \
	-framework WebRTC -framework Foundation -framework CoreVideo \
	-framework CoreMedia -framework AVFoundation \
	-I "../../Plugins/Purple Service" \
	"../../Plugins/Purple Service/AIJingleEngine.m" \
	"../../Plugins/Purple Service/AIJingleSessionMachine.m" \
	"../../Plugins/Purple Service/AIJingleCallController.m" \
	jingle-fullstack-test.m -o /tmp/adium-jingle-fullstack -Wl,-rpath,"$FRAMEWORK"
exec /tmp/adium-jingle-fullstack
