# purple2-ircv3

<https://github.com/EionRobb/purple2-ircv3>, a fork of libpurple's built in IRC protocol that adds
IRCv3 capabilities. Built here at `0e73297`.

Not shipped yet. The plugin builds and loads, but Adium has no service and account class for it, so
nothing offers it when adding an account. That is task 21, the generic service binding; this
protocol is its first candidate.

## Why it is worth having

* `message-tags` gives typing notifications, which built in IRC has none of
* `server-time` gives relayed messages their real timestamp, which matters behind a bouncer
* `metadata-2` gives user avatars
* `echo-message` and `labeled-response` stop own messages appearing twice
* `invite-notify`, `utf8-only`, and an attempt at STS

It also carries the fix from `../pidgin-2.14.14/irc/irc.c.patch`, which its author ported after
seeing it: the send queue was driven by a raw GLib timeout, so under a user interface with its own
event loop nothing in it ever went out. There is no raw GLib scheduling left anywhere in the tree,
which is the condition for it working here at all.

## It does not replace the built in IRC

It registers as `prpl-eionrobb-ircv3`, not `prpl-irc`, and Adium's IRC is compiled into libpurple
rather than loaded, so both exist side by side. Existing IRC accounts stay on the built in protocol
and do not migrate.

## CMakeLists.txt

The upstream `Makefile` covers Linux and mingw32. Neither branch builds here: it passes `-shared`
where macOS needs a loadable module, hardcodes Macports include paths, and asks pkg-config for a
`libsasl2.pc` that macOS does not ship. The file beside this builds it instead. Drop it into a
checkout:

    cp CMakeLists.txt <checkout>/
    cd <checkout>
    PKG_CONFIG_PATH=<adium>/Dependencies/build/lib/pkgconfig cmake -B build -S .
    cmake --build build

Then, as for every plugin here:

    ./Dependencies/patches/tdlib-purple/relink_for_bundle.sh <checkout>/build/libircv3.so

Without that the plugin carries absolute paths to the libpurple and glib it was built against, and
loading it puts a second copy of each into a process that already has them. See the comment at the
top of that script for what that looks like from the outside.

Worth offering upstream once it has actually run here.
