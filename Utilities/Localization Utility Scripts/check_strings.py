#!/usr/bin/env python3
"""Say what a commit does to the string tables, before the commit happens.

Two things go wrong quietly here, and both have happened.

A new string is written and nobody translates it, so an interface that was whole in
thirty languages is whole in twenty-nine and English in one corner. Nothing announces
this: the missing entry falls back to the key, which is English and looks deliberate.

A string leaves the code and its entries stay, or leaves the tables and then comes
back. The second one cost this project two IRC strings in twenty-eight languages: a
window was deleted by accident, the sweep for orphaned translations removed its
strings quite correctly, and five days later the window was restored without them.

So this reads the staged diff, not the whole tree, and reports only what this commit
changes. Run with --all to audit everything instead.

  check_strings.py [--all] [--reference de.lproj] [--strict]

Exit is 0 with warnings unless --strict, which makes findings fail. Being a warning is
the point: a commit that adds a string is perfectly fine, as long as whoever wrote it
knows they added it.
"""

import argparse
import os
import re
import subprocess
import sys

# AILocalizedString(key, comment), and the two that name a table before the rest.
CALL = re.compile(
    r'AILocalizedString(?P<kind>FromTableInBundle|FromTable|)\s*\(\s*'
    # A key may be written as several literals in a row, which C joins into one before the
    # compiler ever sees it. Three OTR texts are written that way, over four lines each.
    # Taking only the first literal yields a fragment that no table can ever carry, and
    # all three were reported as untranslated while the full key sat in de.lproj.
    r'@"(?P<key>(?:[^"\\]|\\.)*)"(?P<more>(?:\s*"(?:[^"\\]|\\.)*")*)\s*'
    # The table may be spelled either way. AILocalizedStringFromTable takes it as a plain
    # C string in most calls, "EmoticonNames", and as an Objective-C one in others,
    # @"Statuses". Accepting only the second put every emoticon name down as a Localizable
    # key, looked for it in the wrong table, and reported forty of them as untranslated
    # while EmoticonNames.strings had carried them all along.
    r'(?:,\s*(?P<table>@?"(?:[^"\\]|\\.)*"|nil))?',
    re.S)

ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)" =', re.M)

SOURCE = ('.m',)
SEARCHED = ('Source', 'Plugins', 'Frameworks/Adium', 'Frameworks/AIUtilities')


def table_of(match):
    """Which .strings file a call reads from. No table, or nil, means Localizable."""
    if not match.group('kind'):
        return 'Localizable'

    table = match.group('table')
    if not table or table == 'nil':
        return 'Localizable'

    # Both spellings reach here, @"Statuses" and "EmoticonNames", so strip what is actually
    # there rather than a fixed two characters, which ate the first letter of every plain
    # C table name and turned EmoticonNames into moticonName.
    return table.lstrip('@').strip('"')


CONTINUATION = re.compile(r'"((?:[^"\\]|\\.)*)"')


def key_of(match):
    """The whole key, with the literals that follow it joined on."""
    key = match.group('key')
    more = match.group('more')
    if more:
        key += "".join(CONTINUATION.findall(more))
    return key


def keys_in(text):
    """The (table, key) pairs a piece of source asks for."""
    return {(table_of(m), key_of(m)) for m in CALL.finditer(text)}


def keys_in_tree():
    found = set()
    for root in SEARCHED:
        for dirpath, _, names in os.walk(root):
            if '/build' in dirpath:
                continue
            for name in names:
                if name.endswith(SOURCE):
                    path = os.path.join(dirpath, name)
                    found |= keys_in(open(path, errors='replace').read())
    return found


def entries_in(path):
    try:
        raw = open(path, 'rb').read()
    except OSError:
        return set()

    encoding = 'utf-16' if raw[:2] in (b'\xff\xfe', b'\xfe\xff') else 'utf-8'
    return set(ENTRY.findall(raw.decode(encoding, 'replace')))


def string_roots():
    """Every directory in the tree that holds .lproj tables.

    The application keeps its own under Resources, and several plug-ins keep theirs beside
    their code: Purple Service has thirty language tables of its own. Looking only at
    Resources is how this check spent weeks reporting strings as untranslated that had been
    translated all along, which is the one thing a check like this must not do, because a
    warning nobody can act on is a warning everybody learns to ignore.
    """
    roots = []
    for base in ['.', 'Plugins', 'Frameworks']:
        if not os.path.isdir(base):
            continue
        candidates = ([base] if base == '.' else
                      [os.path.join(base, d) for d in sorted(os.listdir(base))])
        for candidate in candidates:
            resources = os.path.join(candidate, 'Resources')
            if candidate == '.':
                resources = 'Resources'
            if not os.path.isdir(resources):
                continue
            # A .lproj alone is not enough. Every bundled C library carries one holding
            # nothing but an InfoPlist.strings, which is a bundle's own name and version
            # and not a translated string. Only a root with a real table counts.
            if any(name.endswith('.strings') and name != 'InfoPlist.strings'
                   for lproj in os.listdir(resources)
                   if lproj.endswith('.lproj') and os.path.isdir(os.path.join(resources, lproj))
                   for name in os.listdir(os.path.join(resources, lproj))):
                roots.append(resources)
    return roots


