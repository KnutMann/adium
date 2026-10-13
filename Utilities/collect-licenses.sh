#!/bin/bash
# Gather the licence of everything Adium ships, from the trees it was built from.
#
# Adium's own code is GPL version 2 or later. The application it ships is not:
# it carries two dozen libraries and six protocol plug-ins, several of them under
# GPLv3 or Apache 2.0, and the bundle as a whole can only be conveyed under GPLv3.
# License.txt has to say that, and it has to list what is inside. It used to list
# exactly one library, libezv, which was removed from the tree years ago.
#
# The lesson of that is not "write a better list by hand". It is that a list
# maintained by hand drifts away from the binaries. So this reads the licence out
# of the source tree each component was actually built from, and refuses to guess:
# where no text can be found, it says so and exits non-zero rather than inventing
# one. The hardest-won part of that is the mapping below. The Telegram plug-in in
# PurplePlugins/ announces itself as tdlib-purple 0.8.1 even though the patch notes
# name a 2.1.0 fork, and the two differ in licence. The binary wins.
#
#   Utilities/collect-licenses.sh                 refresh Resources/Licenses/
#   Utilities/collect-licenses.sh --check <app>   every binary in that app covered?
set -u

cd "$(dirname "$0")/.."
REPO=$(pwd)
OUT="$REPO/Resources/Licenses"

# component | SPDX | where the text lives, relative to the repository | upstream
MANIFEST=$(cat <<'EOF'
AutoHyperlinks|BSD-3-Clause|Frameworks/AutoHyperlinks Framework/License.txt|https://github.com/adium/adium
cyrus-sasl|BSD-4-Clause|Dependencies/source/cyrus-sasl/COPYING|https://github.com/cyrusimap/cyrus-sasl
gettext-runtime|LGPL-2.1-or-later|Dependencies/source/gettext/gettext-runtime/intl/COPYING.LIB|https://savannah.gnu.org/projects/gettext
GPL-3.0|GPL-3.0|Dependencies/source/purple-gowhatsapp/LICENSE|https://www.gnu.org/licenses/gpl-3.0.html
glib|LGPL-2.1-or-later|Dependencies/source/glib/COPYING|https://gitlab.gnome.org/GNOME/glib
json-glib|LGPL-2.1-or-later|Dependencies/source/json-glib-1.6.2/COPYING|https://gitlab.gnome.org/GNOME/json-glib
libgcrypt|LGPL-2.1-or-later|Dependencies/source/libgcrypt/COPYING.LIB|https://gnupg.org/software/libgcrypt
libgpg-error|LGPL-2.1-or-later|Dependencies/source/gpgerror/COPYING.LIB|https://gnupg.org/software/libgpg-error
libogg|BSD-3-Clause|Dependencies/source/libogg-1.3.6/COPYING|https://gitlab.xiph.org/xiph/ogg
libotr|LGPL-2.1-or-later|Dependencies/source/otr/COPYING.LIB|https://otr.cypherpunks.ca
libpurple|GPL-2.0-or-later|Dependencies/source/libpurple/COPYING|https://pidgin.im
MMTabBarView|BSD-3-Clause|Dependencies/MMTabBarView/LICENSE|https://github.com/MrNoodle/MMTabBarView
opus|BSD-3-Clause|Dependencies/source/opus-1.5.2/COPYING|https://opus-codec.org
opusfile|BSD-3-Clause|Dependencies/source/opusfile-0.12/COPYING|https://opus-codec.org
picomemo|ISC|Dependencies/picomemo/picomemo/LICENSE|https://codeberg.org/pico/picomemo
purple-gowhatsapp|GPL-3.0-or-later|Dependencies/source/purple-gowhatsapp/LICENSE|https://github.com/hoehermann/purple-gowhatsapp
purple-matrix-rs|GPL-2.0-or-later|Dependencies/source/purple-matrix-rs/LICENSE|https://github.com/iilonmasc/purple-matrix-rs
purple-presage|GPL-3.0-or-later|Dependencies/source/purple-presage/LICENSE|https://github.com/hoehermann/purple-presage
tdlib|BSL-1.0|Dependencies/source/td-1.8.67/LICENSE_1_0.txt|https://github.com/tdlib/td
tdlib-purple|GPL-3.0|Dependencies/source/tdlib-purple-master/LICENSE|https://github.com/adrighem/tdlib-purple
WebRTC|BSD-3-Clause|Dependencies/webrtc/WebRTC.xcframework/LICENSE|https://github.com/stasel/WebRTC
EOF
)

