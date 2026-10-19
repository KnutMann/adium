# The libraries are built here and committed as binaries

**Decision.** The nineteen libraries Adium bundles and the seven protocol
plug-ins are built by `Dependencies/build.sh` and then committed: 1446 files
under `Frameworks/` and seven under `PurplePlugins/`. A fresh clone builds the
application without running anything in `Dependencies/`.

**Why.** The alternative is that every contributor builds glib, libpurple,
OpenSSL, libotr and the image codecs before they can compile a line, which takes
the better part of an hour and needs a Homebrew toolchain of autoconf, automake,
libtool, pkg-config, meson, cmake and ninja. Issue #5 exists because for a while
only one Mac could build this fork at all. Committing the output is what turns
"clone it and open Xcode" into something that works.

The cost of that is a repository that is large and that contains binaries nobody
can read, so two things make up for it: every source is fetched from a pinned
address and checked against a recorded SHA-256 before it unpacks, and every
recipe is in the tree. What ships can be reproduced, and reproducing it is how
the Telegram plug-in was checked before the last merge: five minutes, and the
result carried the same exported symbols as the committed one.

**What it costs.** A binary in a repository is a promise that somebody can
rebuild it, and the promise has to be kept. Three things keep it: the recipe
lives in `Dependencies/phases/`, the pin and the checksum live in the script, and
`Utilities/verify-purple-plugins.sh` asks the bundle's own libpurple whether each
plug-in's protocol actually arrives, because a plug-in linked against a stray
copy of libpurple loads cleanly and registers its protocol where the application
never looks.

The other cost is drift between the recipe and the artefact, and it has happened:
the Telegram plug-in announced itself as 0.8.1 for weeks while the notes beside
it described a 2.1.0 tree, because a rebuild went into the wrong directory. A
plug-in states its own version, and that is the thing to believe.

**Verified** 19 October 2026: 1446 files tracked under `Frameworks/`, seven under
`PurplePlugins/`.
