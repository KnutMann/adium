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

## adium.patch

Three changes, all in the login path:

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
