#!/usr/bin/env python3
"""Add test files and their fixtures to the "Unit tests" target in Adium.xcodeproj.

Usage:
    Utilities/add-unit-tests.py UnitTests/TestFoo.m [UnitTests/TestBar.m ...]
    Utilities/add-unit-tests.py --all          every UnitTests/Test*.m the target lacks
    Utilities/add-unit-tests.py --all --dry-run

Files join an Xcode project only through project.pbxproj, and the test target is the one
that gains files in batches. A new test file is three things there: a file reference, a
build file, and a line in the target's Sources phase, each with an identifier nothing else
uses. This writes those three for every file named, skips the ones the target already
has, and puts the reference into the "Unit tests" group so Xcode lists it with the rest.
It also makes sure UnitTests/Fixtures is in the target's Resources phase, as a folder
reference, whenever that folder exists, because the tests find their fixtures there.
It never removes anything, and it writes nothing with --dry-run.

Identifiers are derived from the path, so running it twice writes nothing the second
time, and two people adding different files do not collide.
"""

import glob
import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBXPROJ = os.path.join(ROOT, "Adium.xcodeproj", "project.pbxproj")

GROUP = "312ED3D80C7E89CC00A6BDA9"      # PBXGroup "Unit tests"
SOURCES = "312ED3C60C7E875B00A6BDA9"    # PBXSourcesBuildPhase of the target
RESOURCES = "312ED3C50C7E875B00A6BDA9"  # PBXResourcesBuildPhase of the target
FIXTURES = "UnitTests/Fixtures"


def identifier(kind, path, text):
    """24 hex digits, uppercase, as Xcode writes them; stable for a path, unique in the file."""
    digest = hashlib.sha1(f"unit-tests:{kind}:{path}".encode()).hexdigest().upper()
    for start in range(0, len(digest) - 24):
        candidate = digest[start:start + 24]
        if candidate not in text:
            return candidate
    sys.exit(f"could not find a free identifier for {path}")


def section(text, name):
    begin = text.index(f"/* Begin {name} section */\n") + len(f"/* Begin {name} section */\n")
    end = text.index(f"/* End {name} section */", begin)
    return begin, end


def phase_files(text, phase_id):
    match = re.search(phase_id + r" /\* \w+ \*/ = \{.*?files = \(\n(.*?)\t\t\t\);", text, re.S)
    if not match:
        sys.exit(f"no build phase {phase_id} in {PBXPROJ}")
    return match


def insert_into_list(text, match, line):
    """Append one entry to the files = ( ... ) list or children = ( ... ) list a match found."""
    end = match.end(1)
    return text[:end] + line + text[end:]


def add_file(text, path, phase_id, file_type, phase_name):
    name = os.path.basename(path)
    if re.search(r"/\* " + re.escape(name) + r" in " + phase_name + r" \*/,", text):
        return text, False
    ref = identifier("ref", path, text)
    build = identifier("build", path, text + ref)
    file_ref = (f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; "
                + ("fileEncoding = 4; " if file_type != "folder" else "")
                + f"lastKnownFileType = {file_type}; name = {name}; path = {path}; "
                f'sourceTree = "<group>"; }};\n')
    build_file = (f"\t\t{build} /* {name} in {phase_name} */ = {{isa = PBXBuildFile; "
                  f"fileRef = {ref} /* {name} */; }};\n")

    begin, end = section(text, "PBXBuildFile")
    text = text[:end] + build_file + text[end:]
    begin, end = section(text, "PBXFileReference")
    text = text[:end] + file_ref + text[end:]

    text = insert_into_list(text, phase_files(text, phase_id),
                            f"\t\t\t\t{build} /* {name} in {phase_name} */,\n")
    group = re.search(GROUP + r" /\* Unit tests \*/ = \{.*?children = \(\n(.*?)\t\t\t\);", text, re.S)
    if not group:
        sys.exit("no 'Unit tests' group in the project")
    text = insert_into_list(text, group, f"\t\t\t\t{ref} /* {name} */,\n")
    return text, True


def main(argv):
    dry_run = "--dry-run" in argv
    args = [a for a in argv if a not in ("--dry-run", "--all")]
    text = open(PBXPROJ).read()

    if "--all" in argv:
        present = set(re.findall(r"/\* (Test\w+\.m) in Sources \*/,", text))
        args += sorted(p for p in glob.glob(os.path.join(ROOT, "UnitTests", "Test*.m"))
                       if os.path.basename(p) not in present)
    if not args and not os.path.isdir(os.path.join(ROOT, FIXTURES)):
        print(__doc__.strip().splitlines()[0])
        return 64

    added = []
    for arg in args:
        path = os.path.relpath(os.path.abspath(arg), ROOT)
        if not path.startswith("UnitTests/") or not path.endswith(".m"):
            sys.exit(f"{path} is not a test source under UnitTests/")
        if not os.path.exists(os.path.join(ROOT, path)):
            sys.exit(f"{path} does not exist")
        text, changed = add_file(text, path, SOURCES, "sourcecode.c.objc", "Sources")
        if changed:
            added.append(path)

    if os.path.isdir(os.path.join(ROOT, FIXTURES)):
        text, changed = add_file(text, FIXTURES, RESOURCES, "folder", "Resources")
        if changed:
            added.append(FIXTURES + "/ (folder reference, Resources)")

    for path in added:
        print(("would add " if dry_run else "added ") + path)
    if not added:
        print("nothing to add; the target already has every file named")
    elif not dry_run:
        open(PBXPROJ, "w").write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
