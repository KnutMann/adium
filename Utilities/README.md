# Developer utilities

Tools that are not part of any build. Each is run by hand; nothing here is
wired into Xcode, the Makefile or continuous integration.

The one-line summaries come from each script's own header, and are written
here by Utilities/script-index.py. A script listed without one has no header,
and that is the thing to fix rather than to describe here.

## Utilities

* `FindMacroMisuses.py`  Find places where a macro's name was written inside a string instead of used
* `GenerateColorTests.py`  Generate the test methods for +colorWithHTMLString:

## Localization Utility Scripts

* `Localization Utility Scripts/add_strings.py`  Add entries to a .strings file without disturbing what is already in it
* `Localization Utility Scripts/check_strings.py`  Say what a commit does to the string tables, before the commit happens

## Utilities

* `add-unit-tests.py`  Add test files and their fixtures to the "Unit tests" target in Adium.xcodeproj
* `collect-licenses.sh`  Gather the licence of everything Adium ships, from the trees it was built from
* `draw-entry-icons.py`  Draw the three message field buttons (Resources/entry_*.png) in the style of the old smiley: a 16 pt glyph in one
* `make-dmg-layout.sh`  Write the release disk image's Finder layout: Other/Artwork/Disk Image/DS_Store
* `notarize.sh`  Notarise a signed Adium.app or a disk image and staple the ticket to it
* `package-release.sh`  Package a built Adium.app for people to download: a zip and a disk image
* `run-unit-test-file.sh`  Build one or more unit test files into a throwaway bundle and run them, without xcodebuild
* `script-index.py`  Regenerate Testing/README.md and Utilities/README.md from the scripts themselves
* `stamp-build.sh`  Writes into the built Info.plist what this build is: when it was made, to the
* `verify-claude-md.sh`  Check that the CLAUDE.md files still describe the tree they describe
* `verify-licenses.sh`  Every binary Adium ships must have a licence beside it
* `verify-purple-plugins.sh`  Verifies that the shipped protocol plug-ins are actually shippable