def tables_for(language):
    """Every table that language has, as {table name: set of keys}.

    Merged across all roots. A key counts as translated when any table of that name carries
    it, which is what the question actually is: the source asks for a string, and either
    some table this build ships answers it or none does.

    The keys stay exactly as the file spells them, escapes and all, because that is also
    how the source spells them: a literal in a .m file carries a backslash and an n, not a
    newline, until the compiler reads it. Turning one side back into real characters and
    not the other would make every string containing a newline or a quote look untranslated
    for ever, which is worse than useless in something meant to be trusted.
    """
    tables = {}
    for root in string_roots():
        directory = os.path.join(root, language)
        if not os.path.isdir(directory):
            continue
        for name in os.listdir(directory):
            if name.endswith('.strings') and name != 'InfoPlist.strings':
                table = name[:-len('.strings')]
                tables.setdefault(table, set()).update(
                    entries_in(os.path.join(directory, name)))
    return tables


def languages():
    seen = set()
    for root in string_roots():
        seen.update(d for d in os.listdir(root) if d.endswith('.lproj'))
    return sorted(seen)


def staged_change():
    """The keys this commit adds to the source and the keys it takes out of it."""
    diff = subprocess.run(['git', 'diff', '--cached', '-U0', '--', '*.m'],
                          capture_output=True, text=True, errors='replace').stdout

    added = "\n".join(l[1:] for l in diff.split("\n") if l.startswith('+') and not l.startswith('+++'))
    removed = "\n".join(l[1:] for l in diff.split("\n") if l.startswith('-') and not l.startswith('---'))

    return keys_in(added), keys_in(removed)


def report(new, orphaned, reference):
    """Both lists, or silence. Silence is the ordinary case and deserves no line of its own."""
    if new:
        print(f'\n  {len(new)} new string{"s" if len(new) != 1 else ""}, with no entry in {reference}:',
              file=sys.stderr)
        for table, key in sorted(new)[:20]:
            shown = key if len(key) <= 68 else key[:66] + '…'
            print(f'      [{table}] {shown}'.replace("\n", " "), file=sys.stderr)
        if len(new) > 20:
            print(f'      ... and {len(new) - 20} more', file=sys.stderr)
        print('\n  Translate them, or they reach every reader in English:', file=sys.stderr)
        print('      Utilities/Localization\\ Utility\\ Scripts/add_strings.py '
              f'Resources/{reference}/Localizable.strings additions.json', file=sys.stderr)

    if orphaned:
        print(f'\n  {len(orphaned)} string{"s" if len(orphaned) != 1 else ""} no longer asked for '
              'anywhere, while the tables still carry them:', file=sys.stderr)
        for table, key in sorted(orphaned)[:20]:
            shown = key if len(key) <= 68 else key[:66] + '…'
            print(f'      [{table}] {shown}'.replace("\n", " "), file=sys.stderr)
        if len(orphaned) > 20:
            print(f'      ... and {len(orphaned) - 20} more', file=sys.stderr)
        print('\n  Leaving them costs nothing and removing them is safe only once you are sure\n'
              '  nothing reaches them another way, through a plist or from libpurple at runtime.',
              file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--all', action='store_true',
                        help='audit the whole tree instead of the staged change')
    parser.add_argument('--reference', default='de.lproj',
                        help='the language kept complete, against which new strings are judged')
    parser.add_argument('--strict', action='store_true', help='fail rather than warn')
    parser.add_argument('-h', '--help', action='store_true')
    options = parser.parse_args()

    if options.help:
        print(__doc__)
        return 0

    if not os.path.isdir('Resources'):
        print('check_strings: run me from the top of the tree', file=sys.stderr)
        return 0

    reference = tables_for(options.reference)
    live = keys_in_tree()

    if options.all:
        new = {(t, k) for t, k in live if k not in reference.get(t, set())}
        known = {(t, k) for t, keys in reference.items() for k in keys}
        orphaned = known - live
    else:
        added, removed = staged_change()

        # Added and already translated is the ordinary case of moving a call around
        new = {(t, k) for t, k in added if k not in reference.get(t, set())}

        # Removed from one place and still called from another is a move, not a loss
        orphaned = {(t, k) for t, k in removed
                    if (t, k) not in live and k in reference.get(t, set())}

    if not new and not orphaned:
        return 0

    print('\nStrings:', file=sys.stderr)
    report(new, orphaned, options.reference)

    if options.strict:
        print('\n  Refusing the commit because --strict was asked for.\n', file=sys.stderr)
        return 1

    print('\n  This is a warning, not a refusal. The commit goes ahead.\n', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
