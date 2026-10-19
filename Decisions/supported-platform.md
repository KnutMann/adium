# Apple Silicon, macOS 13

**Decision.** The application is built for arm64 only and for macOS 13 or later.
The floor is set in `Base.xcconfig` and in every place the four project files set
it themselves.

**Why.** Each of the three numbers it has had was forced by something specific.

It was 11, because that is what the Macs this fork exists for can run. It became
12 when Xcode 27 stopped building for anything older; that was not a choice but a
toolchain fact. It became 13 on 13 October 2026 because the prebuilt
`WebRTC.framework` the call support links is built for 13, and that produced the
only link warning left in the whole project.

That last one was a choice, and the alternatives were worse. WebRTC's packager
passes a deployment target for iOS and none for macOS, so the macOS slice
inherits Chromium's, which has risen to 13. Building WebRTC ourselves means a
Chromium checkout and hours of compile at every bump, for a fork whose recent
achievement is that strangers can build it at all. Restamping the binary with
`vtool` is cheaper and worse: if the code really uses something that arrived in
13, the result is a crash on 12 rather than an honest refusal to load.

arm64 only is the point of the fork rather than a decision inside it. Intel users
have 1.5.10.4, and Rosetta 2 is supported through macOS 27.

**What it costs.** Nothing measurable. Every Apple Silicon Mac ever sold runs
Ventura, so raising the floor to 13 excluded nobody who could run an arm64 build
in the first place. The bundled libraries keep whatever older stamp they were
built with, and that is correct: a library built for an older system is valid on a
newer one, and only the reverse warns.

**Verified** 19 October 2026: `Base.xcconfig` reads 13.0, the only `10.12` left in
the tree is inside TDLib's own Swift example project under `Dependencies/source/`,
which is third-party source and never built.
