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
clang -fobjc-arc -framework Cocoa manifest-test.m ../AIJSXtraBundle.m -o "$BUILD/js-manifest-test"

fails=0

echo "== isolation probe (security gate)"
if ! "$BUILD/js-isolation-probe"; then
	echo "!! ISOLATION PROBE FAILED - do not ship"
	fails=$((fails + 1))
fi

echo "== manifest rules"
if ! "$BUILD/js-manifest-test"; then
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
	"😀😀" "+font-size: 48px" \
	"hello world" "-font-size" \
	"😀 with text" "-font-size" \
	"<img class=\"emoticon\" src=\"$PNG\">" "+width: 2px" \
	"<img class=\"emoticon\" src=\"$PNG\"><img class=\"emoticon\" src=\"$PNG\"><img class=\"emoticon\" src=\"$PNG\"><img class=\"emoticon\" src=\"$PNG\">" "-width: 2px"

echo "== Read Receipts"
# The plugin's whole output is a stylesheet, so the input HTML is beside the
# point; what is measured is which CSS the placement setting produced. This is
# the first coverage this plugin has ever had.
RR="../Bundled/Read Receipts.AdiumPlugin/Contents/Resources/plugin.js"
run "$RR" x "+margin-right: 5px"
run --settings '{"placement":"time-after"}' "$RR" x "+margin-left: 5px"
run --settings '{"placement":"message"}' "$RR" x "+x-adium-read::after"
run --settings '{"placement":"message"}' "$RR" x "-margin-right"
# A value the plugin does not know must land on its own fallback, not on nothing
run --settings '{"placement":"nonsense"}' "$RR" x "+margin-right: 5px"

echo "== Big Emoji settings"
# Quadruple: a 16px base times four is 64, clear of the 48px floor, so the value
# is visibly the one that crossed the boundary rather than the floor winning again.
run --settings '{"emojiScale":"4"}' "$BE" "😀😀" "+font-size: 64px"
# One glyph at most, so a two-emoji message is left alone
run --settings '{"maxGlyphs":"1"}' "$BE" "😀😀" "-font-size"

echo "== Markdown Light"
run "$ML" \
	"this is **bold** text" "+<strong>bold</strong>" \
	"some *italic* here" "+<em>italic</em>" \
	"a ~struck~ word" "+<s>struck</s>" \
	"plain text" "-<strong>" \
	"&lt;em&gt;typed&lt;/em&gt;" "-<em>typed</em>"

echo "== Code Blocks"
# The last case guards against silent loss: text after the closing fence means
# the message is not one block, so nothing of it may be thrown away.
#
# The two absence checks name the ELEMENT rather than the class: the readback
# carries the document head as well as the message now, and this plugin's own
# stylesheet mentions both class names, so a bare class name would match there
# and never fail however broken the transform got.
run "$CB" \
	"run \`ls -la\` now" "+<code class=\"x-adium-code\">ls -la</code>" \
	"no code here" "-<code class=\"x-adium-code\"" \
	"\`\`\`<br>line1<br>line2<br>\`\`\`" "+<pre" \
	"\`\`\`<br>line1<br>\`\`\`<br>siehe oben" "+siehe oben" \
	"\`\`\`<br>line1<br>\`\`\`<br>siehe oben" "-<pre class=\"x-adium-pre\""

echo
if [ $fails -gt 0 ]; then
	echo "== $fails test group(s) FAILED"
	exit 1
fi
echo "== all tests pass"
