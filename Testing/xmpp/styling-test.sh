#!/bin/zsh
# Build and run the XEP-0393 reader's checks: what is markup, and what is ordinary writing?
set -e
cd "$(dirname "$0")"

clang -fobjc-arc -framework Foundation \
	-I ../../Source \
	styling-test.m ../../Source/AIMessageStyling.m \
	-o /tmp/adium-styling
exec /tmp/adium-styling
