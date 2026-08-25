#!/bin/zsh
# Tests for the JavaScript-plugin feature.
#
# 1. The isolation probe: a hostile plugin, injected into a content world with
#    the exact hardening the message view applies, must find every network and
#    native-handler escape blocked. This is the security gate; it must pass
#    before the feature ships to anyone.
# 2. Transform tests: each bundled plugin, driven through a real WKWebView the
#    way the app injects it, must render its transform and must never turn
#    message text into markup.
#
# Usage: Tests/run-tests.sh   (from Plugins/JavaScript Xtras, or anywhere)

set -e
cd "$(dirname "$0")"
BUILD="../../../Other/XtrasCreator/build"   # reuse a gitignored build dir near the tree
mkdir -p "$BUILD"

echo "== compile"
clang -fobjc-arc -framework Cocoa -framework WebKit isolation-probe.m -o "$BUILD/js-isolation-probe"
clang -fobjc-arc -framework Cocoa -framework WebKit transform-test.m  -o "$BUILD/js-transform-test"

fails=0

echo "== isolation probe (security gate)"
if ! "$BUILD/js-isolation-probe"; then
	echo "!! ISOLATION PROBE FAILED - do not ship"
	fails=$((fails + 1))
fi

run() { if ! "$BUILD/js-transform-test" "$@"; then fails=$((fails + 1)); fi }

BE="../Bundled/Big Emoji.AdiumPlugin/Contents/Resources/plugin.js"
ML="../Bundled/Markdown Light.AdiumPlugin/Contents/Resources/plugin.js"
CB="../Bundled/Code Blocks.AdiumPlugin/Contents/Resources/plugin.js"

echo "== Big Emoji"
# Emoji grow to triple (font size); emoticons to double their own pixels (a 1x1
# data-URI stands in for an emoticon image, so doubling lands at 2px).
PNG='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='
run "$BE" \
	"😀😀" "+3em" \
	"hello world" "-3em" \
	"😀 with text" "-3em" \
	"<img class=\"emoticon\" src=\"$PNG\">" "+width: 2px" \
	"<img class=\"emoticon\" src=\"$PNG\"><img class=\"emoticon\" src=\"$PNG\"><img class=\"emoticon\" src=\"$PNG\"><img class=\"emoticon\" src=\"$PNG\">" "-width: 2px"

echo "== Markdown Light"
run "$ML" \
	"this is **bold** text" "+<strong>bold</strong>" \
	"some *italic* here" "+<em>italic</em>" \
	"a ~struck~ word" "+<s>struck</s>" \
	"plain text" "-<strong>" \
	"&lt;em&gt;typed&lt;/em&gt;" "-<em>typed</em>"

echo "== Code Blocks"
run "$CB" \
	"run \`ls -la\` now" "+<code class=\"x-adium-code\">ls -la</code>" \
	"no code here" "-x-adium-code" \
	"\`\`\`<br>line1<br>line2<br>\`\`\`" "+<pre"

echo
if [ $fails -gt 0 ]; then
	echo "== $fails test group(s) FAILED"
	exit 1
fi
echo "== all tests pass"
