# The source is GPLv2 or later; the application is GPLv3

**Decision.** Adium's own source code stays under the GNU GPL version 2 or, at
your option, any later version. The application built from it is conveyed under
GPL version 3, and `License.txt` says so.

**Why.** The bundle carries code that cannot be combined with GPLv2. Five of the
seven shipped protocol plug-ins are GPL-3.0, and OpenSSL has been under the
Apache licence since version 3.0, which GPLv2 forbids because of its patent
termination and indemnification clauses; GPLv3 section 7 was written to permit
exactly those. So the only licence under which all of it can go out together is
GPLv3, and the "or any later version" in Adium's own grant is what allows that.
Permitting it is what the clause is for.

**What it costs.** Less than it sounds, and the misunderstanding is worth
spelling out because it came up twice.

It is not a one way door. The source keeps its GPLv2-or-later grant; nobody can
take that away, and a file from this tree can still go into a GPLv2 project. Only
the distributed combination is GPLv3, and a build without the GPLv3 components
would be GPLv2-conveyable again. The price of that build would be no WhatsApp, no
Signal, no Teams and no Telegram, which is why nobody is going to make it.

What it does cost is paperwork, and that is now mechanical: every shipped binary
carries its licence in `Resources/Licenses/`, gathered by
`Utilities/collect-licenses.sh` from the tree each component was built from, and
`Utilities/verify-licenses.sh` fails the build if a binary arrives without one.
Before that existed, `License.txt` named exactly one third-party library, libezv,
which had been removed from the tree years earlier.

**Verified** 13 October 2026, and the measurement is in the commit: the licence
of every shipped plug-in read from the tree it was built from, not from a GitHub
badge, and OpenSSL traced to the two binaries that link it.
