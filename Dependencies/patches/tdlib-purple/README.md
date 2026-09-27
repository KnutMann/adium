# tdlib-purple patches

`Dependencies/source` is not under version control, so these files are the only record of what
`PurplePlugins/libtelegram-tdlib.so` was built from.

Base revision: `b277ac1941dbed946444454f67b89265541237b7`, release 2.1.0, of
<https://github.com/adrighem/tdlib-purple>, built against TDLib 1.8.65
(`a8f21f5230172634becc1739050ef23ecd6ea291`), which its CMakeLists requires as a minimum.

The tree this replaced was `43e6cc2` of the 0.8.1 line, and it carried five local changes. Four of
them are upstream now, in this release, having been merged as pull requests #29, #30 and #31: the
scheduling on purple2, which became `purple2-scheduler.cpp` and removed every `g_idle_add` and
`g_timeout_add` in the plugin; `tgprpl_add_buddy` no longer resolving a username for a contact
already known; `tgprpl_request_delete_contact` no longer deleting a contact that is merely being
unfiled from a group; and the deletion confirmation that had been commented out since 2020. What
remains local is one change, below.

## adium.patch

**A contact's phone number is written where an interface can find it**, in `client-utils.cpp` and
`purple-info.h`. Two lines and a constant.

A buddy is named after the Telegram user id, because a name has to be stable and unique and a phone
number is neither. The number is known all the same, and it went only into the info dialog, as a
line of text assembled when somebody opens it. That is a fine place to read it and no place at all
to look it up, so an interface wanting to match this person against an address book had nothing to
match on. It is left on the buddy as `phone-number`, deliberately without the `tdlib-` prefix the
neighbouring setting carries: that one is this plugin talking to itself about a photo it downloaded,
this one is a fact about the person that any user interface might want, and a name only this plugin
understands is a fact nobody can use.

Telegram hands out a contact's number only when they share it, so the setting is often absent, and
absent is written as no setting rather than an empty string.

Worth offering upstream, like the four before it.

## Rebuilding

TDLib first, once, into its own prefix so the 1.8.35 package beside it stays where it is:

    git -C Dependencies/source/td-1.8.65 checkout a8f21f5230172634becc1739050ef23ecd6ea291
    cmake -B build -S . -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=Dependencies/build/tdlib-1.8.65 \
      -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
    cmake --build build --target install -j

Then the plugin. Two flags beyond the obvious, both learned the hard way:

    cmake -B build -S . \
      -DTd_DIR=<repo>/Dependencies/build/tdlib-1.8.65/lib/cmake/Td \
      -DNoVoip=TRUE -DNoLottie=TRUE \
      -DCMAKE_DISABLE_FIND_PACKAGE_fmt=TRUE -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j

`NoLottie` because rlottie's pixman NEON assembly is written for 32 bit ARM while the C beside it is
gated on `__ARM_NEON__`, which clang defines on arm64 as well; the link then fails on
`pixman_composite_over_n_8888_asm_neon`. `CMAKE_DISABLE_FIND_PACKAGE_fmt` because cmake otherwise
picks up Homebrew's libfmt and records it as an absolute path, which `relink_for_bundle.sh` has no
mapping for and rightly refuses.

## Installing, and the thing that goes wrong

Do not copy the built plugin into place by hand. Use

    Dependencies/patches/tdlib-purple/install.sh <built .dylib> <its build directory>

tdlib keeps its session in a binlog, and every event in it carries the writing tdlib's internal
format number: 1.8.65 writes 60, 1.8.35 writes 53 and refuses to read anything from 54 upwards. A
plugin built against the older one therefore cannot open a session the newer one wrote, and it does
not fail cleanly either: it has already touched the log by the time it gives up, and the newer tdlib
will not read it afterwards. The account is then gone and has to be linked again.

Nothing warns about this on its own. The plugin's CMakeLists checks the tdlib it is built against,
not the tdlib that wrote the session on this machine; the libraries live in `Dependencies/build` and
the session lives in Application Support, and a stale build directory is enough to pair them
wrongly. That is exactly what happened on 2026-08-16, and it cost the account.

