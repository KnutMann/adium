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
seen=""

# Every string literal that reaches a nib loader, and the file it came from.
while IFS= read -r line; do
	# grep -A prints "file-NN-text" for context lines and "file:NN:text" for matches, so
	# cut at whichever separator comes first rather than assuming one of them.
	file=$(printf '%s' "$line" | sed -E 's/[:-][0-9]+[:-].*//')
	name=$(printf '%s' "$line" | sed -n 's/.*@"\([A-Za-z0-9_ -]*\)".*/\1/p')
	[ -z "$name" ] && continue
	case " $seen " in *" $name "*) continue;; esac
	seen="$seen $name"
	if [ -z "$(find "$APP" -name "$name.nib" -print -quit 2>/dev/null)" ]; then
		printf '  MISSING  %-32s named by %s\n' "$name.nib" "$(basename "$file")"
		fail=1
	else
		printf '  ok       %-32s named by %s\n' "$name.nib" "$(basename "$file")"
	fi
done < <(
	# Direct loads: the name is in the same statement.
	grep -rn 'ai_loadNibNamed:@"\|loadNibNamed:@"\|initWithWindowNibName:@"' \
		--include='*.m' Source Plugins Frameworks 2>/dev/null
	# Indirect loads. The name need not be in the file that loads it: a base class can load
	# [[self class] nibName] while each subclass answers with its own name, which is how the
	# contact list windows work. So once any file loads through -nibName, every -nibName in
	# the tree is a candidate, and each one is checked.
	#
	# This is deliberately wider than the loaders. A pane that answers -nibName without
	# loading anything is not a fault, but a name that points at nothing is still worth
	# seeing, because the next person to add a load call inherits it.
	if grep -rq 'NibNamed:\[self nibName\]\|NibNamed:\[\[self class\] nibName\]\|NibName:\[self nibName\]\|NibName:\[\[self class\] nibName\]' \
			--include='*.m' Source Plugins Frameworks 2>/dev/null; then
		grep -rn 'nibName' -A3 --include='*.m' Source Plugins Frameworks 2>/dev/null \
			| grep 'return @"'
	fi
)

echo
if [ "$fail" = "0" ]; then
	echo "Every nib that is named is in the bundle."
else
	echo "A nib is named that the bundle does not carry. It would fail when its pane opens." >&2
fi
exit $fail
