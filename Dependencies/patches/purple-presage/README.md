# purple-presage patches

`Dependencies/source` is not under version control, so these files are the only record of what
`PurplePlugins/libsignal-presage.so` was built from.

Base revision: `c4c9b8d8e1a822f973520e8870aba1d2347b18c6` (2026-08-10, tagged
`nightly-20260810-f74b96e`) of <https://github.com/hoehermann/purple-presage>, the same author as
purple-gowhatsapp. It wraps the Rust `presage` library, which speaks Signal as a linked device, in a
C layer for libpurple, and it is under active development.

## adium.patch

**The runtime thread gets a stack it can live on**, in `src/c/connection.c` and `src/c/presage.h`.
This one crashes the whole application, so it comes first.

`presage_login` starts the Rust runtime on a thread of its own. The Windows branch asks for 32 MB,
with a comment saying tokio is picky about it, and `bridge.rs` sets the same size for its tokio
workers next to a note that 25 MB was found to be too little. The `pthread_create` branch passes no
attributes at all and takes the default. On Linux that is 8 MB and it grows. On macOS it is 512 KB,
measured, and it does not grow.

The result is not a Signal problem that stays inside the plugin: the runtime walks off the end of its
stack somewhere inside the first URL it parses, and macOS kills the process. What the user sees is
Adium vanishing a second after the account connects, with a crash report pointing at
`url::Parser::parse_path`, which looks like anything but a stack size. The tell is in the exception:
`KERN_PROTECTION_FAILURE` on an address inside the stack guard region.

The size is now one constant used by both branches. Linking a Signal account means scanning a QR code with
the phone, so the plugin draws one and hands it to the UI as an image. It drew it as a PBM, the
Netpbm ASCII bitmap format, with a comment in the original calling it a poor man's encoder. NSImage
does not read PBM, so on macOS the field where the QR code belongs came up blank and there was no way
to link at all. The patch fills a one pixel per module GdkPixbuf, scales it up with nearest neighbour
so the modules stay crisp squares rather than being smoothed into each other, and writes a PNG. Every
libpurple frontend can display that, so this is not a macOS special case, and gdk-pixbuf was already
a dependency of the plugin.

**The username no longer has to be the UUID**, in `src/c/presage.h`, `src/c/connection.c`,
`src/c/qrcode.c`, `src/c/receive_text.c` and `src/c/groups.c`. This is the larger of the two changes
and it removes the whole of the set-up procedure the upstream README describes.

An account has to be named before it can be linked, and nothing tells you your Signal UUID until you
have linked. `presage_handle_uuid` insisted the username already was the UUID and refused the
connection otherwise, reporting the right value in the error text. The documented way through was
therefore: type a placeholder, link, read the UUID out of the error, rename the account, link again.
Twice, because the store is named after the username, so the corrected name points at an empty store.
And the first linked device stays on the Signal account doing nothing until the user notices it.

The username never needed to be the UUID. It is two things: the file name of the store, and a label.
Signal identity is needed in exactly three places, where this account has to name itself among other
participants, and all three now ask `presage_own_uuid`, which answers with what the back-end
reported. That is asked for on every connection, not only the first, because `bridge.c` sends
`presage_rust_whoami` as soon as the channel to the runtime exists, so it is always current. It is
stored on the account as well, so it is right from the first moment rather than from the first reply.

What the user does now: name the account anything, link once, done.

Worth offering upstream. Nothing in it is specific to Adium; the procedure was the same everywhere.

**The conversation with yourself has a name**, in `src/c/blist.c`. One condition and one string.

Signal never sends you a contact record for yourself. You are not in your own contact list, and the
conversation with yourself is a place to put notes rather than a person. The entry standing for your
own account therefore arrives with an empty name and an empty profile key, which closes both roads
to a display name at once: there is nothing to alias the buddy with, and the profile that would hold
your name cannot be fetched without a key. `contacts.rs` says so in the debug log, once per attempt,
as `Missing profile key`. What is left on screen is a contact whose name is a bare UUID, with
nothing to say that it is you.

`presage_blist_update_buddy` now asks `presage_own_uuid`, which the change above already put there,
and calls that buddy `Note to Self`, which is the name Signal itself uses. Only the empty case is
filled in, so a real name would still win, and only the name is invented: no profile key is faked
and nothing is fetched.

Worth offering upstream, for the same reason as the last one. It is not an Adium problem.

## Building

    cd Dependencies/source/purple-presage/src/rust && cargo build --release   # long, only when needed
    ./Dependencies/patches/purple-presage/build.sh

The script compiles the C layer, links it, installs the result over
`PurplePlugins/libsignal-presage.so` and signs it.

There is no relink step here, unlike tdlib-purple and purple-gowhatsapp. The script links directly
against the libraries in `Frameworks/`, which already carry `@executable_path` install names, so the
names recorded are the ones that resolve inside the bundle and there is no window in which a second
copy of glib or libpurple could be pulled in. The script still refuses to finish if any absolute path
survives.

What an ordinary build of this plugin produces instead is `-undefined dynamic_lookup`: leave every
libpurple and glib symbol unresolved and let dyld find it in whatever is already loaded. For
libpurple that is safe, since it is by definition loaded before any protocol plugin. It is not safe
for gdk-pixbuf, which this plugin needs for the QR code and which is only in the process because
another plugin happens to link it. Linking it here is the difference between the QR code working and
it depending on which plugin loaded first.

qrencode is linked statically, from the archive Homebrew ships beside the dylib, so the bundle needs
no copy of it. The whole of it this plugin uses is one encode call.

## Testing it loads

Loading is worth checking separately from running, because a protocol plugin that fails to load says
nothing at all. Copy the built bundle somewhere, put a small program in `Contents/MacOS` so that
`@executable_path` resolves the way it will in the real thing, and `dlopen` the plugin. Do not do
this inside the bundle you use, since adding a file to it invalidates its signature and the keychain
will start asking for passwords again.
