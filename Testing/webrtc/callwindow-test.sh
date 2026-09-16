#!/bin/zsh
# Build and run the call window's geometry check: the real window, once without a
# picture and once with, measuring that nothing overlaps, nothing sits outside,
# and the bar at the bottom stays clear even when the picture fills the frame.
set -e
cd "$(dirname "$0")"

../../Dependencies/webrtc/fetch-webrtc.sh
FRAMEWORK="$(cd ../../Dependencies/webrtc/WebRTC.xcframework/macos-x86_64_arm64 && pwd)"

clang -fobjc-arc -Wno-arc-retain-cycles -F "$FRAMEWORK" -F "../../build/Debug" \
	-framework WebRTC -framework Foundation -framework AppKit -framework CoreVideo \
	-framework CoreMedia -framework AVFoundation -framework CoreImage -framework QuartzCore \
	-I "../../Plugins/Purple Service" \
	"../../Plugins/Purple Service/AIJingleEngine.m" \
	"../../Plugins/Purple Service/AIJingleSessionMachine.m" \
	"../../Plugins/Purple Service/AIJingleCallController.m" \
	"../../Plugins/Purple Service/AIJingleVideoView.m" \
	"../../Plugins/Purple Service/AIJingleCallWindowController.m" \
	logging-stub.m callwindow-test.m -o /tmp/adium-callwindow -Wl,-rpath,"$FRAMEWORK"
exec /tmp/adium-callwindow
