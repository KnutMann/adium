# Bonjour runs on libpurple's prpl-bonjour, not on libezv

**Decision.** Local network chat is a descriptor row for `prpl-bonjour`, the
protocol libpurple ships. The service came back on 21 September 2026.

**Why.** Adium's own Bonjour implementation was libezv, an Intel-only framework
from 2004 with its own Rendezvous stack. It left with the other Intel-only
frameworks in August 2026, and bringing it to arm64 would have meant porting a
twenty-year-old networking library for a protocol libpurple already speaks.

The replacement cost one row in `AIPurpleServiceDescriptors.plist` and a
migration for accounts stored under the old service identifier. That ratio is the
whole argument.

**What it costs.** libpurple's Bonjour is not Adium's, and the differences are
real: no file transfer that has been exercised, and the presence model is
libpurple's rather than the one Adium's own implementation had. The UI test is
still outstanding.

It also left one piece of debris worth knowing about, because it misled a licence
audit: `License.txt` went on naming libezv as the only third-party library in the
application for years after the code was gone. That is why the licence list is
now generated rather than maintained.

**Verified** 19 October 2026: no file in the tree mentions libezv, and
`prpl-bonjour` is in the descriptor; the service returned in `efc24cd2b`.
