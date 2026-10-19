# Automatic reference counting, everywhere, as a setting

**Decision.** There is no Objective-C in this repository that is not compiled
under ARC. Every one of the thirteen targets that produces anything, across all
four project files, has `CLANG_ENABLE_OBJC_ARC` set; the only three targets
without it are script-only aggregates with no product and nothing to compile.
It is a target setting, carried by six xcconfigs, and there is not one per-file
`-fobjc-arc` flag and not one `-fno-objc-arc` exception left anywhere.

**Why.** Adium was written for manual retain and release, and the conversion ran
in seven rounds from August to September 2026, folder by folder, because a half
converted file owns nothing it thinks it owns. Mixing the two models per file
works and was how the migration proceeded, but leaving it mixed means every new
file begins with a question nobody should have to ask. Once the last round was
done, the flags came off the files and the setting went into the xcconfigs.

**What it costs.** Two traps, both found by being bitten:

A value set in the project file beats the xcconfig. Raising the deployment
target in the three xcconfigs on 13 October 2026 changed nothing until the same
key was raised in all eleven places the four project files set it themselves;
`xcodebuild -showBuildSettings` said 12.0 while the xcconfig said 13.0. Measure
the setting, do not read it.

The other direction also bites: `CLANG_ENABLE_OBJC_ARC` set at *project* level in
a pbxproj does not reach the targets, while `CLANG_ENABLE_OBJC_WEAK` in the same
block does. The build stays green and you get 136 warnings about a missing
`[super dealloc]` instead.

And the conversion keeps producing work long after it is finished. A file written
for manual counting and merged after ARC became the setting does not compile, and
`master` did not build for twelve days in October because of one cast of
`conv->ui_data` that needed `__bridge`. An outside contributor found it. That is
also why continuous integration exists.

**Verified** 19 October 2026, by asking the build rather than reading the
settings: `xcodebuild -showBuildSettings` for every target of every project
reports `CLANG_ENABLE_OBJC_ARC = YES`, except `Plist Macros`, `Setup Build
Directory` and `Touch Framework Bundles to Executable Date`, which report no
`PRODUCT_TYPE` either. No `.m` file exists outside those four projects, and
`grep -c fobjc-arc Adium.xcodeproj/project.pbxproj` is 0, the same for
`fno-objc-arc`.
