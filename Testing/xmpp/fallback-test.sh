#!/bin/zsh
# Build and run the XEP-0428 range check: does the marked stretch come out of the body,
# counted in characters rather than bytes, and from the back so the earlier offsets hold?
set -e
cd "$(dirname "$0")"

clang -fobjc-arc -framework Foundation fallback-test.m -o /tmp/adium-fallback
exec /tmp/adium-fallback
