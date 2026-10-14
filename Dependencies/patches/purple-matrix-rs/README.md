# purple-matrix-rs

`Dependencies/source` is not under version control, so this file and `build.sh` are the only record
of what `PurplePlugins/libmatrix.so` was built from.

Base revision: `b2fb0ce276e0d84c8495a9a7a1a955251203c052` (tag `v0.2.1`, 2026-10-14) of
<https://github.com/iilonmasc/purple-matrix-rs>, the Matrix protocol plug-in written for this
bundle: a Rust library on the [matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk)
behind a small C file for libpurple. The SDK does sync, rooms and end-to-end encryption; the plug-in
registers as `prpl-matrix`, so the service entry in `AIPurpleServiceDescriptors.plist` and any
account made for the earlier purple-matrix plug-in carry on unchanged.

There is no `adium.patch`. The plug-in is developed against this bundle, and what Adium needs goes
into the plug-in's repository rather than into a patch here; its `spec/` directory records the
decisions, among them the four rules that came out of the purple-matrix branch: closing a window is
not leaving a room, `/leave` is; nothing is echoed locally, the plug-in writes what the server
confirmed; a room reopens from its state when the account is still in it; a bookmark can be made
from an open room.

## What it does, as of 0.2.1

Signing in with an access token (the password field, with "The password is an access token" set in
the account's options, which keeps the token in the keychain); joined rooms as chats with members,
names, topics and the last lines of history; text in both directions, encrypted by the SDK in
encrypted rooms; invitations; `/leave`; bookmarks and reopening. Not yet: password or SSO sign-in,
typing and read receipts, media, creating rooms, presence, device verification and key backup, so
other clients show the device as unverified.

The SDK's stores live under `<purple user dir>/matrix/<account>/` and are the device's encryption
identity, bound to the token's device id. They are not to be deleted while the token stays: other
clients then keep sharing room keys with the old identity. A fresh start is a new token.

## Building

`build.sh` clones the repository at the pin into `Dependencies/source/purple-matrix-rs`, runs its
`ADIUM=<checkout> just plugin`, and copies the result to `PurplePlugins/libmatrix.so`. It needs a
stable Rust toolchain and `just` on the machine; the first Rust build takes a few minutes.

## Licence

The plug-in is GPL-2.0-or-later. The SDK it links in statically is Apache-2.0, which combines with
GPLv3 and not with GPLv2, so the shipped `libmatrix.so` is distributed under GPLv3, like several
other plug-ins in this bundle (see the fork's README, "License").
