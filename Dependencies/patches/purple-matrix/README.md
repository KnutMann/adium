# purple-matrix

<https://github.com/matrix-org/purple-matrix>, the Matrix protocol for libpurple, written at
matrix.org. Built here at `2792d4d`, which is its last commit (April 2023); upstream has called
itself unmaintained since 2022.

Bound as `prpl-matrix` through the descriptor and the account plan, like Telegram, IRCv3 and Teams:
no Objective-C of its own.

## What it does

Text messages in rooms you are already in or get invited to. Tried against `gitter.ems.host` with
a token (2026-10-13): the account connected and the rooms from Gitter came up straight away. The
code also reads `m.room.topic` and fetches thumbnails for `m.image`; neither has been looked at
closely yet.

What it does not do, by upstream's own list: create rooms or one-to-one chats, presence, typing,
rich text, calls. End-to-end encryption is compiled out here (`MATRIX_NO_E2E`):
upstream only ever got as far as decrypting, it needs libolm, which has itself been retired, and
public rooms are not encrypted anyway.

## Encrypted rooms

Element creates new private rooms end-to-end encrypted, and the first test room was one. Upstream
dropped every `m.room.encrypted` event it could not decrypt with nothing but a debug line, and sent
into such a room in the clear, which Element then flagged on every message. Both are said out loud
now: an encrypted room announces itself with a system line when it opens, an encrypted message
leaves a "cannot be read here" line with its sender, and a message typed into an encrypted room is
refused with an error instead of going out unencrypted. Gitter's public rooms are not encrypted,
so none of this shows up there.

Adium shows the refusal as a grey status line, the way it shows every line a libpurple protocol
writes without a sender. What it no longer does is show the refused message as sent: the plugin
writes its own outgoing messages into the room itself, so the descriptor says
`EchoesOutgoingMessages` and Adium keeps no local copy. A message that was not sent is simply not
there. Adium's lock icon in the chat toolbar is OTR, which has nothing to do with Matrix
encryption and cannot switch it on.

## Why it is here

Gitter moved to Matrix. Its rooms live on the homeserver `gitter.ems.host` (which is what
`gitter.im/.well-known/matrix/client` points at), and they are federated, so any Matrix account can
join them.

## Signing in

The Gitter homeserver offers no password login, only SSO (GitHub, GitLab) and token. Ask it:

    curl https://gitter.ems.host/_matrix/client/v3/login

purple-matrix only speaks password login itself, but it keeps and prefers an access token once it
has one. `adium.patch` lets the token be typed in as the password, so the way in is:

1. Sign in to the homeserver in a browser (Element Web at `app.gitter.im`, or any Element).
2. Copy the access token: Settings → Help & About → Advanced → Access Token.
3. In Adium, add a Matrix account with the full Matrix id (`@name:gitter.im`), paste the token as
   the password, set the home server URL to `https://gitter.ems.host` and tick "The password is an
   access token" under Options.

The token stays valid until that browser session logs out. An ordinary Matrix account with a
password, on `matrix.org` for instance, signs in without any of this and can join the same rooms.

## Where the token lives

In the keychain, like every other Adium password, and nowhere else. The first version of this patch
made the token an account option, and account options are plain text: libpurple writes them to
`libpurple/accounts.xml` and Adium mirrors them in `AccountPrefs.plist`, both in the user's
profile. Only the mode switch is an option now; it is a bool, and nothing of it is secret.

Upstream still stores the token it obtains from a password login in `accounts.xml`, to reuse the
device on the next connection. That is unchanged for password accounts. In token mode the plugin
removes that setting, so a profile that had the first version of this patch is cleaned up at the
next connection.

## Closing a window is not leaving a room

Upstream implemented libpurple's `chat_leave` as leaving the room on the server. libpurple calls
`chat_leave` whenever a chat conversation is destroyed, and Adium destroys the conversation when
its window closes (as Pidgin does). So closing the window of a room meant leaving it, for good,
and closing a window with six Gitter rooms in it meant leaving six rooms. That is how it was
noticed, on 2026-10-13.

`adium.patch` makes `chat_leave` free the conversation's local state and nothing more. A closed
room comes back with the next sync that mentions it, or with the next connection. Leaving for good
is the `/leave` command, typed into the room; it tells the server and marks the conversation as
left.

## Bookmarks

A room can be bookmarked from its window (Add Group Chat Bookmark), and the bookmark is a row in
the contact list, which also makes the borderless list visible again when nothing else is in it.
Opening the bookmark joins the room, which for a room the account is still in simply brings the
window back. Tried on 2026-10-13: close the window, open the bookmark, the room is back with its
members.

That needed one more line in the plugin: `chat_info_defaults` returned an empty table and ignored
the room it was asked about, and that table is what Adium turns into a bookmark's join data. Now
it answers with the room id, which is all the protocol asks for when joining.

Two more things stood between the bookmark and a live room:

* Joining a room the account is already in is a no-op on the server, so the sync had nothing to
  say about it and `_join_completed`, which only logged, never produced a conversation. The room
  stayed an empty window until somebody wrote in it. Now a completed join whose room has no
  conversation fetches `/rooms/<id>/state` and opens the room from that; messages arrive with the
  sync as before, history before the join is not fetched.
* Adium lowercased every chat name, and a Matrix room id is case sensitive (room version 12 ids
  carry no server part at all, `!2cKIUR…` is the whole id). The generic service now keeps chat
  names as they are when its descriptor says `CaseSensitive`. That is Adium's side, in
  `AIPurpleGenericService.m`, not the patch. A bookmark made before that fix carries the lowercased
  name and has to be made again.

## adium.patch

Seven changes:

* `libmatrix.c`, `matrix-room.c`, `matrix-room.h`: `chat_leave` no longer leaves the room on the
  server, see above; `/leave` does.
* `libmatrix.c`: `chat_info_defaults` answers with the room id, so bookmarks work.
* `matrix-connection.c`, `matrix-sync.c`, `matrix-api.c` and their headers: a completed join opens
  the room from `/rooms/<id>/state` when the sync will not.
* `matrix-room.c`: encrypted rooms and messages are announced, and nothing is sent into an
  encrypted room, see above.

* `libmatrix.c`, `libmatrix.h`: a bool option, "The password is an access token". When it is set
  the password is used as the token and goes straight to `whoami`; a failure there is reported
  rather than falling back to a password login that cannot exist.
* `matrix-connection.c`: an `access_token` setting left empty comes back as `""`, not `NULL`, and
  the plugin took that as a token and asked `whoami` with nothing. Empty now means absent.
* `matrix-connection.c`: `_whoami_error` read its `user_data` as the account, but every caller
  passes the connection, so the password fallback after a stale token ran on the wrong struct.
  It takes the account from the connection now.

## build.sh

Fetches both sources at their pins, applies the patch, compiles against the frameworks in
`Frameworks/` and installs the result as `PurplePlugins/libmatrix.so`:

    ./Dependencies/patches/purple-matrix/build.sh

No relink afterwards: linking against the bundled frameworks records their `@executable_path` names
directly, as purple-presage does. The upstream `Makefile` does not build here: it wants `gcc`,
pkg-config for everything, and `-shared` where a loadable module is needed.

`http_parser.c`, from nodejs/http-parser 2.9.4, is compiled straight into the plugin. The project
is archived and macOS ships no copy, and one source file does not justify a bundled library.
