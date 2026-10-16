# Source/, the application

The Adium target. The `adium` singleton, its controllers, the contact list
and preferences windows, and some seventy small features compiled in.

## Launch

main.m starts AIAdium, the application delegate. applicationDidFinishLaunching
creates the AILoginController, which picks the user profile; completeLogin
then allocates the controllers in this order: preference, toolbar, debug,
contact alerts, sound, emoticon, account, contact, chat, content, dock, file
transfer, applescriptability, status (menu and interface come from the nib).
The preference and debug controllers finish loading first; then
AICoreComponentLoader instantiates every component in its list and calls
installPlugin on each; then AICorePluginLoader loads bundles; then the rest
of the controllers get controllerDidLoad, account before contact before
interface, because accounts must exist before contacts and contacts before
the list that shows them. A component may therefore use preferences and
debug logging in installPlugin and nothing else until controllerDidLoad.

## Controllers

Each owns one domain and implements the matching protocol in the framework.
AIAccountController: accounts, services and passwords (its categories are the
Adium*.m files: AdiumAccounts, AdiumServices, AdiumPasswords,
AdiumPreferredAccounts). AIContactController: every list object, grouping,
metacontacts and sorting (AIAlphabeticalSort, AIManualSort, ESStatusSort).
AIChatController: open chats. AIContentController: messages in and out, with
filtering, formatting, typing and events in AdiumContentFiltering,
AdiumFormatting, AdiumTyping, AdiumMessageEvents and AdiumChatEvents.
AIInterfaceController: windows, the message view and the contact list.
AIStatusController: presence, with AIAutomaticStatus for idle and away.
AIPreferenceController: defaults and panes, with AIPreferenceContainer for
per-object settings. AIMenuController, AIToolbarController, AISoundController
(AdiumSound, AdiumSoundSets, AdiumSpeech), AIDockController,
AIEmoticonController, ESContactAlertsController, ESFileTransferController,
ESDebugController and AILoginController are what their names say.

## Where the bigger things are

The contact list window: AIListController and AIListWindowController, with
AIStandardListWindowController and AIBorderlessListWindowController for the
two window styles; AISCLViewPlugin is the component that owns it.

The preferences window: AIModernPreferencesWindowController, the fork's,
with AIPreferenceWindowController kept as a thin front to it. Panes are
AIPreferencePane subclasses spread across Source/ and Plugins/. Installed
xtras are managed there too: AIXtrasPreferences, AIXtraDetailsPage,
AIXtrasManager, and XtrasInstaller for the files.

OTR: AdiumOTREncryption on libotr, with the ESOTR* windows and preferences
and OTRCommon.h. OMEMO is not here; it is in Plugins/Purple Service.

Voice notes: AIVoiceNotePlugin, AIVoiceNoteShelfView, AIVoiceRecorder and
AIOpusEncoder.

Logging: AILoggerPlugin writes the XML chat logs; AILogViewerWindowController,
AIChatLog, AILogFromGroup and AILogToGroup read them back; AIXMLAppender and
AIXMLChatlogConverter are the file format.

Inline pictures in a conversation: AIInlineMediaLinkPlugin. Now-playing
status: ESiTunesPlugin. Global hotkeys: the SG* classes. First run:
AdiumSetupWizard.

## The components

Most *Plugin classes here are one feature each, and the fastest way to find
a feature is the list in AICoreComponentLoader.m, then the class it names.
A new feature is a new AIPlugin subclass added to that list. The other
components live in the folders under Plugins/.
