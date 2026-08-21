#!/bin/zsh
# Fetches one real-world xtra per type from adiumxtras.com into
# build/wild-fixtures, where run-tests.sh picks them up. They are cached and
# deliberately not part of the repository: they are other people's work.
#
# The download ids come from the site's category pages
# (index.php?a=cats&cat_id=N); the adiumxtra:// links there carry the same
# path over https, which is exactly what Adium's own installer requests.

set -e
cd "$(dirname "$0")/.."
WILD="build/wild-fixtures"
mkdir -p "$WILD"

# type-directory:download-id  (one known-good specimen per category)
# Group chat status icons have no wild specimen: adiumxtras.com predates the
# type; the two packs shipped with Adium are the only known examples.
fixtures=(
	"menubar:8427"		# Menu Bar Icons
	"statusicons:8624"	# Status Icons
	"serviceicons:8629"	# Service Icons
	"emoticons:8772"	# Emoticons
	"sounds:8654"	# Sound Sets
	"contactlist:7617"	# Contact List Styles
	"messagestyles:8774"	# Message Styles
	"scripts:3401"	# AppleScripts
	"dockicons:8779"	# Dock Icons
)

for entry in $fixtures; do
	dir="${entry%%:*}"
	id="${entry##*:}"
	dest="$WILD/$dir"

	if [ -d "$dest" ] && [ -n "$(ls "$dest" 2>/dev/null)" ]; then
		echo "have $dir (cached)"
		continue
	fi

	mkdir -p "$dest"
	archive="$dest/download.archive"
	echo "fetch $dir (id $id)"
	curl -sL --max-time 60 -H "Accept-Encoding: identity" \
		-o "$archive" "https://www.adiumxtras.com/download/$id"

	case "$(file -b "$archive")" in
		Zip*)	unzip -o -q "$archive" -d "$dest" ;;
		gzip*)	tar xzf "$archive" -C "$dest" ;;
		*)		echo "  unknown archive format, leaving as is" ;;
	esac
	rm -f "$archive"
	rm -rf "$dest/__MACOSX"
done

echo "wild fixtures ready in $WILD"
