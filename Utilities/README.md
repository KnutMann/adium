# Developer utilities

Tools that are not part of any build. Each is run by hand; nothing here is
wired into Xcode, the Makefile or continuous integration.

The one-line summaries come from each script's own header, and are written
here by Utilities/script-index.py. A script listed without one has no header,
and that is the thing to fix rather than to describe here.

## Utilities

* `AppcastReplaceItem.py`  Usage:

## Build

* `Build/buildDMG.pl`  **no header**
* `Build/buildDaily.sh`  filename: buildDaily.sh

## Utilities

* `FindMacroMisuses.py`  Find places where a macro's name was written inside a string instead of used
* `GenerateColorTests.py`  Generate the test methods for +colorWithHTMLString:

## Localization Utility Scripts

* `Localization Utility Scripts/add_strings.py`  Add entries to a .strings file without disturbing what is already in it
* `Localization Utility Scripts/check_strings.py`  Say what a commit does to the string tables, before the commit happens

## Utilities

* `collect-licenses.sh`  Gather the licence of everything Adium ships, from the trees it was built from
* `draw-entry-icons.py`  Draw the three message field buttons (Resources/entry_*.png) in the style of the old smiley: a 16 pt glyph in one
* `package-release.sh`  Package a built Adium.app for people to download: a zip and a disk image
* `script-index.py`  Regenerate Testing/README.md and Utilities/README.md from the scripts themselves
* `stamp-build.sh`  Writes into the built Info.plist what this build is: when it was made, to the
* `tosupportpage.sh`  Usage: tosupportpage path/to/www/help
* `verify-claude-md.sh`  Check that the CLAUDE.md files still describe the tree they describe
* `verify-licenses.sh`  Every binary Adium ships must have a licence beside it
* `verify-purple-plugins.sh`  Verifies that the shipped protocol plug-ins are actually shippable
