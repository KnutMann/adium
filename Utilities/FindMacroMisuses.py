#!/usr/bin/env python3
"""Find places where a macro's name was written inside a string instead of used.

Adium defines a great many names with #define, preference groups and keys above
all, and a name in quotes looks exactly like the name used. `@"PREF_GROUP_GENERAL"`
compiles, reads correctly to a human, and silently means something different from
`PREF_GROUP_GENERAL`. This walks the source for that shape.

It reports candidates, not faults. A macro named after the string it expands to
will match itself, and so will a comment quoting a macro on purpose, so every hit
wants a human. What it does is narrow the search from the whole tree to a list.

    Utilities/FindMacroMisuses.py [directories...]

Defaults to our own source. Frameworks/ as a whole is not a default: the built
third-party frameworks live there, and their headers bury the signal.

Rewritten in October 2026. The version before had been dead since Adium left
Subversion: it descended only into directories containing a .svn folder, so in a
git checkout it walked nothing and always printed nothing.
"""
import os
import re
import sys

SUFFIXES = (".m", ".h", ".c")
DEFINE = re.compile(r"^\s*#\s*define\s+([A-Za-z_][A-Za-z_0-9]*)")


def sources(roots):
	for root in roots:
		for directory, dirnames, filenames in os.walk(root):
			dirnames[:] = [d for d in dirnames if not d.startswith(".")]
			for name in filenames:
				if name.endswith(SUFFIXES):
					yield os.path.join(directory, name)


def main():
	roots = sys.argv[1:] or ["Source", "Plugins", "Frameworks/Adium",
	                         "Frameworks/AIUtilities",
	                         "Frameworks/AutoHyperlinks Framework"]
	roots = [r for r in roots if os.path.isdir(r)]
	if not roots:
		sys.exit("none of those directories exist; run this from the repository root")

	files = list(sources(roots))

	macros = set()
	for path in files:
		with open(path, encoding="utf-8", errors="replace") as f:
			for line in f:
				m = DEFINE.match(line)
				if m:
					macros.add(m.group(1))
	# One character and two character names match far too much to be worth reading.
	quoted = {'"%s"' % name: name for name in macros if len(name) > 2}

	hits = 0
	for path in files:
		with open(path, encoding="utf-8", errors="replace") as f:
			for number, line in enumerate(f, start=1):
				if DEFINE.match(line):
					continue
				for text, name in quoted.items():
					if text in line:
						print("%s:%d: %s" % (path, number, line.strip()))
						hits += 1
						break

	print("\n%d macro definitions, %d lines worth a look" % (len(macros), hits),
	      file=sys.stderr)


if __name__ == "__main__":
	main()
