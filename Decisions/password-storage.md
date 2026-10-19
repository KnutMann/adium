# Passwords are in the keychain, through SecItem

**Decision.** Account passwords are stored in the user's login keychain as
internet passwords, written and read through `SecItemAdd`,
`SecItemCopyMatching`, `SecItemUpdate` and `SecItemDelete` in `AIKeychain`
(Frameworks/AIUtilities). They are never in `Accounts.plist`, never in
libpurple's `accounts.xml`, and never logged. libpurple is not asked to keep
them: Adium creates its `PurpleAccount`s itself and calls neither
`purple_accounts_load` nor `purple_accounts_sync`, so the file libpurple would
write does not exist.

**Why.** The keychain was always the place; what changed on 9 August 2026
(`e8e7734ac`) was the API. The `SecKeychain*` family had been deprecated since
macOS 10.10, and the replacement keeps every existing entry readable: SecItem
works on the same login keychain, the custom four-character protocol code
`AdIM` maps to its string form, and a lookup that finds nothing under the
protocol asks once more without it, for entries written before one was
recorded. It was checked against a live account, which connected without a
prompt.

The alternative is libpurple's own path, where `remember_password` puts
`<password>` into `accounts.xml` in clear text. That is why adium-swift's backup
filters that element out, and why this fork does not go there.

**What it costs.** Two traps, both found on 15 August 2026, both looking like the
same bug, a password that would not stay remembered:

A keychain item carries the identity of the application that wrote it, and for
an application signed with anything but an Apple-issued certificate that
identity is the cdhash of the binary, not its designated requirement. Measured
on 19 October 2026 with `security dump-keychain -a`: the Jabber item that Adium
1.5 wrote in 2021 lists eighteen entries for `build/Debug/Adium.app`, one cdhash
per rebuild that was allowed with "Always allow", and its partition list grows
the same way. So a developer is asked once after every rebuild and never on an
unchanged start. The local signing certificate, trusted for code signing as it
is, does not change that, because it carries no team identifier; a Developer ID
would. Issue #8, a password asked for at every launch, is a different thing: the
`supportsPassword` default lost on 22 September and restored on 19 October,
which had made Jabber connect without fetching its password at all.

Some protocol plug-ins use the password slot for themselves: purple-teams stores
its refresh token as the libpurple account password and reads it back from
there on connect. An empty slot can then mean "the session expired" or "this
protocol never uses the slot", and treating the second as the first once deleted
a real user password. `KEY_PASSWORD_IS_PROTOCOL_SESSION` in the account status
group now records who owns what is stored, and only what that path stored itself
is ever forgotten.

Measuring without touching the running application: `security dump-keychain`
filtered for `ptcl == AdIM` lists the entries and `mdat` says whether one was
written today; never with `-d`, which prompts for every item. `/usr/bin/log show
--predicate 'process == "Adium"'` shows each keychain access to the millisecond.

**Verified** 19 October 2026: `AIKeychain.m` contains no call to the
`SecKeychainFind*`, `SecKeychainAdd*` or `SecKeychainSearch*` functions; the one
mention left is a comment saying they were replaced. Nothing under Plugins or
Source calls `purple_accounts_load` or `purple_accounts_sync`.
