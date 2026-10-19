#!/bin/bash
# Check that the CLAUDE.md files still describe the tree they describe.
#
# A map that lies is worse than no map, and this repository has three fresh
# examples of documentation drifting away from what it documented: a roadmap
# table where three of twenty items had moved, a License.txt naming one library
# that was removed years earlier, and a patch note describing a source tree the
# shipped plug-in was not built from.
#
# What this can check mechanically is the kind of drift that matters most: a
# document pointing at something that no longer exists, and a protocol arriving
# without being mentioned. What it cannot check is a sentence that quietly stops
# being true while every name in it still resolves. That still wants a reader.
#
#   Utilities/verify-claude-md.sh
set -uo pipefail

cd "$(dirname "$0")/.."
# The file list is found inside, not passed in: one of these paths has a space in
# it, and a shell that splits on whitespace turns "Plugins/Purple Service" into two
# files that do not exist.
python3 - <<'PY'
import re, subprocess, sys, pathlib

docs = [d for d in subprocess.run(["git", "ls-files"], capture_output=True, text=True)
        .stdout.splitlines() if d == "CLAUDE.md" or d.endswith("/CLAUDE.md")]
if not docs:
    sys.exit("no CLAUDE.md anywhere")
print("== checking %d CLAUDE.md file(s)" % len(docs))
text = "\n".join(pathlib.Path(d).read_text(errors="replace") for d in docs)
tracked = set(subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.splitlines())
bases = {f.rsplit("/", 1)[-1] for f in tracked}
stems = {f.rsplit("/", 1)[-1].rsplit(".", 1)[0] for f in tracked if f.endswith((".h", ".m"))}

bad = 0

# Every file named with an extension has to exist somewhere, by path or by name.
# A name written with a wildcard, "AI*ControllerProtocol.h", stands for a family
# and is checked by its tail instead.
for name in sorted(set(re.findall(
		r"\b([A-Za-z0-9_+*.-]+\.(?:m|h|c|cpp|plist|sh|py|xib|xcconfig|pbxproj|so|dylib|scpt))\b", text))):
	if "*" in name:
		tail = name.split("*")[-1]
		if any(f.endswith(tail) for f in tracked):
			continue
	elif name not in bases and name not in tracked and not any(f.endswith("/" + name) for f in tracked):
		pass
	else:
		continue
	if True:
		print("  MISSING FILE   %s" % name)
		bad += 1

# Every Adium-style class named has to have a header or an implementation.
# Frameworks and macros share the prefix, so a name that is a folder is not a class.
folders = {f.split("/")[0] for f in tracked} | {f.split("/")[1] for f in tracked if "/" in f}
# Not every AI-prefixed word is a class. A file stem, a folder, a macro and a
# preference key all share the prefix, and only a class has a header beside it.
keys = set(re.findall(r"defaults write \S+ (\S+)", text))
macros = set(subprocess.run(
	["bash", "-c", "git grep -h -E '^[[:space:]]*#[[:space:]]*define[[:space:]]+[A-Za-z_]' -- '*.h' '*.m' | "
	 "sed -E 's/^[[:space:]]*#[[:space:]]*define[[:space:]]+([A-Za-z_0-9]+).*/\\1/'"],
	capture_output=True, text=True).stdout.split())
for name in sorted(set(re.findall(r"\b((?:AI|ES|CB|SL|MM|AH|AX|NEH|RAF)[A-Z][A-Za-z0-9_]{3,})\b", text))):
	if name in stems or name in folders or name in keys or name in macros:
		continue
	if any(f.rsplit("/", 1)[-1].startswith(name + ".") for f in tracked):
		continue
	if re.search(r"\b%s[A-Za-z]" % re.escape(name), text):   # ein Wortanfang, kein ganzer Name
		continue
	print("  MISSING CLASS  %s" % name)
	bad += 1

# A protocol in the descriptor that no document mentions is the one kind of
# staleness this repository actually produces: six protocols were added in ninety
# days, and each needs a word in Plugins/Purple Service/CLAUDE.md.
plist = pathlib.Path("Plugins/Purple Service/AIPurpleServiceDescriptors.plist")
if plist.exists():
	# By the name the descriptor itself gives the service, not by guessing at the
	# protocol id: prpl-hehoe-presage is Signal and prpl-eionrobb-msteams is Teams,
	# and no document should have to spell either id out.
	import plistlib
	for key, row in plistlib.loads(plist.read_bytes()).items():
		name = (row.get("ShortDescription") or "").split(" (")[0]
		if name and not re.search(r"\b%s\b" % re.escape(name), text, re.I):
			print("  UNMENTIONED    %s (%s) is a service and no CLAUDE.md names it" % (name, key))
			bad += 1

print("  %d problem(s)" % bad)
sys.exit(1 if bad else 0)
PY
status=$?
[ $status -eq 0 ] && echo "== the maps still match the tree"
exit $status
