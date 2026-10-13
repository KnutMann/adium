# purple-matrix

<https://github.com/matrix-org/purple-matrix>, the Matrix protocol for libpurple, written at
matrix.org. Built here at `2792d4d`, which is its last commit (April 2023); upstream has called
itself unmaintained since 2022.

Bound as `prpl-matrix` through the descriptor and the account plan, like Telegram, IRCv3 and Teams:
no Objective-C of its own.

## What it does

Text messages in rooms you are already in or get invited to. The code also reads `m.room.topic`
and fetches thumbnails for `m.image`, though neither has been tried from Adium yet.

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
has one. `adium.patch` makes that token an account option, so the way in is:

1. Sign in to the homeserver in a browser (Element Web at `app.gitter.im`, or any Element).
2. Copy the access token: Settings → Help & About → Advanced → Access Token.
3. In Adium, add a Matrix account with the full Matrix id (`@name:gitter.im`), leave the password
   empty, set the home server URL to `https://gitter.ems.host` and paste the token.

The token stays valid until that browser session logs out. An ordinary Matrix account with a
password, on `matrix.org` for instance, signs in without any of this and can join the same rooms.

## adium.patch

Two changes, both in the login path:

* `libmatrix.c`: the `access_token` setting, which the plugin already reads before trying a
  password, becomes a (masked) account option, so it can be supplied rather than only remembered.
* `matrix-connection.c`: an option left empty comes back as `""`, not `NULL`, and the plugin took
  that as a token and asked `whoami` with nothing. Empty now means absent.

## build.sh

Fetches both sources at their pins, applies the patch, compiles against the frameworks in
`Frameworks/` and installs the result as `PurplePlugins/libmatrix.so`:

    ./Dependencies/patches/purple-matrix/build.sh

No relink afterwards: linking against the bundled frameworks records their `@executable_path` names
directly, as purple-presage does. The upstream `Makefile` does not build here: it wants `gcc`,
pkg-config for everything, and `-shared` where a loadable module is needed.

`http_parser.c`, from nodejs/http-parser 2.9.4, is compiled straight into the plugin. The project
is archived and macOS ships no copy, and one source file does not justify a bundled library.
