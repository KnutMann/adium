#!/bin/zsh
# Build and run the WebRTC loopback probe: two peer connections in one
# process, synthetic video frames instead of a camera (so no permission
# prompts), SDP and ICE exchanged directly. Proves the pinned framework
# works on this machine: ICE connects, DTLS-SRTP establishes, frames
# arrive at the far renderer.
set -e
cd "$(dirname "$0")"

../../Dependencies/webrtc/fetch-webrtc.sh
FRAMEWORK="$(cd ../../Dependencies/webrtc/WebRTC.xcframework/macos-x86_64_arm64 && pwd)"

clang -fobjc-arc -Wno-arc-retain-cycles -F "$FRAMEWORK" \
	-framework WebRTC -framework Foundation -framework CoreVideo \
	-framework CoreMedia -framework AVFoundation \
	loopback-probe.m -o /tmp/adium-rtc-probe -Wl,-rpath,"$FRAMEWORK"
exec /tmp/adium-rtc-probe
