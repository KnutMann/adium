#!/bin/bash
#
# Build purple-matrix-rs for the bundle and install it as PurplePlugins/libmatrix.so.
#
# The plugin lives in its own repository, https://github.com/iilonmasc/purple-matrix-rs: a Rust
# library on the matrix-rust-sdk (sync, rooms, end-to-end encryption) behind a small C file for
# libpurple. Its own `just plugin` recipe links the two into a loadable bundle; with ADIUM set it
# links against the libraries in Frameworks/ directly, the way purple-presage is built here, so the
# result resolves everything inside the bundle and needs no relink afterwards.
#
# The source is not in the repository. It is fetched here, pinned by commit, and checked against the
# pin, so what ships is exactly what was looked at. There is no adium.patch: the plugin is written
# for this bundle in the first place, and whatever Adium needs goes upstream into it.
#
# Needs a stable Rust toolchain (rustup.rs) and `just` (brew install just), besides Xcode's clang.
# The Rust build takes a few minutes the first time; cargo keeps its output under the checkout's
# target/, so later runs are quick.
#
# Usage: build.sh

set -euo pipefail

export MACOSX_DEPLOYMENT_TARGET=13.0

ADIUM="$(cd "$(dirname "$0")/../../.." && pwd)"
SOURCES="$ADIUM/Dependencies/source"
SRC="$SOURCES/purple-matrix-rs"
OUT="$ADIUM/PurplePlugins/libmatrix.so"

MATRIX_RS_URL=https://github.com/iilonmasc/purple-matrix-rs.git
MATRIX_RS_REV=b2fb0ce276e0d84c8495a9a7a1a955251203c052   # v0.2.1

command -v cargo >/dev/null || { echo "cargo not found: install a stable Rust toolchain from https://rustup.rs" >&2; exit 1; }
command -v just >/dev/null || { echo "just not found: brew install just" >&2; exit 1; }

# Clone at the pin, or check that what is there is the pin. A tree at any other commit is an error
# rather than something to silently build.
if [ ! -d "$SRC/.git" ]; then
	echo "fetching purple-matrix-rs at ${MATRIX_RS_REV:0:7}"
	mkdir -p "$SOURCES"
	git clone -q "$MATRIX_RS_URL" "$SRC"
	git -C "$SRC" checkout -q "$MATRIX_RS_REV"
fi
head="$(git -C "$SRC" rev-parse HEAD)"
[ "$head" = "$MATRIX_RS_REV" ] || { echo "$SRC is at ${head:0:7}, expected ${MATRIX_RS_REV:0:7}" >&2; exit 1; }

# The recipe builds the Rust library in release profile, compiles c/prpl.c against Frameworks/,
# links the bundle, strips it and signs it ad hoc (the signature Xcode's copy phase keeps).
(cd "$SRC" && ADIUM="$ADIUM" just plugin)

cp "$SRC/plugin/libmatrix.so" "$OUT"

# Anything absolute would load a second copy of something; say so rather than ship it.
if otool -L "$OUT" | tail -n +2 | grep -qE '^[[:space:]]+/(Users|opt|usr/local)/'; then
	echo "libmatrix.so links something outside the bundle:" >&2
	otool -L "$OUT" >&2
	exit 1
fi

echo "installed $OUT ($(du -h "$OUT" | cut -f1))"
