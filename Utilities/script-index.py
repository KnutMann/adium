#!/usr/bin/env python3
"""Regenerate Testing/README.md and Utilities/README.md from the scripts themselves.

A list of scripts maintained by hand drifts away from the scripts, the way
License.txt drifted away from the libraries it claimed to describe. So the
one-line summary of each script is read out of that script's own header, and a
script with no header shows up in the list saying so, which is the point.

    Utilities/script-index.py
"""
import pathlib
import re
import subprocess
import sys

SECTIONS = (
	("Testing", "Test harnesses",
	 "One directory per thing under test, each harness beside what it exercises.\n"
	 "Nothing here runs automatically: these are run by a person, usually against a\n"
	 "running service or a built application, and several need a server or a device."),
	("Utilities", "Developer utilities",
	 "Tools that are not part of any build. Each is run by hand; nothing here is\n"
	 "wired into Xcode, the Makefile or continuous integration."),
)


def summary(path):
	"""The first explaining line of a script's header, or "" if it has none."""
	try:
		lines = pathlib.Path(path).read_text(errors="replace").splitlines()
	except OSError:
		return ""
	i = 1 if lines and lines[0].startswith("#!") else 0
	while i < len(lines) and not lines[i].strip():
		i += 1
	if i >= len(lines):
		return ""
	stripped = lines[i].strip()
	if stripped.startswith(('"""', "'''")):
		quote = stripped[:3]
		first = stripped[3:].strip()
		if first:
			return first.rstrip(".").rstrip('"').rstrip("'")
		for line in lines[i + 1:]:
			if line.strip().startswith(quote):
				break
			if line.strip():
				return line.strip().rstrip(".")
		return ""
	if stripped.startswith("#"):
		text = stripped.lstrip("#").strip()
		if text:
			return text.rstrip(".")
		for line in lines[i + 1:]:
			if not line.startswith("#"):
				break
			text = line.lstrip("#").strip()
			if text:
				return text.rstrip(".")
	return ""


def main():
	root = pathlib.Path(__file__).resolve().parent.parent
	files = subprocess.run(["git", "-C", str(root), "ls-files"],
	                       capture_output=True, text=True).stdout.splitlines()
	for directory, title, blurb in SECTIONS:
		rows = [(f[len(directory) + 1:], summary(root / f))
		        for f in sorted(files)
		        if f.startswith(directory + "/") and re.search(r"\.(sh|py|rb|pl)$", f)]
		out = ["# %s" % title, "", blurb, "",
		       "The one-line summaries come from each script's own header, and are written",
		       "here by Utilities/script-index.py. A script listed without one has no header,",
		       "and that is the thing to fix rather than to describe here."]
		group = object()
		for name, text in rows:
			this = name.split("/")[0] if "/" in name else directory
			if this != group:
				group = this
				out += ["", "## %s" % this, ""]
			out.append("* `%s`  %s" % (name, text if text else "**no header**"))
		(root / directory / "README.md").write_text("\n".join(out) + "\n")
		missing = sum(1 for _, t in rows if not t)
		print("  %s/README.md: %d scripts, %d without a header" % (directory, len(rows), missing))


if __name__ == "__main__":
	main()
