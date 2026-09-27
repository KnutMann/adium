#!/bin/bash
# Builds Adium from a fresh checkout, without installing it:
#
#   git clone --recursive <repo> && cd adium && ./bootstrap.sh
#
# The app lands in build/Release/Adium.app. CONFIGURATION=Debug ./bootstrap.sh
# builds the Debug configuration, --rebuild-dependencies builds the bundled
# libraries from source first, and --help lists the rest.
#
# This is install.sh with --build-only. The two were separate scripts doing
# nearly the same thing in nearly the same way, and that is how a fix for the
# ad hoc signing fallback came to reach one of them and not the other, on a
# machine that had no certificate and could not build either. The name stays
# because the README, the issue tracker and other people's notes point at it.

set -eu
cd "$(dirname "$0")"

for option in "$@"; do
	case "$option" in
		-h|-help|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; echo; exec ./install.sh --help ;;
	esac
done

exec ./install.sh --build-only "$@"
