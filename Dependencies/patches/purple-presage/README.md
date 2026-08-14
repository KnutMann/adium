# purple-presage patches

`Dependencies/source` is not under version control, so these files are the only record of what
`PurplePlugins/libsignal-presage.so` was built from.

Base revision: `c4c9b8d8e1a822f973520e8870aba1d2347b18c6` (2026-08-10, tagged
`nightly-20260810-f74b96e`) of <https://github.com/hoehermann/purple-presage>, the same author as
purple-gowhatsapp. It wraps the Rust `presage` library, which speaks Signal as a linked device, in a
C layer for libpurple, and it is under active development.

## adium.patch

**The QR code is a PNG**, in `src/c/qrcode.c`. Linking a Signal account means scanning a QR code with
the phone, so the plugin draws one and hands it to the UI as an image. It drew it as a PBM, the
Netpbm ASCII bitmap format, with a comment in the original calling it a poor man's encoder. NSImage
does not read PBM, so on macOS the field where the QR code belongs came up blank and there was no way
to link at all. The patch fills a one pixel per module GdkPixbuf, scales it up with nearest neighbour
so the modules stay crisp squares rather than being smoothed into each other, and writes a PNG. Every
libpurple frontend can display that, so this is not a macOS special case, and gdk-pixbuf was already
a dependency of the plugin.

**The store moves with the username**, in `src/c/connection.c` and `src/c/qrcode.c`. Setting an
account up asks for a username before anything knows the account's real UUID, so the documented
advice is to type anything and let the plugin report the right value. It reports it by refusing to
connect: "Username for this account must be ...". By then the device has been linked, and it has been
linked into a store named after the placeholder, because `rust_main` builds the path as
`<user dir>/presage/<username>.db3`. Correcting the username therefore points the plugin at a store
that does not exist, the QR code comes back, and the device linked a minute ago stays on the account
doing nothing until the user notices and removes it. Two scans and a stray device, for a first run.

The patch notes the real UUID down when it reports it, and moves the store, its write ahead log and
its shared memory file to match once the runtime has stopped. The second attempt then finds what the
first one did and connects without asking again. It refuses to move onto an existing store, since one
already under the real name means the account has been linked before and that is the one worth
keeping.

The timing is the whole of the care here. `rust_main_finished` is the only point at which the Rust
runtime has returned and the database is closed, which is why the move happens there rather than
where the UUID arrives. Renaming a SQLite database out from under an open connection loses data
quietly.

Worth offering upstream. Nothing in it is specific to Adium; the two scans happen on every frontend.

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
