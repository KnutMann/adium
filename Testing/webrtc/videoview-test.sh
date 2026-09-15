#!/bin/zsh
# Build and run the video view's own checks: a frame in, a picture out.
set -e
cd "$(dirname "$0")"
../../Dependencies/webrtc/fetch-webrtc.sh
FRAMEWORK="$(cd ../../Dependencies/webrtc/WebRTC.xcframework/macos-x86_64_arm64 && pwd)"
clang -fobjc-arc -F "$FRAMEWORK" -framework WebRTC -framework AppKit -framework CoreImage \
	-framework CoreVideo -framework QuartzCore -I "../../Plugins/Purple Service" \
	"../../Plugins/Purple Service/AIJingleVideoView.m" videoview-test.m -o /tmp/adium-videoview-test \
	-Wl,-rpath,"$FRAMEWORK"
exec /tmp/adium-videoview-test
