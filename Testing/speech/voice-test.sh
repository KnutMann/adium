#!/bin/zsh
# Build and run the speech migration check: do the stored rate, pitch and voice identifier
# still mean what they meant now that AVSpeechUtterance does the speaking?
set -e
cd "$(dirname "$0")"

clang -fobjc-arc -framework Foundation -framework AVFoundation voice-test.m -o /tmp/adium-voice
exec /tmp/adium-voice
