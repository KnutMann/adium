#!/bin/zsh
# Round-trip tests for the new XtrasCreator.
#
# Compiles the test runner against the application sources, then round-trips
# every fixture: the xtras shipped with Adium, and - when present - the wild
# packs fetched from adiumxtras.com by fetch-wild-fixtures.sh. Fixtures whose
# type the application has not learned yet report as SKIP.
#
# Usage: Tests/run-tests.sh   (from Other/XtrasCreator2, or anywhere)

set -e
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
SCRATCH="build/test-scratch"
WILD="build/wild-fixtures"
RUNNER="build/AXSRoundTripTest"

mkdir -p build
rm -rf "$SCRATCH"

echo "== compile"
clang -fobjc-arc -framework Cocoa -framework UniformTypeIdentifiers -framework AVFoundation \
	-I Sources -I "$REPO_ROOT/Frameworks/Adium/Source" \
	Tests/AXSRoundTripTest.m \
	$(ls Sources/*.m | grep -v '/main\.m$' | tr '\n' ' ') \
	"$REPO_ROOT/Frameworks/Adium/Source/AISettingsFormView.m" \
	-o "$RUNNER"

failures=0

run_fixture() {
	local ext="$1" pack="$2"
	if ! "$RUNNER" "$ext" "$pack" "$SCRATCH"; then
		failures=$((failures + 1))
	fi
}

echo "== shipped fixtures"
for dir in "Menu Bar Icons" "Status Icons" "Service Icons" "Emoticons" "Sounds" \
		   "Dock Icons" "Message Styles" "Scripts" "Contact List" "Group Chat Status Icons"; do
	src="$REPO_ROOT/Resources/$dir"
	[ -d "$src" ] || continue
	for pack in "$src"/*.*; do
		[ -e "$pack" ] || continue
		ext="${pack##*.}"
		case "$ext" in
			txt|plist) continue ;;
		esac
		run_fixture "$ext" "$pack"
	done
done

if [ -d "$WILD" ]; then
	echo "== wild fixtures (adiumxtras.com)"
	for pack in "$WILD"/**/*.*(N); do
		[ -d "$pack" ] || [ -f "$pack" ] || continue
		case "$pack" in *__MACOSX*) continue ;; esac
		ext="${pack##*.}"
		case "$ext" in
			Adium*|ListTheme|ListLayout) run_fixture "$ext" "$pack" ;;
		esac
	done
else
	echo "== no wild fixtures; fetch some with Tests/fetch-wild-fixtures.sh"
fi

echo
if [ $failures -gt 0 ]; then
	echo "== $failures fixture(s) FAILED"
	exit 1
fi
echo "== all fixtures pass"
