# Dependencies/

What Adium links against beyond macOS, and how it got there. Three kinds of
thing, and the distinction is the whole point of this folder.

Checked in: the prebuilt arm64 frameworks and dylibs under Frameworks/ and
the protocol plug-ins under PurplePlugins/. A fresh clone builds without ever
running anything here.

Fetched, by fetch.sh, which install.sh runs before every build: the
MMTabBarView submodule; webrtc/fetch-webrtc.sh, a prebuilt WebRTC.xcframework
checked against a pinned SHA-256 and kept out of git for its size; and
picomemo/fetch-picomemo.sh, which fetches and builds the cryptographic half
of OMEMO from a pinned commit. All three are idempotent and quiet when there
is nothing to do.

Built, by build.sh, from Dependencies/ and only when a library has to move:
it sources phases/ in order (utility.sh for fetching and checksums,
build_dependencies.sh for the base libraries, then libffi, the image codecs,
OpenSSL, the OTR trio of gpg-error, gcrypt and libotr, libpurple, and
make_frameworks.sh, which turns the dylibs into frameworks through
framework_maker/frameworkize.py with the *-Info.plist files here).
build_other.sh and build_vv_dependencies.sh are not sourced; they are
upstream leftovers. Every source is fetched from a pinned address and checked
against a recorded SHA-256 before it unpacks, and the version each library is
stamped with must match Base.xcconfig. copy_frameworks.sh puts the output
where the project looks for it. opus/build-opus.sh builds the voice note
codec separately; rebuild-whatsmeow.sh rebuilds the WhatsApp plug-in;
refresh-libpurple-framework.sh swaps a freshly built libpurple into the
framework the application loads. patches/ holds every local change on top of
a library's release, one folder per library, with a README where the change
needs explaining. The build needs autoconf, automake, libtool, pkg-config,
meson, cmake and ninja from Homebrew and takes the better part of an hour.

build/, source/ and Frameworks/ inside this folder are build material and
ignored; source/ runs to gigabytes and some scripts here expect it, so do not
clear it casually.

## Adding or moving a library

The rule is in the README under "Adding a library", and the test is one line:
every path under Frameworks/ or Dependencies/build named in an xcconfig must
be produced by a script here, and listed in the README's table of bundled
binaries or among the three fetched things. The script, the binary and the
table row land in the same change. Every shipped binary also carries its
licence in the bundle: Utilities/collect-licenses.sh gathers them from the
source trees or the pinned release URL, and Utilities/verify-licenses.sh
checks the built application, which continuous integration runs. A library
added without its licence fails there.
