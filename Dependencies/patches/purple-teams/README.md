# purple-teams

<https://github.com/EionRobb/purple-teams>, a third party Microsoft Teams protocol for libpurple.
Built here at `62f6fff`.

Bound as `prpl-eionrobb-msteams` through the descriptor and the account plan, so it needs no
Objective-C of its own. It is the third protocol to arrive that way, after Telegram and IRCv3.

## Why it fits here

Signing in is the part that usually stops a third party Teams client on a Mac, because Microsoft
wants a browser. This protocol asks for one through `purple_notify_uri` and takes the code back
through `purple_request_input`, and Adium implements both. No web view has to be embedded, and no
account class has to know anything about it.

It brings its own options, so the account page builds itself: the tenant sits with the account,
history and meeting settings under Options. There is no password, because the protocol says so with
`OPT_PROTO_NO_PASSWORD`, and no server or port, because it declares neither.

## What it does not do

Calls. It offers a link to the Teams website instead. Reactions and threads exist but read poorly in
a client that was not built around them.

## CMakeLists.txt

The upstream `Makefile` has a Darwin branch, but it does not build here: it passes `-shared` where
macOS needs a loadable module, sets `CC` to gcc and hardcodes Macports include paths. The file
beside this builds it instead. Drop it into a checkout:

    cp CMakeLists.txt <checkout>/
    cd <checkout>
    PKG_CONFIG_PATH=<adium>/Dependencies/build/lib/pkgconfig cmake -B build -S . -DCMAKE_OSX_ARCHITECTURES=arm64
    cmake --build build

Then, as for every plugin here:

    ./Dependencies/patches/purple-teams/relink_for_bundle.sh <checkout>/build/libteams.so

Without that the plugin carries absolute paths to the libpurple, glib and json-glib it was built
against, and loading it puts a second copy of each into a process that already has them. This one
needs more mappings than the others because it uses gio, gobject and json-glib directly, which is
why it has a script of its own rather than sharing tdlib-purple's.

## The personal variant

The same source builds `libteams-personal.so` with `-DENABLE_TEAMS_PERSONAL`, for consumer Microsoft
accounts rather than work ones. Not built here; it would be a second protocol id, a second descriptor
and a second plan, and nobody has asked for it.
