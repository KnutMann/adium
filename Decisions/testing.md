# Unit tests run in continuous integration, harnesses run by hand

**Decision.** Two kinds of test, kept apart on purpose. `UnitTests/` is an
XCTest bundle for logic that needs nothing but the three frameworks it links,
AIUtilities, Adium and AutoHyperlinks: the Cocoa categories, the HTML decoder,
the model objects, emoticon and sound packs, the URL scanner, and whatever else
can be exercised without the running application. It builds and runs in
continuous integration after the application, and a failure fails the job. A
test that pins a known defect carries `XCTExpectFailure` with the file and line,
so the suite stays green and the fix announces itself as an unexpected pass;
`grep -n XCTExpectFailure UnitTests/*.m` is the open defect list. `Testing/` is 45 harnesses, one directory per thing
under test, each run by a person, because each needs something the job does not
have: a server (the Prosody container behind `Testing/xmpp/server.sh`), a
device, a screen to photograph, or somebody at the other end to answer a call
or accept a file. Nothing under `Testing/` runs automatically, and its README
says so.

**Why.** The unit tests had been dead since Xcode stopped shipping
SenTestingKit, and were revived on 29 September 2026 (`e8b4c1048`): 356 tests,
44 failing for two known reasons, which was reason enough not to run them
anywhere. On 19 October both reasons were removed, and a suite that passes in
two seconds is cheap to run on every push and expensive not to. It is what found
the colour category converting through the wrong colour space, and under that,
an `rgb()` parser that had never divided by 255. The same evening seven agents
wrote 1,400 more tests against the frameworks' own contracts, and those found a
crash any contact could trigger with `<font size=0>`, numeric character
references showing as numbers since the ARC conversion, colour names that had
never worked, and a service default lost in September that made Jabber ask for
its password at every launch.

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

**Verified** 19 October 2026: `xcrun xctest` on the Release bundle reports 1,801
tests, 0 failures, 3 skipped, in 1.5 seconds, 94 of them expected failures that
each name a defect; `Testing/README.md` lists 45 harnesses;
`.github/workflows/build.yml` carries the two steps.
