# Adium, revival fork

Adium is a multi-protocol chat client for macOS, written in Objective-C on top
of libpurple. This fork brings it to macOS 13 and arm64 and adds the services
people use now. The README says what it does and how to build it. This file
says where things are and what a change has to satisfy. Four folders carry a
CLAUDE.md of their own that says how that part is put together; it loads when a
file there is opened, so read it before changing anything in that folder. And
Decisions/ says why the rules below are the rules: one page per choice somebody
could reasonably make differently, with what was rejected and what it costs.
Read the one that covers what you are about to change, and if you are about to
argue with a rule, read its page first.

## Where things are

Source/ is the application: the `adium` singleton with one controller per
domain, the contact list window, the preferences window, OTR, voice notes,
logging, and most of the older features, which are small classes called
*Plugin compiled into the application. See Source/CLAUDE.md.

Frameworks/Adium is Adium.framework: the model (AIAccount, AIListContact,
AIChat, AIContentMessage and their relatives), the protocol each controller
implements, the view the contact list is drawn with, and the loader for
.AdiumPlugin bundles. See Frameworks/Adium/CLAUDE.md. Frameworks/AIUtilities
is Cocoa categories and generic views that know nothing about chat; its
xcconfigs/ folder holds the build settings for every target.

Plugins/ is the rest of the features, one folder each, compiled into the
application and named in Source/AICoreComponentLoader.m: the message windows
and their tabs (Dual Window Interface), the conversation rendered in a
WKWebView (WebKit Message View), the padlock and encryption menu (Secure
Messaging), JavaScript xtras, Typst formulas, emoticons, the status menu
item and the contact alerts. Plugins/Purple Service is different: it builds
the AdiumLibpurple framework, the bridge to libpurple, and every protocol
lives in it or behind it. See Plugins/Purple Service/CLAUDE.md. PurplePlugins/
holds the prebuilt third-party protocol plug-ins that bridge loads.

Frameworks/ also carries the prebuilt arm64 libraries the application links,
and Dependencies/ is what fetches and builds them. See Dependencies/CLAUDE.md.

Resources/ is nibs, images, default plists, Adium.sdef, the .lproj folders
and the bundled xtras (Message Styles, Emoticons, Sounds, Dock Icons, Status
Icons, Service Icons, Menu Bar Icons, Contact List, Scripts). What the user
installs, with accounts and logs, is under ~/Library/Application Support/Adium
2.0. UnitTests/ is the XCTest target. Testing/ is harnesses run by hand and
Utilities/ is developer tools; both READMEs are generated from the scripts'
headers. Other/XtrasCreator is the companion application for making xtras,
and AdiumHelp/ is the help book.

## Building and checking

Build with ./install.sh --build-only, which is what continuous integration
runs: it fetches what the repository does not carry, builds, checks that every
protocol plug-in registers with the bundled libpurple, and verifies the
application's signature. Xcode alone skips the fetch and fails at a header it
cannot find. The Makefile and Release/ are leftovers of the upstream project.

No scheme runs the unit tests. They build and run by hand:

    xcodebuild -project Adium.xcodeproj -target "Unit tests" -configuration Release \
        -destination "platform=macOS,arch=arm64" SYMROOT="$PWD/build" \
        OBJROOT="$PWD/build/Intermediates" CODE_SIGN_IDENTITY=- \
        CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
    DYLD_FRAMEWORK_PATH="$PWD/build/Release" xcrun xctest "build/Release/Unit tests.xctest"

Continuous integration builds, verifies the plug-ins and the licences, and
runs nothing else. Files join the project by editing
Adium.xcodeproj/project.pbxproj; there is no workspace, package or Podfile.
/Applications/Adium.app is often a symbolic link into build/Debug, so a
script that builds for its own purposes builds somewhere else.

## What a change has to satisfy

The code is Objective-C under ARC. No Swift, CocoaPods or Swift Package
Manager; the deployment target and architecture are set once in
Base.xcconfig; nothing the application needs at runtime comes from Homebrew.

A new library follows the README's "Adding a library" and Dependencies/CLAUDE.md:
a script that produces it from a pinned source, a row in the README's table
and its licence in the bundle, all in the same change.

Every script opens with a header saying what it is for and how it is run;
Utilities/script-index.py rewrites the two generated READMEs from those
headers, so a new or renamed script means running it again.

User-visible strings go through the string tables. Utilities/git-hooks/
pre-commit checks them; enable it once per clone with
`git config core.hooksPath Utilities/git-hooks`.

docs/ is ignored by the owner's decision: it holds internal working notes,
and commit c034def91 says why. Do not un-ignore it or commit anything in it.

A commit's title is a full sentence saying what changed; its body says why,
and what was checked and how. Comments say why, not what. Commits written
with Claude end with a Co-Authored-By trailer naming the model.
