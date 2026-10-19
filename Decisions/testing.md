# Unit tests run in continuous integration, harnesses run by hand

**Decision.** Two kinds of test, kept apart on purpose. `UnitTests/` is an
XCTest bundle for logic that needs nothing but the frameworks: the AIUtilities
categories on strings, dates, colours, data and dictionaries, and the rich text
coercion. It builds and runs in continuous integration after the application,
and a failure fails the job. `Testing/` is 45 harnesses, one directory per thing
under test, each run by a person, because each needs something the job does not
have: a server (the Prosody container behind `Testing/xmpp/server.sh`), a
device, a screen to photograph, or somebody at the other end to answer a call
or accept a file. Nothing under `Testing/` runs automatically, and its README
says so.

**Why.** The unit tests had been dead since Xcode stopped shipping
SenTestingKit, and were revived on 29 September 2026 (`e8b4c1048`): 356 tests,
44 failing for two known reasons, which was reason enough not to run them
anywhere. On 19 October both reasons were removed, and a suite that passes in
a second is cheap to run on every push and expensive not to. It is what found
the colour category converting through the wrong colour space, and under that,
an `rgb()` parser that had never divided by 255.

The harnesses are a different animal. Most of what this fork adds is protocol
work, and protocol work is only proven against a real counterpart: a real MUC
service answering a self-ping, a real upload slot, a real neighbour on mDNS, a
real WebRTC peer connection. A unit test with a stub on the other side proves
that the code agrees with the stub. So the harnesses link the application's own
frameworks (from ad hoc signed copies, since arm64 will not load the unsigned
ones in the tree) and talk to the real thing, and several of them end with a
human deciding: declining the call, clicking the transfer. That cannot be a job.

What goes where, for new code: logic that is a function of its inputs gets a
unit test in `UnitTests/`; anything with a counterpart gets a harness beside
what it exercises, with a header saying what it needs, and
`Utilities/script-index.py` puts it in the README.

**What it costs.** The harnesses do not run themselves, so a regression in
protocol code is found by whoever next runs the harness, which may be weeks
later. That is the price of testing against the real thing rather than a stub.
`Testing/ui/` photographs views for comparison by eye, which is a check only for
the person who looks at the pictures.

One test is skipped rather than run: `testPlainTextToRichTextInAppleScript`
needs the AppleScript term "rich text" from `Adium.sdef`, which AppleScript
resolves against a running application, and `xcrun xctest` has none. It would
take a host application, and nothing in the job is one.

**Verified** 19 October 2026: `xcrun xctest` on the Release bundle reports 356
tests, 0 failures, 1 skipped, in 0.96 seconds; `Testing/README.md` lists 45
harnesses; `.github/workflows/build.yml` carries the two steps.
