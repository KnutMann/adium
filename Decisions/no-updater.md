# There is no updater until there is a release

**Decision.** The application has no update mechanism: no "Check for Updates"
menu item, no Sparkle, no feed. One comes back with the first release that
GitHub builds, signs and publishes, and not before.

**Why.** Adium 1.5 updated through Sparkle 1.17, which exists only for x86_64,
against a feed that has been dead for years. On 7 August 2026 (`37a8ac5d3`,
`5aa9583f6`) the framework went out with the menu item, the `SUUpdater` stub
and some 280 lines of feed and version-comparison delegate code; a half-removed
state in between had crashed at launch, because the main menu xib still
connected a delegate outlet to a stub without the property. An updater with
nothing to point at is a menu item that lies, which is worse than a missing one.

The order of events is fixed by what an updater needs: a signed and notarised
build, a place to put it, and a feed that says it is there. The release
workflow (`.github/workflows/release.yml`) packages a zip and a disk image on
every `v*` tag and has been rehearsed; publishing waits for an Apple developer
account that does not exist yet, because an unsigned application cannot be the
thing an updater installs. Once a release can be built there, the feed is one
more file the same workflow writes, and the obvious candidate on the
application side is Sparkle 2, which is arm64 and signs its appcast with EdDSA.
That part is not decided. What is decided is that it comes after the release,
not instead of it.

**What it costs.** Somebody running this application today built it, or took a
zip from somebody who did, and learns of a newer one by looking at the
repository. `Release/` and `Utilities/Build/` are the upstream project's release
chain and stay where they are until the new one has produced something.

**Verified** 19 October 2026: `grep -ri sparkle` over the sources, xibs, plists,
scripts and workflows finds nothing outside `docs/` and an emoticon fixture;
the repository has no release, and `release.yml` has only ever run as a
rehearsal.
