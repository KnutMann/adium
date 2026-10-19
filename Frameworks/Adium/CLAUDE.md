# Adium.framework

The model, the protocols the application's controllers implement, and the
views the contact list is drawn with. Everything else links it: Source/,
every folder under Plugins/, and the AdiumLibpurple framework. Nothing here
talks to a network, and nothing here is a controller; a protocol lives in
Plugins/Purple Service and a controller in Source/.

## The model

AIService is a protocol and AIAccount an account on it. AIAbstractAccount
holds the mechanics of connecting, reconnecting and storing settings;
AIAccount is the part a protocol's subclass overrides. AIAccountPlan describes
an account's settings form as a list of fields, each saying once where its
value lives, and AIAccountPlanFormBuilder lays that out on an AISettingsFormView.

AIListObject is anything that can appear in the contact list. AIListContact
is one person on one account; AIMetaContact is several of those seen as one
person; AIListGroup is a group; AIListBookmark is a saved group chat;
AIContactList is the root. AIProxyListObject stands for one object in one
place in the outline view, which is how a contact appears in two groups.
AIContactObserverManager is how a change to a list object reaches everything
that displays it.

AIChat is a conversation, with one contact or a room. What passes through it
is an AIContentObject: AIContentMessage for a message, AIContentContext for
one restored from history, and AIContentEvent, AIContentNotification,
AIContentStatus, AIContentTopic and AIContentTyping for the rest.

AIStatus is a presence state, AIStatusGroup a folder of them, AIStatusItem
their common parent; AIStatusDefines has the keys.

AIXtraInfo is an installed xtra of any kind; AIEmoticonPack and AISoundSet are
two kinds read into objects. AIServiceIcons, AIStatusIcons and AIUserIcons
hand out images, the last from the *UserIconSource classes.

## What a feature implements

AIPlugin is the base class of every component; installPlugin and
uninstallPlugin are the whole contract. A preference pane is an
AIPreferencePane, laid out on an AISettingsFormView, the fork's System
Settings-style form, with AISettingsNavigationController behind the sidebar.
An action a contact alert can take is an AIActionDetailsPane.

Each controller in Source/ implements one of the AI*ControllerProtocol.h
files here, and AIAdiumProtocol declares `adium`, the object that owns them
all (AISharedAdium.h makes it a global). A component reaches a controller only
through those protocols.

AICorePluginLoader loads .AdiumPlugin bundles from the application's
Contents/PlugIns and the user's PlugIns folder; the fork's JavaScript xtras
are that kind. The loader for compiled-in components is in Source/.

## Views and helpers

The contact list view is AIAbstractListController with AIListOutlineView
(drawing in AIListOutlineView+Drawing) and the AIListCell, AIListContactCell,
AIListGroupCell and AIListRowView classes; the window controllers that hold
one are in Source/. AIAccountMenu, AIContactMenu and AIStatusMenu build the
menus the application shows in several places. AIHTMLDecoder converts between
HTML and attributed strings and is on the path of every message in and out.
AIAddressBookController and AIAddressBookPerson are the Contacts framework
integration. The AILocalizedString macros live one framework over, in
AIUtilities/Source/AIStringUtilities.h; AILocalizationAssistance.h is the
category the AILocalization* controls use to size themselves to a translated
title.
