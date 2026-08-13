# tdlib-purple patches

`Dependencies/source` is not under version control, so these files are the only record of what the
Telegram plugin in `PurplePlugins/libtelegram-tdlib.so` was built from.

Base revision: `43e6cc2f14ccd08171b1515f6216f4bbf84eed80` of
<https://github.com/BenWiederhake/tdlib-purple> (a fork of ars3niy/tdlib-purple at 0.8.1). Both
repositories are dormant — ars3niy's last commit is from December 2021, BenWiederhake's is archived.
The living fork is <https://github.com/adrighem/tdlib-purple>, which needs tdlib 1.8.65 where we
build 1.8.35, and which has rewritten the scheduling this patch touches. Moving to it is a project
of its own.

## adium.patch

Four fixes, all offered upstream separately:

**The scheduling, ten call sites.** `g_idle_add`, `g_timeout_add`, `g_timeout_add_seconds` and
`g_source_remove` become the `purple_timeout_*` wrappers. libpurple lets a UI supply its own event
loop through `PurpleEventLoopUiOps`, and Adium does exactly that, onto GCD — so a source handed
straight to GLib is never dispatched. The decisive one is `transceiver.cpp`
(`TdTransceiver::pollThreadLoop`), the only path by which a tdlib response reaches the main thread:
without it the account sits on "Connecting" forever, no database is created, no socket is opened,
and nothing is logged, because the authorization state machine never receives its first update.

**`tgprpl_add_buddy` no longer resolves a username for a contact we already have.** The function
reads the buddy name into a variable called `phoneNumber` and asks the server to look it up. When a
UI files a known buddy into another group, that name is one of the plugin's own `id<n>` forms, so
the server answers 400 `USERNAME_NOT_OCCUPIED` — and the blist node has already been removed by
then. Telegram has no contact groups, so that call is purely local and nothing needs sending.

**`tgprpl_request_delete_contact` no longer deletes a contact that is merely being unfiled.**
libpurple keeps one node per group, so removing a contact from one of several groups arrives here
exactly as a deletion does, and the contact and its server-side history were deleted outright.
Counting the nodes first distinguishes the two.

**The deletion confirmation is back.** It was commented out upstream in 2020 with no rationale
(`0812be1` in ars3niy's tree), leaving contact and chat history deleted with no prompt, one keystroke
away in some UIs. It is reinstated as `purple_request_action`, matching the other confirmations in
the file. This one is a local decision: the upstream question is filed as an issue rather than a
patch, because disabling it was deliberate and there may be a reason we cannot see.

Also included: `purpleBuddyNameToSecretChatId` compared two characters of the six-character prefix
`secret` and then parsed from offset 6, so a username like `setup12345` came back as secret chat
12345. The add_buddy fix consults that helper, so it had to be right first.

## Rebuilding the plugin

There is no build phase for this; it is done by hand.

    cd Dependencies/source/tdlib-purple
    git apply ../../patches/tdlib-purple/adium.patch     # if starting from a fresh checkout
    cmake -B build -S . -DTd_DIR=<adium>/Dependencies/build/tdlib/lib/cmake/Td -DNoVoip=True
    cmake --build build

Then, and this step is not optional:

    ./Dependencies/patches/tdlib-purple/relink_for_bundle.sh PurplePlugins/libtelegram-tdlib.so

cmake records absolute paths to whatever pkg-config found, which pulls a second copy of glib and
libpurple into a process that already has the bundled ones. Two glibs mean two sets of global
tables: the protocol registers itself into one while libpurple reads the other, and the account
hangs on "Connecting" with no error — indistinguishable from the scheduling bug above, and it cost a
day to find once. The script rewrites the paths and refuses to finish if any absolute one remains.
