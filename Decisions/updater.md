# The application updates itself through Sparkle 2, from a feed GitHub serves

**Decision.** The application carries Sparkle 2 (`Dependencies/sparkle`, fetched
by checksum like WebRTC) and a "Check for Updates…" item in its menu. The feed is
`appcast.xml`, published as an asset of every release and read through
`https://github.com/KnutMann/adium/releases/latest/download/appcast.xml`, GitHub's
redirect to the newest release, so the newest release is always the feed and
nothing has to be committed or hosted for it. Every entry is signed with an EdDSA
key whose public half is `SUPublicEDKey` in `Info.plist`; the private half lives
in the owner's keychain and, for the release workflow, in the `SPARKLE_PRIVATE_KEY`
secret. `CFBundleVersion`, the number the updater compares, is the count of
commits behind the build, written by `Utilities/stamp-build.sh`; the version
people read stays `CFBundleShortVersionString`.

**Why.** Adium 1.5 updated through Sparkle 1.17, x86_64 only and pointed at a
feed that had been dead for years; it went out on 7 August 2026 with the menu
item and 280 lines of delegate code, and this page said "no updater until there
is a release" until 29 October. On that day the developer membership came back,
and with it the three things an updater cannot do without: a Developer ID to
sign with, a notary ticket so that what it installs opens, and a place to put
the files. Sparkle 2 is the second generation of the same project, rewritten in
2021: arm64, its own XPC services, a feed it signs itself. There is no serious
alternative to it outside the App Store, only "no updater", and that one was
already tried.

Two smaller choices inside the big one. The feed lives in the release rather
than in a committed file or on GitHub Pages, because a release workflow that
commits to master on every tag is a loop waiting to happen and Pages is a second
thing to keep alive; the `latest` redirect costs nothing and cannot drift. And the
build number counts commits rather than being typed, because a number somebody
has to remember to raise is a number that will not be.

**What it costs.** The first release is the feed's first entry, so until it is
cut the menu item answers that it cannot reach the feed; that is the honest
state. A release that is not the newest cannot be pointed at: the redirect knows
only one. The EdDSA private key is a thing to keep: lose it and every installed
copy stops trusting the feed, and the only way out is a release signed with the
old key that carries the new public key. Sparkle adds sixteen megabytes of
somebody else's code to the bundle, re-signed on copy with the application's
identity; the notary service has to accept its nested helpers, which
`Utilities/notarize.sh` finds out.

**Verified** 29 October 2026: `install.sh --sign="Developer ID Application"
--build-only` builds with Sparkle 2.10.1 inside, every Mach-O in the bundle
including Sparkle's helpers carries the team and the hardened runtime, the
built `Info.plist` names the feed, the public key and a counted build number.
The same day, a rehearsal of the release workflow on GitHub's runner (run
40922920677) produced a zip whose `appcast.xml` entry carries build 1308, the
count of commits behind that commit, and an EdDSA signature; its first attempt
had said build 1, because a checkout fetches one commit unless told otherwise,
which is why the workflow fetches the whole history and refuses a shallow clone.