So the version that wrote the session is recorded beside it, in
`~/Library/Application Support/Adium 2.0/Users/Default/libpurple/tdlib/.tdlib-version`, and the
script compares before installing, copies the session aside every time, and refuses rather than
guesses when there is no record. For a session that predates the record, read the version out of the
debug log, where the plugin announces itself as

    (Libpurple: telegram-tdlib) version 2.1.0, tdlib 1.8.65

and write it down once with `install.sh --record 1.8.65`.

## Testing it loads

Start Adium with the debug log on and look for the line above. If the version is not the one you
just built, the bundle still has the old copy: the Xcode build copies `PurplePlugins/` into
`Adium.app`, so the app has to be rebuilt after installing.

## 2026-09-27: built against TDLib 1.8.67

The shipped plugin is now built against TDLib 1.8.67 (`bc9c263`, the commit that sets that
version, pinned the same way `a8f21f5` pinned 1.8.65). The source tree needed five adaptations,
because the TDLib interface moved underneath it:

* `getProxies` answers with `addedProxies` rather than `proxies`, and each entry is an
  `addedProxy` which carries the old `proxy` inside it. The entry still has `id_` of its own, so
  only the types changed.
* `addProxy` takes a `proxy` object where it used to take server, port and type as three fields
  of the request, and it answers with `addedProxy`.
* `inputMessageDocument::document_` is an `inputDocument` now, which wraps the file along with a
  thumbnail and a flag.
* `inputMessagePhoto::photo_` is an `inputPhoto`, which wraps the file along with a thumbnail, a
  video, sticker ids and a size.
* `addContact` takes the user id beside the contact rather than inside it, and what it takes is
  an `importedContact`, which has no id of its own. `importContacts` takes the same type.

**These five are not ours to keep.** adrighem's master already carries all of them, and carries
them identically: the two awkward ones, the photo and the document, are character for character
the same down to `nullptr, nullptr, std::vector<int32_t>(), 0, 0`. They are in no release yet,
2.1.1 does not have them, which is why they had to be made here at all. They should disappear on
the next move to a release that contains them, and nothing should be offered upstream, because
upstream has already done it.

**What is not established**, and is written down rather than guessed: this source tree no longer
matches the base revision named at the top of this file, nor the 2.1.0 tag, by thousands of lines
in the larger files, while `purple-info.h` differs by the eight lines of our own patch. adrighem
reconciled two histories on 2026-09-12 with a merge made 'ours', so the tags very probably do not
point at the trees they pointed at in August. Whoever next touches this should establish the base
afresh rather than trust the line above.

**Deployment target.** TDLib was configured with `-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0`, matching
`Base.xcconfig`. Without it CMake takes the current SDK and the result demands macOS 26, which
loads nowhere else and says nothing about why. Worth checking after any rebuild:

    otool -l PurplePlugins/libtelegram-tdlib.so | grep -m1 minos

**Not yet run.** The plugin compiles, links, resolves everything through the bundle and is
installed through install.sh, which recorded the session as 1.8.67. Whether it talks to Telegram
is untested. The session as it was is beside it, in a folder named for the day.

## A contact joining Telegram is not an unsupported message

Reported the first evening this ran: a chat line reading

    Max Schön: Unsupported message type messageContactRegistered

Telegram sends that when somebody already in the address book starts using it. It is an ordinary
thing to be told, not a gap in what this plug-in supports, and naming a wire type at a reader is
no way to say it. It says "joined Telegram" now, after the sender's name, the way every other
service message in this file is built, and only if the account asks for it.

The asking is the point. Showing such a message opens a chat window by itself, which is a great
deal of window for a piece of news nobody was waiting for, so the account setting **"Say when a
contact joins Telegram" is off unless somebody turns it on**. Knowing is worth something; being
interrupted for it is not, and a reader who wants it can say so once.

**This one is worth offering upstream**, unlike the five API adaptations above: adrighem's master
does not have it either, its table still lists messageContactRegistered among the types that fall
through to the unsupported branch. Worth offering along with the phone number change, which has
been waiting since August.
