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

## Moving to adrighem's tree

Under way as of 2026-08-15. The plugin in `PurplePlugins/` is still the 0.8.1 build described above;
what follows is the record of the move, not of what ships today.

adrighem/tdlib-purple 2.1.0 was built against tdlib 1.8.65 and run in Adium with a real account: it
connects, reuses the tdlib session that 1.8.35 created, receives and sends, and schedules timeouts
from the libpurple thread. Three changes were needed and all three are offered upstream:

* [#29](https://github.com/adrighem/tdlib-purple/pull/29): master does not compile.
  `ops->request_yes_no` is not a member of `PurpleRequestUiOps`.
* [#30](https://github.com/adrighem/tdlib-purple/pull/30): `tgprpl_close` deletes the client before
  clearing the connection's protocol data, so a reentrant close deletes it twice.
* [#31](https://github.com/adrighem/tdlib-purple/pull/31): the scheduling, which is what
  `adium.patch` above solves locally for the 0.8.1 line. Rather than substituting the calls, the
  plugin dispatches on a context of its own which is driven from libpurple's event loop through
  `purple_input_add` and `purple_timeout_add`. Answers upstream issue 26.

When those land, the four fixes in `adium.patch` are no longer needed: three are upstream already
(#24, #25 and the restored deletion prompt), and the scheduling is #31.

### Building that tree here

Two flags beyond the obvious, both learned the hard way:

    cmake -B build -S . \
      -DTd_DIR=<tdlib 1.8.65>/lib/cmake/Td \
      -DNoVoip=TRUE -DNoLottie=TRUE \
      -DCMAKE_DISABLE_FIND_PACKAGE_fmt=TRUE

`NoLottie` because rlottie's pixman NEON assembly is written for 32 bit ARM while the C beside it is
gated on `__ARM_NEON__`, which clang defines on arm64 as well; the link then fails on
`pixman_composite_over_n_8888_asm_neon`. Nothing is lost, the shipped 0.8.1 build has no lottie in
it either. `CMAKE_DISABLE_FIND_PACKAGE_fmt` because cmake otherwise picks up Homebrew's libfmt and
records it as an absolute path, which `relink_for_bundle.sh` has no mapping for and rightly refuses.

tdlib 1.8.65 has to be built from the commit the tree pins; Homebrew carries 1.8.0 and the
`Dependencies` tree builds 1.8.35, and the CMakeLists refuses anything below 1.8.65.

One thing to know before switching back: tdlib 1.8.65 upgrades the session database in place, and
1.8.35 may not read it afterwards. Take a copy of
`~/Library/Application Support/Adium 2.0/Users/Default/libpurple/tdlib` first.