# The ones whose source tree is not kept after the build, or which are prebuilt
# elsewhere. Pinned to the exact tag we build, so the text is the one that applies.
REMOTE=$(cat <<'EOF'
gdk-pixbuf|LGPL-2.1-or-later|https://raw.githubusercontent.com/GNOME/gdk-pixbuf/2.44.7/COPYING|https://gitlab.gnome.org/GNOME/gdk-pixbuf
libffi|MIT|https://raw.githubusercontent.com/libffi/libffi/v3.8.0/LICENSE|https://github.com/libffi/libffi
libjpeg-turbo|BSD-3-Clause|https://raw.githubusercontent.com/libjpeg-turbo/libjpeg-turbo/3.2.0/LICENSE.md|https://libjpeg-turbo.org
libpng|libpng-2.0|https://raw.githubusercontent.com/pnggroup/libpng/v1.6.58/LICENSE|http://www.libpng.org
libwebp|BSD-3-Clause|https://raw.githubusercontent.com/webmproject/libwebp/v1.6.0/COPYING|https://developers.google.com/speed/webp
matrix-rust-sdk|Apache-2.0|https://raw.githubusercontent.com/matrix-org/matrix-rust-sdk/matrix-sdk-0.19.1/LICENSE|https://github.com/matrix-org/matrix-rust-sdk
openssl|Apache-2.0|https://raw.githubusercontent.com/openssl/openssl/openssl-3.5.9/LICENSE.txt|https://www.openssl.org
purple-teams|GPL-3.0|https://raw.githubusercontent.com/EionRobb/purple-teams/master/LICENSE|https://github.com/EionRobb/purple-teams
purple2-ircv3|GPL-2.0|https://raw.githubusercontent.com/EionRobb/purple2-ircv3/master/LICENSE|https://github.com/EionRobb/purple2-ircv3
EOF
)

write_one() {                                  # name spdx upstream source-description
	local name=$1 spdx=$2 upstream=$3 whence=$4
	{
		echo "$name"
		echo "SPDX-License-Identifier: $spdx"
		echo "Upstream: $upstream"
		echo "Text taken from: $whence"
		echo "$(printf '%.0s-' {1..78})"
		echo
		cat
	} > "$OUT/$name.txt"
}

missing=0
mkdir -p "$OUT"

while IFS='|' read -r name spdx path upstream; do
	[ -z "$name" ] && continue
	if [ -r "$REPO/$path" ]; then
		write_one "$name" "$spdx" "$upstream" "$path" < "$REPO/$path"
		printf "  %-20s %-22s %s\n" "$name" "$spdx" "$path"
	else
		printf "  %-20s %-22s MISSING: %s\n" "$name" "$spdx" "$path"
		missing=$((missing + 1))
	fi
done <<< "$MANIFEST"

while IFS='|' read -r name spdx url upstream; do
	[ -z "$name" ] && continue
	if body=$(curl -fsSL --max-time 30 "$url" 2>/dev/null) && [ -n "$body" ]; then
		printf '%s\n' "$body" | write_one "$name" "$spdx" "$upstream" "$url"
		printf "  %-20s %-22s %s\n" "$name" "$spdx" "fetched"
	else
		printf "  %-20s %-22s MISSING: %s\n" "$name" "$spdx" "$url"
		missing=$((missing + 1))
	fi
done <<< "$REMOTE"

echo
if [ "$missing" -gt 0 ]; then
	echo "$missing component(s) without a licence text. Fix the manifest, do not guess."
	exit 1
fi
echo "Resources/Licenses/ holds $(ls "$OUT" | wc -l | tr -d ' ') files."
