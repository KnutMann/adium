#!/bin/bash
# Notarise a signed Adium.app or a disk image and staple the ticket to it.
#
#   Utilities/notarize.sh <Adium.app or Adium.dmg> [more of either]
#
# Credentials, one of the two:
#   NOTARY_PROFILE                 a keychain profile made once with
#                                  xcrun notarytool store-credentials
#   NOTARY_KEY_P8, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#                                  an App Store Connect API key: the .p8 file, its
#                                  key id and the issuer id; what continuous
#                                  integration gets as secrets
#
# An application is zipped for the submission, because the service takes zips,
# disk images and packages and not bare bundles; the ticket then goes onto the
# bundle itself and the zip is thrown away. The zip and the disk image that ship
# are made afterwards from the stapled bundle by package-release.sh, and the disk
# image is notarised and stapled in its turn, so that it opens without a word on
# a machine that has never seen Adium. An input that is not signed with a
# Developer ID is refused here, because the service would refuse it too, after
# the upload. When the service refuses, its log is printed: it names every file
# it objected to, which is the one thing worth having at that moment.
set -euo pipefail

[ $# -ge 1 ] || { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }

CREDENTIALS=()
if [ -n "${NOTARY_PROFILE:-}" ]; then
	CREDENTIALS=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "${NOTARY_KEY_P8:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
	CREDENTIALS=(--key "$NOTARY_KEY_P8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
	echo "No credentials: set NOTARY_PROFILE, or NOTARY_KEY_P8 with NOTARY_KEY_ID and NOTARY_ISSUER_ID." >&2
	exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/adium-notarize.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

submit() { # $1 file to upload, $2 what to describe it as
	local result status id
	echo "== submitting $2"
	result=$(xcrun notarytool submit "$1" "${CREDENTIALS[@]}" --wait --output-format json)
	status=$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')
	id=$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
	echo "   submission $id: $status"
	if [ "$status" != "Accepted" ]; then
		echo "== the service's log:" >&2
		xcrun notarytool log "$id" "${CREDENTIALS[@]}" >&2 || true
		return 1
	fi
}

for target in "$@"; do
	[ -e "$target" ] || { echo "no such file: $target" >&2; exit 1; }
	case "$target" in
		*.app)
			if ! codesign -dv "$target" 2>&1 | grep -q "^Authority=Developer ID Application"; then
				echo "$target is not signed with a Developer ID; nothing to notarise." >&2
				codesign -dv "$target" 2>&1 | grep -E "^Authority|TeamIdentifier" | sed 's/^/  /' >&2
				exit 1
			fi
			ZIP="$WORK/$(basename "$target" .app).zip"
			ditto -c -k --keepParent "$target" "$ZIP"
			submit "$ZIP" "$(basename "$target")"
			xcrun stapler staple -q "$target"
			echo "== stapled; Gatekeeper says: $(spctl --assess --type execute -v "$target" 2>&1 | tail -1)"
			;;
		*.dmg)
			submit "$target" "$(basename "$target")"
			xcrun stapler staple -q "$target"
			echo "== stapled; Gatekeeper says: $(spctl --assess --type open --context context:primary-signature -v "$target" 2>&1 | tail -1)"
			;;
		*)
			echo "$target is neither an .app nor a .dmg" >&2
			exit 2
			;;
	esac
done
