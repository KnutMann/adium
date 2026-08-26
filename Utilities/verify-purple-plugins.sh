#!/bin/bash
# Verifies that the shipped protocol plug-ins are actually shippable.
#
# Born of a day lost to a plug-in that was broken in a way nothing reported:
# it linked libpurple at a build-tree path, so inside Adium it loaded a second
# libpurple, registered its protocol there, and the application's own libpurple
# never saw a protocol arrive. libpurple's directory scan drops such a plug-in
# without a line of log; the first symptom is an account that will not connect.
# A second, separate trap: Xcode's copy phase strips any binary that carries
# only the linker's signature, and a stripped Go runtime does not survive.
#
# Three checks per plug-in, each against one of those failure shapes:
#
#   references   every load command must resolve inside the bundle
#                (@executable_path/@rpath/@loader_path) or the system
#                (/usr/lib, /System). Build-tree and Homebrew paths fail.
#   signature    a real signature, not the linker's: "linker-signed" is what
#                the copy phase strips.
#   function     libpurple itself, the bundle's own copy, scans the plug-in
#                the way Adium does, and the protocol must actually arrive.
#                This is the check that catches whatever shape the next
#                mistake takes.
#
# Usage:
#   Utilities/verify-purple-plugins.sh              repo artifacts (PurplePlugins/ against Frameworks/)
#   Utilities/verify-purple-plugins.sh --app <App>  a built bundle (PlugIns/purple-2 against its Frameworks)
#   ... --quick                                     skip the functional probe (fast, for build phases)
#
# Exits nonzero on the first hard failure, with the offending file and reason.

set -u

cd "$(dirname "$0")/.." || exit 2
REPO="$PWD"

QUICK=no
APP=""
while [ $# -gt 0 ]; do
	case "$1" in
		--app) APP="$2"; shift 2 ;;
		--quick) QUICK=yes; shift ;;
		*) echo "unknown option: $1"; exit 2 ;;
	esac
done

if [ -n "$APP" ]; then
	PLUGIN_DIR="$APP/Contents/PlugIns/purple-2"
	FRAMEWORKS_DIR="$APP/Contents/Frameworks"
	WHAT="app bundle $APP"
else
	PLUGIN_DIR="$REPO/PurplePlugins"
	FRAMEWORKS_DIR="$REPO/Frameworks"
	WHAT="repository artifacts"
fi

[ -d "$PLUGIN_DIR" ] || { echo "FAIL: no plug-in directory at $PLUGIN_DIR"; exit 1; }
[ -d "$FRAMEWORKS_DIR" ] || { echo "FAIL: no frameworks directory at $FRAMEWORKS_DIR"; exit 1; }

