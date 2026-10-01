#!/bin/bash
#
# Every nib a class names must be in the built application.
#
# This exists because of a mistake worth not repeating. Nine interface files looked dead:
# their panes build their views in code, so AIModularPane never loads a nib for them. Four
# of them were not dead at all. Those panes are hybrids, they override -view to mirror the
# base class and then call ai_loadNibNamed themselves, taking the individual controls out
# of the nib while the card form only arranges them. Deleting a nib like that breaks
# nothing at build time and everything the first time somebody opens the pane.
#
# So the test is not "does a pane override -view" and not "does anything mention the name".
# It is: which names are handed to a nib loader, and is each of those files in the bundle.
#
#   Testing/ui/nibs/nib-audit.sh [path/to/Adium.app]

set -u
cd "$(dirname "$0")/../../.." || exit 1

APP="${1:-}"
if [ -z "$APP" ]; then
	APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Adium-*/Build/Products/*/Adium.app 2>/dev/null | head -1)
fi
if [ ! -d "$APP" ]; then
	echo "No built Adium.app found. Build first, or pass one as the first argument." >&2
	exit 1
fi
echo "Auditing $APP"
echo

fail=0

# Every string literal that reaches a nib loader, and the file it came from.
while IFS= read -r line; do
	file="${line%%:*}"
	name=$(printf '%s' "$line" | sed -n 's/.*@"\([A-Za-z0-9_ -]*\)".*/\1/p')
	[ -z "$name" ] && continue
	if [ -z "$(find "$APP" -name "$name.nib" -print -quit 2>/dev/null)" ]; then
		printf '  MISSING  %-28s named by %s\n' "$name.nib" "$(basename "$file")"
		fail=1
	else
		printf '  ok       %-28s named by %s\n' "$name.nib" "$(basename "$file")"
	fi
done < <(
	# Direct loads: the name is in the same statement.
	grep -rn 'ai_loadNibNamed:@"\|loadNibNamed:@"\|initWithWindowNibName:@"' \
		--include='*.m' Source Plugins Frameworks 2>/dev/null
	# Indirect loads: the class asks itself, so take the answer of its -nibName.
	for f in $(grep -rl 'ai_loadNibNamed:\[self nibName\]\|ai_loadNibNamed:\[\[self class\] nibName\]\|initWithWindowNibName:\[self nibName\]\|initWithWindowNibName:\[\[self class\] nibName\]' \
			--include='*.m' Source Plugins Frameworks 2>/dev/null); do
		grep -n 'nibName' -A3 "$f" 2>/dev/null | grep 'return @"' | sed "s|^|$f:|"
	done
)

echo
if [ "$fail" = "0" ]; then
	echo "Every nib that is named is in the bundle."
else
	echo "A nib is named that the bundle does not carry. It would fail when its pane opens." >&2
fi
exit $fail
