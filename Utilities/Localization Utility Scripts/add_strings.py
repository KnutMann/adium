#!/usr/bin/env python3
"""Add entries to a .strings file without disturbing what is already in it.

Adium's string tables are UTF-16 and roughly sorted by key, and they are edited by
hand often enough that rewriting one wholesale is a good way to lose somebody's work.
This inserts, in place, only the keys that are not already there, at the position the
existing ordering suggests, and leaves every other byte alone.

  add_strings.py <path to Localizable.strings> <json file: {key: value}>

The JSON is read as UTF-8. Keys already present are reported and skipped, never
overwritten: a translator's wording beats ours.

Refuses to write when a value's format specifiers do not match its key's. A
translation that drops a %@ silently loses the value it should have shown, and one
that adds a %@ reads uninitialised stack.
"""

import json
import re
import sys

ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)" =')
SPECIFIER = re.compile(r'%(?:\d+\$)?[@dfsu%]')


def specifiers(text):
    """The format specifiers in order, with positional ones reduced to their type."""
    return [m.group(0)[-1] for m in SPECIFIER.finditer(text) if not m.group(0).endswith('%%')]


def escape(text):
    return text.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    path, additions_path = sys.argv[1], sys.argv[2]
    additions = json.load(open(additions_path, encoding='utf-8'))

    problems = []
    for key, value in additions.items():
        if sorted(specifiers(key)) != sorted(specifiers(value)):
            problems.append(f'{key!r} has {specifiers(key)}, translation has {specifiers(value)}')
    if problems:
        print('refusing to write, format specifiers do not match:', file=sys.stderr)
        for p in problems:
            print('  ' + p, file=sys.stderr)
        return 1

    raw = open(path, 'rb').read()
    encoding = 'utf-16' if raw[:2] in (b'\xff\xfe', b'\xfe\xff') else 'utf-8'
    lines = raw.decode(encoding).split('\n')

    added = skipped = 0
    for key in sorted(additions, key=str.lower):
        present = [(i, m.group(1)) for i, m in ((i, ENTRY.match(l)) for i, l in enumerate(lines)) if m]
        if any(k == key for _, k in present):
            skipped += 1
            continue
        position = next((i for i, k in present if k.lower() > key.lower()), len(lines))
        lines.insert(position, f'"{escape(key)}" = "{escape(additions[key])}";')
        added += 1

    open(path, 'wb').write('\n'.join(lines).encode(encoding))
    print(f'{path}: {added} added, {skipped} already present')
    return 0


if __name__ == '__main__':
    sys.exit(main())