fails=0
plugins=("$PLUGIN_DIR"/*.so)
[ -e "${plugins[0]}" ] || { echo "FAIL: no plug-ins in $PLUGIN_DIR"; exit 1; }

echo "== verifying ${#plugins[@]} plug-in(s) in $WHAT"

#--- references and signature, per plug-in --------------------------------------
for so in "${plugins[@]}"; do
	name=$(basename "$so")

	if ! file -b "$so" | grep -q "Mach-O.*arm64"; then
		echo "FAIL $name: not an arm64 Mach-O"
		fails=$((fails+1))
		continue
	fi

	#Only the indented lines are load commands; a fat binary repeats its
	#header once per architecture and those lines are not dependencies.
	bad=$(otool -L "$so" | grep '^	' | awk '{print $1}' \
		| grep -vE '^@(executable_path|rpath|loader_path)/|^/usr/lib/|^/System/')
	if [ -n "$bad" ]; then
		echo "FAIL $name: resolves outside the bundle and the system:"
		echo "$bad" | sed 's/^/        /'
		fails=$((fails+1))
	fi

	sig=$(codesign -dvv "$so" 2>&1)
	if ! echo "$sig" | grep -q "CodeDirectory"; then
		echo "FAIL $name: unsigned (Xcode's copy phase will strip it)"
		fails=$((fails+1))
	elif echo "$sig" | grep -q "linker-signed"; then
		echo "FAIL $name: only linker-signed (Xcode's copy phase treats that as unsigned and strips it)"
		fails=$((fails+1))
	fi
done

#--- the frameworks themselves obey the same reference rule ---------------------
while IFS= read -r -d '' bin; do
	file -b "$bin" | grep -q "Mach-O" || continue
	bad=$(otool -L "$bin" 2>/dev/null | grep '^	' | awk '{print $1}' \
		| grep -vE '^@(executable_path|rpath|loader_path)/|^/usr/lib/|^/System/')
	if [ -n "$bad" ]; then
		echo "FAIL $(basename "$bin"): framework binary resolves outside the bundle and the system:"
		echo "$bad" | sed 's/^/        /'
		fails=$((fails+1))
	fi
done < <(find "$FRAMEWORKS_DIR" -type f \( -name "*.dylib" -o -path "*/Versions/*" \) -print0 2>/dev/null)

[ $fails -gt 0 ] && { echo "== $fails static failure(s); not probing"; exit 1; }
echo "== references and signatures: clean"

[ "$QUICK" = "yes" ] && { echo "== quick mode, functional probe skipped"; exit 0; }

#--- the functional probe: does the protocol actually arrive? -------------------
LIBPURPLE="$FRAMEWORKS_DIR/libpurple.framework/Versions/0/libpurple"
LIBGLIB="$FRAMEWORKS_DIR/libglib.framework/Versions/2.0.0/libglib"
LIBGOBJECT="$FRAMEWORKS_DIR/libgobject.framework/Versions/2.0.0/libgobject"
[ -f "$LIBPURPLE" ] || { echo "FAIL: no libpurple at $LIBPURPLE"; exit 1; }

#Inside the repository's build directory on purpose: some sandboxes refuse to
#execute binaries from the system temp directory, and build/ is gitignored.
mkdir -p "$REPO/build"
RIG=$(mktemp -d "$REPO/build/plugin-probe.XXXXXX")
trap 'rm -rf "$RIG"' EXIT
mkdir -p "$RIG/MacOS" "$RIG/empty"
ln -s "$FRAMEWORKS_DIR" "$RIG/Frameworks"

if ! clang -o "$RIG/MacOS/probe" "$REPO/Utilities/purple-plugin-probe.c" \
	"$LIBPURPLE" "$LIBGLIB" "$LIBGOBJECT" 2>"$RIG/clang.log"; then
	echo "FAIL: could not build the probe:"
	head -5 "$RIG/clang.log" | sed 's/^/        /'
	exit 1
fi

#Some sandboxed environments kill a freshly linked binary on exec with no
#output and no reason given. A debugger launch of the very same file works
#there, so after two plain attempts the probe runs under lldb; on an ordinary
#machine the first attempt simply succeeds and lldb is never consulted.
run_probe() {
	local attempt out
	for attempt in 1 2; do
		out=$("$RIG/MacOS/probe" "$1" 2>/dev/null) && { echo "$out"; return 0; }
		sleep 1
	done
	out=$(xcrun lldb -b -o run -- "$RIG/MacOS/probe" "$1" 2>/dev/null | grep -E "^(prpl |protocols )")
	[ -n "$out" ] && { echo "$out"; return 0; }
	return 1
}

baseline=$(run_probe "$RIG/empty" | awk '/^protocols /{n=$2} END{print n+0}')
if [ -z "$baseline" ]; then
	echo "FAIL: the probe did not run against an empty directory"
	exit 1
fi

for so in "${plugins[@]}"; do
	name=$(basename "$so")
	one="$RIG/one"
	rm -rf "$one"; mkdir "$one"
	cp "$so" "$one/"
	out=$(run_probe "$one")
	got=$(echo "$out" | awk '/^protocols /{n=$2} END{print n+0}')
	added=$(echo "$out" | awk '/^prpl /{seen[$2]=1} END{for (id in seen) printf "%s ", id}')
	if [ "$got" -le "$baseline" ]; then
		echo "FAIL $name: loads without error but registers NO protocol"
		echo "        (the libpurple it registered with is not the libpurple that asked)"
		fails=$((fails+1))
	else
		echo "ok   $name registers a protocol (of: $added)"
	fi
done

if [ $fails -gt 0 ]; then
	echo "== $fails functional failure(s)"
	exit 1
fi
echo "== all plug-ins verified against the bundle's own libpurple"
exit 0
