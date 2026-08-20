/*
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 *
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import <Adium/AIAccountMenu.h>
#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AISettingsFormView.h>
#import "AISoundController.h"
#import "ESGeneralPreferences.h"
#import "ESGeneralPreferencesPlugin.h"
#import "AIMessageWindowController.h"
#import <Adium/AIServiceIcons.h>
#import <Adium/AIStatusIcons.h>
#import <AIUtilities/AIColorAdditions.h>
#import <AIUtilities/AIFontAdditions.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIPopUpButtonAdditions.h>
#import "AILogByAccountWindowController.h"

#define	PREF_GROUP_DUAL_WINDOW_INTERFACE	@"Dual Window Interface"
#define KEY_TABBAR_POSITION					@"Tab Bar Position"

/* Preference keys the pane binds to. PREF_GROUP_LOGGING, KEY_LOGGER_ENABLE,
 * PREF_GROUP_STATUS_MENU_ITEM and KEY_STATUS_MENU_ITEM_ENABLED come from
 * ESGeneralPreferencesPlugin.h; these mirror AILoggerPlugin.h and
 * DCMessageContextDisplayPlugin.h, which the pane does not otherwise need.
 */
#define KEY_LOGGER_SECURE_CHATS				@"LogSecureChats"
#define KEY_LOGGER_CERTAIN_ACCOUNTS			@"LogCertainAccounts"
#define PREF_GROUP_CONTEXT_DISPLAY			@"Message Context Display"
#define KEY_DISPLAY_CONTEXT					@"Display Message Context"
#define KEY_DISPLAY_LINES					@"Lines to Display"

//Width the form starts out at; the preferences window resizes it to its column.
#define GENERAL_PANE_INITIAL_WIDTH			540.0
#define RECENT_MESSAGES_FIELD_WIDTH			44.0

@interface ESGeneralPreferences () {
	/* The owner of the log-by-account sheet for as long as it is up. */
	AILogByAccountWindowController *logByAccountWindowController;
}
- (NSMenu *)tabChangeKeysMenu;
- (NSMenu *)sendKeysMenu;
- (NSMenu *)tabPositionMenu;
- (NSMenu *)accountMenuIconMenu;
- (IBAction)rebuildLogIndex:(id)sender;
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
- (AISettingsFormView *)buildSettingsForm;
- (void)bindObject:(id)object binding:(NSString *)binding keyPath:(NSString *)keyPath options:(NSDictionary *)options;
- (NSString *)keyPathForGroup:(NSString *)group key:(NSString *)key;
@end

/*!
 * @brief A nib label reused as a row label: without its trailing colon.
 *
 * Keeps every existing translation of the old labels usable while matching the
 * System Settings look, where row labels carry no colon.
 */
static NSString *AIRowLabel(NSString *label)
{
	NSCharacterSet	*whitespace = [NSCharacterSet whitespaceCharacterSet];
	NSString		*trimmed = [label stringByTrimmingCharactersInSet:whitespace];

	while ([trimmed hasSuffix:@":"]) {
		trimmed = [[trimmed substringToIndex:([trimmed length] - 1)] stringByTrimmingCharactersInSet:whitespace];
	}

	return trimmed;
}

@implementation ESGeneralPreferences

+ (NSSet *)keyPathsForValuesAffectingChatHistoryDisplayActive
{
	return [NSSet setWithObjects:@"adium.preferenceController.Logging.Enable Logging",
			@"adium.preferenceController.Message Context Display.Display Message Context",
			nil];
}

//Preference pane properties
- (NSString *)paneIdentifier
{
	return @"General";
}
- (NSString *)paneName{
    return AILocalizedString(@"General","General preferences label");
}
- (NSImage *)paneIcon
{
	return [NSImage imageNamed:@"pref-general" forClass:[self class]];
}

/*!
 * @brief Undo everything -view built.
 *
 * -bind:toObject:withKeyPath:options: retains us, so every live binding is a
 * retain cycle the pane only escapes through -viewWillClose. Deallocating with
 * bindings still in place would leave a dozen KVO observers registered on freed
 * memory; -closeView unbinds and releases the view, and is idempotent.
 */
- (void)dealloc
{
	[self closeView];
}

#pragma mark View

/*!
 * @brief Build our view instead of loading a nib.
 *
 * Mirrors -[AIModularPane view] so subclass hooks fire in the same order.
 */
- (NSView *)view
{
	if (!view) {
		AISettingsFormView	*form = [self buildSettingsForm];

		/* The view ivar is declared in AIModularPane and is strong under ARC; this store is
		 * the one reference, and -closeView's view = nil gives it up. No nib was loaded for
		 * this view, so unlike nib panes it carries no extra unowned reference. */
		view = form;

		[self viewDidLoad];
		[self localizePane];

		//-viewDidLoad fills the pop up menus; they need their final width before the last layout pass.
		[popUp_sendKeys sizeToFit];
		[popUp_tabKeys sizeToFit];
		[popUp_tabPositionMenu sizeToFit];
		[popUp_accountMenuIcon sizeToFit];
		[form layoutForWidth:NSWidth([form frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief Create the controls and stack them into cards.
 *
 * Each control keeps the bindings (key and group) its nib counterpart had.
 */
- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[AISettingsFormView alloc] initWithWidth:GENERAL_PANE_INITIAL_WIDTH];
	NSDictionary		*doesNotSetEnabled = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO]
																		 forKey:NSConditionallySetsEnabledBindingOption];
	/* The nib passed -1 for every placeholder of the secondary "enabled2" bindings,
	 * i.e. an absent value counts as enabled.
	 */
	NSDictionary		*enabledPlaceholders = [NSDictionary dictionaryWithObjectsAndKeys:
												[NSNumber numberWithInt:-1], NSMultipleValuesPlaceholderBindingOption,
												[NSNumber numberWithInt:-1], NSNoSelectionPlaceholderBindingOption,
												[NSNumber numberWithInt:-1], NSNotApplicablePlaceholderBindingOption,
												[NSNumber numberWithInt:-1], NSNullPlaceholderBindingOption,
												nil];
	NSString			*loggingEnabledPath = [self keyPathForGroup:PREF_GROUP_LOGGING key:KEY_LOGGER_ENABLE];

	//Messages
	[form addSectionHeader:AILocalizedString(@"Messages",nil)];

	//Create new chats in tabs
	checkBox_messagesInTabs = [AISettingsFormView switchWithTarget:nil action:NULL];
	[self bindObject:checkBox_messagesInTabs
			 binding:NSValueBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_INTERFACE key:KEY_TABBED_CHATTING]
			 options:nil];
	[form addRowWithLabel:AILocalizedString(@"Create new chats in tabs",nil)
				  control:checkBox_messagesInTabs];

	//Organize tabs into new windows by group
	checkBox_arrangeByGroup = [AISettingsFormView switchWithTarget:nil action:NULL];
	[self bindObject:checkBox_arrangeByGroup
			 binding:NSValueBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_INTERFACE key:KEY_GROUP_CHATS_BY_GROUP]
			 options:nil];
	[self bindObject:checkBox_arrangeByGroup
			 binding:NSEnabledBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_INTERFACE key:KEY_TABBED_CHATTING]
			 options:nil];
	[form addRowWithLabel:AILocalizedString(@"Organize tabs into new windows by group",nil)
				  control:checkBox_arrangeByGroup];

	//Reopen chats from last time on startup
	checkBox_reopenChats = [AISettingsFormView switchWithTarget:nil action:NULL];
	[self bindObject:checkBox_reopenChats
			 binding:NSValueBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_INTERFACE key:KEY_SAVE_CONTAINERS]
			 options:nil];
	[form addRowWithLabel:AILocalizedString(@"Reopen chats from last time on startup",nil)
				  control:checkBox_reopenChats];

	//Show recent messages in new chats: the nib's "Show [x] recent messages in new chats"
	checkBox_showChatHistory = [AISettingsFormView switchWithTarget:nil action:NULL];
	[self bindObject:checkBox_showChatHistory
			 binding:NSValueBinding
			 keyPath:@"chatHistoryDisplayActive"
			 options:nil];
	[self bindObject:checkBox_showChatHistory
			 binding:NSEnabledBinding
			 keyPath:loggingEnabledPath
			 options:nil];
	[form addRowWithLabel:AILocalizedString(@"Show recent messages in new chats","Switch for showing the last messages of a conversation at the top of a new chat")
				  control:checkBox_showChatHistory];

	//...and how many of them
	textField_recentMessages = [AISettingsFormView valueFieldWithWidth:RECENT_MESSAGES_FIELD_WIDTH
															   target:nil
															   action:@selector(takeIntValueFrom:)];
	NSNumberFormatter *recentMessagesFormatter = [[NSNumberFormatter alloc] init];
	[recentMessagesFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
	[recentMessagesFormatter setPositiveFormat:@"0"];
	[recentMessagesFormatter setNegativeFormat:@"-0"];
	[recentMessagesFormatter setMinimum:[NSNumber numberWithInt:1]];
	[recentMessagesFormatter setMaximum:[NSNumber numberWithInt:400]];
	[textField_recentMessages setFormatter:recentMessagesFormatter];
	[[textField_recentMessages cell] setSendsActionOnEndEditing:YES];

	stepper_recentMessages = [[NSStepper alloc] initWithFrame:NSZeroRect];
	[stepper_recentMessages setMinValue:0.0];
	[stepper_recentMessages setMaxValue:999.0];
	[stepper_recentMessages setIncrement:1.0];
	[stepper_recentMessages setValueWraps:YES];
	[stepper_recentMessages setAutorepeat:YES];
	[stepper_recentMessages setContinuous:YES];
	[stepper_recentMessages sizeToFit];

	/* The nib had the two take their value from each other. NSControl's target
	 * is a zeroing weak reference (verified on the 26 SDK: after the stepper is
	 * deallocated the field's -target reads nil and -sendAction:to: is a no-op),
	 * so the mutual pointers cannot outlive either control.
	 */
	[textField_recentMessages setTarget:stepper_recentMessages];
	[stepper_recentMessages setTarget:textField_recentMessages];
	[stepper_recentMessages setAction:@selector(takeIntValueFrom:)];
	[textField_recentMessages setNextKeyView:stepper_recentMessages];

	for (NSControl *control in [NSArray arrayWithObjects:textField_recentMessages, stepper_recentMessages, nil]) {
		[self bindObject:control
				 binding:NSEnabledBinding
				 keyPath:loggingEnabledPath
				 options:nil];
		[self bindObject:control
				 binding:@"enabled2"
				 keyPath:[self keyPathForGroup:PREF_GROUP_CONTEXT_DISPLAY key:KEY_DISPLAY_CONTEXT]
				 options:enabledPlaceholders];
	}
	[self bindObject:textField_recentMessages
			 binding:NSValueBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_CONTEXT_DISPLAY key:KEY_DISPLAY_LINES]
			 options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
												 forKey:NSContinuouslyUpdatesValueBindingOption]];
	[self bindObject:stepper_recentMessages
			 binding:NSValueBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_CONTEXT_DISPLAY key:KEY_DISPLAY_LINES]
			 options:nil];

	[form addRowWithLabel:AILocalizedString(@"Number of recent messages","Label of the field holding how many recent messages a new chat shows")
				  control:[AISettingsFormView rowOfViews:[NSArray arrayWithObjects:
														  textField_recentMessages, stepper_recentMessages, nil]
												 spacing:2.0]];

	//Send messages with
	popUp_sendKeys = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Send messages with:",nil))
				  control:popUp_sendKeys];

	//Switch tabs with
	popUp_tabKeys = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Switch tabs with:",nil))
				  control:popUp_tabKeys];

	//Show tabs on the
	popUp_tabPositionMenu = [AISettingsFormView popUpButtonWithTitles:nil target:nil action:NULL];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Show tabs on the:",nil))
				  control:popUp_tabPositionMenu];

	//Logging
	[form addSectionHeader:AILocalizedString(@"Logging","Section title of the message logging settings")];

	//Log messages
	checkBox_logMessages = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[self bindObject:checkBox_logMessages
			 binding:NSValueBinding
			 keyPath:loggingEnabledPath
			 options:doesNotSetEnabled];
	[form addRowWithLabel:AILocalizedString(@"Log messages",nil)
				  control:checkBox_logMessages];

	//Log only certain accounts, plus the button configuring them
	checkBox_logCertainAccounts = [AISettingsFormView switchWithTarget:nil action:NULL];
	[self bindObject:checkBox_logCertainAccounts
			 binding:NSValueBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_LOGGING key:KEY_LOGGER_CERTAIN_ACCOUNTS]
			 options:nil];
	[self bindObject:checkBox_logCertainAccounts
			 binding:NSEnabledBinding
			 keyPath:loggingEnabledPath
			 options:nil];

	button_customizeLogAccounts = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Customize",nil)
																   target:self
																   action:@selector(configureLogCertainAccounts:)];
	[self bindObject:button_customizeLogAccounts
			 binding:NSEnabledBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_LOGGING key:KEY_LOGGER_CERTAIN_ACCOUNTS]
			 options:nil];
	[self bindObject:button_customizeLogAccounts
			 binding:@"enabled2"
			 keyPath:loggingEnabledPath
			 options:enabledPlaceholders];

	[form addRowWithLabel:AILocalizedString(@"Log only certain accounts",nil)
				  control:[AISettingsFormView rowOfViews:[NSArray arrayWithObjects:
														  button_customizeLogAccounts, checkBox_logCertainAccounts, nil]
												 spacing:12.0]];

	//Log OTR-secured chats
	checkBox_logOTR = [AISettingsFormView switchWithTarget:nil action:NULL];
	[self bindObject:checkBox_logOTR
			 binding:NSValueBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_LOGGING key:KEY_LOGGER_SECURE_CHATS]
			 options:nil];
	[self bindObject:checkBox_logOTR
			 binding:NSEnabledBinding
			 keyPath:loggingEnabledPath
			 options:nil];
	[form addRowWithLabel:AILocalizedString(@"Log OTR-secured chats",nil)
				  control:checkBox_logOTR];

	/* Rebuilding the search index used to be a menu command, which put a repair next to the things
	 * people do every day. It keeps itself current on its own and is only ever wanted when a search
	 * comes up empty for a conversation that plainly exists, so it belongs beside the transcripts
	 * rather than in a menu. */
	button_rebuildIndex = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Rebuild",
																				   "Button which rebuilds the transcript search index")
														   target:self
														   action:@selector(rebuildLogIndex:)];
	[form addRowWithLabel:AILocalizedString(@"Search index",
										   "Label for the button which rebuilds the transcript search index")
				  control:button_rebuildIndex
				   detail:AILocalizedString(@"Only needed if searching does not find a conversation that exists.",
											"Explains when rebuilding the transcript search index is worth doing")];

	/* Confirmations, folded in from the former advanced pane the way the 1.6
	 * line folded them into its General pane. Same controls, same keys, same
	 * enabling rules; only the pane around them is gone. */
	[form addSectionHeader:AILocalizedString(@"Window Close Confirmation", "Preference")];

	checkBox_confirmBeforeClosing = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Confirm before closing multiple chat windows", "Message close confirmation preference")
				  control:checkBox_confirmBeforeClosing];

	radio_closeConfirmAlways = [AISettingsFormView radioButtonWithTitle:AILocalizedString(@"Always", "Confirmation preference")
																 target:self
																 action:@selector(changePreference:)];
	[radio_closeConfirmAlways setTag:AIMessageCloseAlways];

	radio_closeConfirmUnread = [AISettingsFormView radioButtonWithTitle:AILocalizedString(@"Only when there are unread messages", "Message close confirmation preference")
																 target:self
																 action:@selector(changePreference:)];
	[radio_closeConfirmUnread setTag:AIMessageCloseUnread];

	[form addRadioGroupWithLabel:nil buttons:[self closeConfirmTypeButtons]];

	[form addSectionHeader:AILocalizedString(@"Quit Confirmation", "Preference")];

	checkBox_quitConfirmAlways = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Always ask before quitting Adium", "Quit Confirmation preference")
				  control:checkBox_quitConfirmAlways];

	checkBox_quitConfirmFT = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Ask when file transfers are in progress", "Quit Confirmation preference")
				  control:checkBox_quitConfirmFT];

	checkBox_quitConfirmUnread = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Ask when there are unread messages", "Quit Confirmation preference")
				  control:checkBox_quitConfirmUnread];

	checkBox_quitConfirmOpenChats = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Ask when chat windows are open", "Quit Confirmation preference")
				  control:checkBox_quitConfirmOpenChats];

	//Status
	[form addSectionHeader:AILocalizedString(@"Status",nil)];

	checkBox_showMenuBarStatus = [AISettingsFormView switchWithTarget:nil action:NULL];
	[self bindObject:checkBox_showMenuBarStatus
			 binding:NSValueBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_STATUS_MENU_ITEM key:KEY_STATUS_MENU_ITEM_ENABLED]
			 options:doesNotSetEnabled];
	[form addRowWithLabel:AILocalizedString(@"Show Adium status in menu bar",nil)
				  control:checkBox_showMenuBarStatus];

	/* Filled and bound in -configureView, once the menu is in place: binding a selected tag to an
	 * empty button would write the setting away before it has anything to select. */
	popUp_accountMenuIcon = [AISettingsFormView popUpButtonWithTitles:nil target:nil action:NULL];
	[form addRowWithLabel:AILocalizedString(@"Show account status in menus",
										   "Chooses what an account carries in front of its name in the menus listing accounts")
				  control:popUp_accountMenuIcon];

	return form;
}

/*!
 * @brief Rebuild the search index over every transcript
 *
 * The transcript window opens with it, because that is where the work becomes visible and where the
 * search that went wrong is repeated afterwards.
 */
- (IBAction)rebuildLogIndex:(id)sender
{
	[[NSNotificationCenter defaultCenter] postNotificationName:AIShowLogViewerAndReindexNotification object:nil];
}

#pragma mark Bindings

/*!
 * @brief The key path a preference has when bound through the shared controller.
 */
- (NSString *)keyPathForGroup:(NSString *)group key:(NSString *)key
{
	return [NSString stringWithFormat:@"adium.preferenceController.%@.%@", group, key];
}

/*!
 * @brief Bind @a object to ourselves, remembering the binding so we can undo it.
 */
- (void)bindObject:(id)object binding:(NSString *)binding keyPath:(NSString *)keyPath options:(NSDictionary *)options
{
	if (!object) return;

	[object bind:binding toObject:self withKeyPath:keyPath options:options];

	if (!establishedBindings) establishedBindings = [[NSMutableArray alloc] init];
	[establishedBindings addObject:[NSArray arrayWithObjects:object, binding, nil]];
}

/*!
 * @brief Tear the bindings down before the controls go away.
 */
- (void)viewWillClose
{
	for (NSArray *boundPair in establishedBindings) {
		[[boundPair objectAtIndex:0] unbind:[boundPair objectAtIndex:1]];
	}
	/* Stays an assignment: -bindObject: builds the array again only when it finds none here. */
	establishedBindings = nil;

	checkBox_messagesInTabs = nil;
	checkBox_arrangeByGroup = nil;
	checkBox_logMessages = nil;
	checkBox_showChatHistory = nil;
	checkBox_logOTR = nil;
	checkBox_logCertainAccounts = nil;
	checkBox_reopenChats = nil;
	checkBox_showMenuBarStatus = nil;
	button_customizeLogAccounts = nil;
	textField_recentMessages = nil;
	stepper_recentMessages = nil;
	popUp_tabKeys = nil;
	popUp_sendKeys = nil;
	popUp_tabPositionMenu = nil;
	popUp_accountMenuIcon = nil;
	button_rebuildIndex = nil;
}

#pragma mark Configuration

//Configure the preference view
- (void)viewDidLoad
{
	BOOL			sendOnEnter, sendOnReturn;

	//Chat Cycling
	[popUp_tabKeys setMenu:[self tabChangeKeysMenu]];
	[popUp_tabKeys selectItemWithTag:[[adium.preferenceController preferenceForKey:KEY_TAB_SWITCH_KEYS
																			 group:PREF_GROUP_CHAT_CYCLING] intValue]];

	//General
	sendOnEnter = [[adium.preferenceController preferenceForKey:SEND_ON_ENTER
															group:PREF_GROUP_GENERAL] boolValue];
	sendOnReturn = [[adium.preferenceController preferenceForKey:SEND_ON_RETURN
															group:PREF_GROUP_GENERAL] boolValue];
	[popUp_sendKeys setMenu:[self sendKeysMenu]];

	if (sendOnEnter && sendOnReturn) {
		[popUp_sendKeys selectItemWithTag:AISendOnBoth];
	} else if (sendOnEnter) {
		[popUp_sendKeys selectItemWithTag:AISendOnEnter];
	} else if (sendOnReturn) {
		[popUp_sendKeys selectItemWithTag:AISendOnReturn];
	}

	[popUp_tabPositionMenu setMenu:[self tabPositionMenu]];
	[popUp_tabPositionMenu selectItemWithTag:[[adium.preferenceController preferenceForKey:KEY_TABBAR_POSITION
																								 group:PREF_GROUP_DUAL_WINDOW_INTERFACE] intValue]];
	/* Bound only now: the nib's selectedTag binding needs the menu in place, and
	 * -setMenu: would otherwise be seen as a selection change.
	 */
	[self bindObject:popUp_tabPositionMenu
			 binding:NSSelectedTagBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_DUAL_WINDOW_INTERFACE key:KEY_TABBAR_POSITION]
			 options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
												 forKey:NSValidatesImmediatelyBindingOption]];

	//Same order for the same reason: the menu first, the selection second, the binding last
	[popUp_accountMenuIcon setMenu:[self accountMenuIconMenu]];
	[popUp_accountMenuIcon selectItemWithTag:[[adium.preferenceController preferenceForKey:KEY_ACCOUNT_MENU_ICON
																					 group:PREF_GROUP_GENERAL] intValue]];
	[self bindObject:popUp_accountMenuIcon
			 binding:NSSelectedTagBinding
			 keyPath:[self keyPathForGroup:PREF_GROUP_GENERAL key:KEY_ACCOUNT_MENU_ICON]
			 options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
												 forKey:NSValidatesImmediatelyBindingOption]];

	[self refreshConfirmationControls];

    [self configureControlDimming];
}

#pragma mark Confirmations

/*!
 * @brief The buttons of the "when to confirm closing" choice, in display order
 */
- (NSArray *)closeConfirmTypeButtons
{
	return [NSArray arrayWithObjects:radio_closeConfirmAlways, radio_closeConfirmUnread, nil];
}

/*!
 * @brief Select the button carrying @a tag; an unknown tag falls back to the first button
 */
- (void)selectTag:(NSInteger)tag inRadioGroup:(NSArray *)buttons
{
	NSButton *match = nil;

	for (NSButton *button in buttons) {
		if ([button tag] == tag) match = button;
	}
	if (!match) match = [buttons firstObject];
	if (!match) return;

	for (NSButton *button in buttons) {
		[button setState:(button == match ? NSControlStateValueOn : NSControlStateValueOff)];
	}
}

- (void)setEnabled:(BOOL)enabled forRadioGroup:(NSArray *)buttons
{
	for (NSButton *button in buttons) {
		[button setEnabled:enabled];
	}
}

/*!
 * @brief Fill the confirmation controls from the stored preferences
 */
- (void)refreshConfirmationControls
{
	NSDictionary *confirmationDict = [adium.preferenceController preferencesForGroup:PREF_GROUP_CONFIRMATIONS];

	/* Asking always is the two stored answers together: confirm at all, and confirm regardless of
	 * what is going on. */
	BOOL always = ([[confirmationDict objectForKey:KEY_CONFIRM_QUIT] boolValue] &&
				   [[confirmationDict objectForKey:KEY_CONFIRM_QUIT_TYPE] integerValue] == AIQuitConfirmAlways);

	[checkBox_quitConfirmAlways setState:(always ? NSControlStateValueOn : NSControlStateValueOff)];

	//The three keys suppress a confirmation, so the switch is the inverse of the stored value
	[checkBox_quitConfirmFT setState:(![[confirmationDict objectForKey:KEY_CONFIRM_QUIT_FT] boolValue] ?
									  NSControlStateValueOn : NSControlStateValueOff)];
	[checkBox_quitConfirmOpenChats setState:(![[confirmationDict objectForKey:KEY_CONFIRM_QUIT_OPEN] boolValue] ?
											 NSControlStateValueOn : NSControlStateValueOff)];
	[checkBox_quitConfirmUnread setState:(![[confirmationDict objectForKey:KEY_CONFIRM_QUIT_UNREAD] boolValue] ?
										  NSControlStateValueOn : NSControlStateValueOff)];

	[checkBox_confirmBeforeClosing setState:([[confirmationDict objectForKey:KEY_CONFIRM_MSG_CLOSE] boolValue] ?
											 NSControlStateValueOn : NSControlStateValueOff)];
	[self selectTag:[[confirmationDict objectForKey:KEY_CONFIRM_MSG_CLOSE_TYPE] integerValue]
	   inRadioGroup:[self closeConfirmTypeButtons]];
}

/*!
 * @brief Write the two stored answers the four quit switches together stand for
 *
 * Whether to ask at all follows from whether any switch wants a question; whether to ask
 * regardless follows from the first one alone.
 */
- (void)writeQuitConfirmation
{
	BOOL always = (checkBox_quitConfirmAlways.state == NSControlStateValueOn);
	BOOL anyCondition = ((checkBox_quitConfirmFT.state == NSControlStateValueOn) ||
						 (checkBox_quitConfirmUnread.state == NSControlStateValueOn) ||
						 (checkBox_quitConfirmOpenChats.state == NSControlStateValueOn));

	[adium.preferenceController setPreference:[NSNumber numberWithInteger:(always ? AIQuitConfirmAlways : AIQuitConfirmSelective)]
									   forKey:KEY_CONFIRM_QUIT_TYPE
										group:PREF_GROUP_CONFIRMATIONS];

	[adium.preferenceController setPreference:[NSNumber numberWithBool:(always || anyCondition)]
									   forKey:KEY_CONFIRM_QUIT
										group:PREF_GROUP_CONFIRMATIONS];
}

//Called in response to all preference controls, applies new settings
- (IBAction)changePreference:(id)sender
{
    if (sender == popUp_tabKeys) {
		AITabKeys keySelect = (AITabKeys)[[sender selectedItem] tag];

		[adium.preferenceController setPreference:[NSNumber numberWithInt:keySelect]
											 forKey:KEY_TAB_SWITCH_KEYS
											  group:PREF_GROUP_CHAT_CYCLING];

	} else if (sender == popUp_sendKeys) {
		AISendKeys 	keySelect = (AISendKeys)[[sender selectedItem] tag];
		BOOL		sendOnEnter = (keySelect == AISendOnEnter || keySelect == AISendOnBoth);
		BOOL		sendOnReturn = (keySelect == AISendOnReturn || keySelect == AISendOnBoth);

		[adium.preferenceController setPreference:[NSNumber numberWithInt:sendOnEnter]
											 forKey:SEND_ON_ENTER
											  group:PREF_GROUP_GENERAL];
		[adium.preferenceController setPreference:[NSNumber numberWithInt:sendOnReturn]
											 forKey:SEND_ON_RETURN
                                              group:PREF_GROUP_GENERAL];

	} else if (sender == checkBox_quitConfirmAlways) {
		[self writeQuitConfirmation];
		[self configureControlDimming];

	} else if (sender == checkBox_quitConfirmFT) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:![sender state]]
										   forKey:KEY_CONFIRM_QUIT_FT
											group:PREF_GROUP_CONFIRMATIONS];
		[self writeQuitConfirmation];

	} else if (sender == checkBox_quitConfirmUnread) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:![sender state]]
										   forKey:KEY_CONFIRM_QUIT_UNREAD
											group:PREF_GROUP_CONFIRMATIONS];
		[self writeQuitConfirmation];

	} else if (sender == checkBox_quitConfirmOpenChats) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:![sender state]]
										   forKey:KEY_CONFIRM_QUIT_OPEN
											group:PREF_GROUP_CONFIRMATIONS];
		[self writeQuitConfirmation];

	} else if (sender == checkBox_confirmBeforeClosing) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:[sender state]]
										   forKey:KEY_CONFIRM_MSG_CLOSE
											group:PREF_GROUP_CONFIRMATIONS];
		[self configureControlDimming];

	} else if (sender == radio_closeConfirmAlways || sender == radio_closeConfirmUnread) {
		[adium.preferenceController setPreference:[NSNumber numberWithInteger:[(NSButton *)sender tag]]
										   forKey:KEY_CONFIRM_MSG_CLOSE_TYPE
											group:PREF_GROUP_CONFIRMATIONS];
	}
}

//Dim controls as needed
- (void)configureControlDimming
{
	[checkBox_arrangeByGroup setEnabled:[checkBox_messagesInTabs state]];

	/* Asking in every case answers the other three as well, so they have nothing left to
	 * decide and say so by dimming. They keep their state while dimmed. */
	BOOL enableSpecificConfirmations = (checkBox_quitConfirmAlways.state != NSControlStateValueOn);
	[checkBox_quitConfirmFT setEnabled:enableSpecificConfirmations];
	[checkBox_quitConfirmUnread setEnabled:enableSpecificConfirmations];
	[checkBox_quitConfirmOpenChats setEnabled:enableSpecificConfirmations];

	[self setEnabled:(checkBox_confirmBeforeClosing.state == NSControlStateValueOn)
	   forRadioGroup:[self closeConfirmTypeButtons]];
}

/*!
 * @brief Construct our menu by hand for easy localization
 */
- (NSMenu *)tabChangeKeysMenu
{
	NSMenu		*menu = [[NSMenu alloc] init];
#define PLACE_OF_INTEREST_SIGN	"\u2318"
#define LEFTWARDS_ARROW			"\u2190"
#define RIGHTWARDS_ARROW		"\u2192"
#define SHIFT_ARROW				"\u21E7"
#define OPTION_KEY				"\u2325"
#define TAB_KEY					"\u21E5"

	[menu addItemWithTitle:[NSString stringWithFormat:AILocalizedString(@"Ctrl + Tab (%@ and %@)","Ctrl/Ctrl+Shift + Tab key word"),
							[NSString stringWithUTF8String:"^" TAB_KEY],
							[NSString stringWithUTF8String:"^" SHIFT_ARROW TAB_KEY]]
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AICtrlTab];

	[menu addItemWithTitle:[NSString stringWithFormat:AILocalizedString(@"Arrows (%@ and %@)","Directional arrow keys word"),
							[NSString stringWithUTF8String:PLACE_OF_INTEREST_SIGN LEFTWARDS_ARROW],
							[NSString stringWithUTF8String:PLACE_OF_INTEREST_SIGN RIGHTWARDS_ARROW]]
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AISwitchArrows];

	[menu addItemWithTitle:[NSString stringWithFormat:AILocalizedString(@"Shift + Arrows (%@ and %@)","Shift key word + Directional arrow keys word"),
							[NSString stringWithUTF8String:SHIFT_ARROW PLACE_OF_INTEREST_SIGN LEFTWARDS_ARROW],
							[NSString stringWithUTF8String:SHIFT_ARROW PLACE_OF_INTEREST_SIGN RIGHTWARDS_ARROW]]
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AISwitchShiftArrows];

	[menu addItemWithTitle:[NSString stringWithFormat:AILocalizedString(@"Option + Arrows (%@ and %@)","Option key word + Directional arrow keys word"),
							[NSString stringWithUTF8String:OPTION_KEY PLACE_OF_INTEREST_SIGN LEFTWARDS_ARROW],
							[NSString stringWithUTF8String:OPTION_KEY PLACE_OF_INTEREST_SIGN RIGHTWARDS_ARROW]]
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AIOptArrows];

	[menu addItemWithTitle:[NSString stringWithFormat:AILocalizedString(@"Brackets (%@ and %@)","Word for [ and ] keys"),
							[NSString stringWithUTF8String:PLACE_OF_INTEREST_SIGN "["],
							[NSString stringWithUTF8String:PLACE_OF_INTEREST_SIGN "]"]]
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AIBrackets];

	[menu addItemWithTitle:[NSString stringWithFormat:AILocalizedString(@"Curly braces (%@ and %@)","Word for { and } keys"),
							[NSString stringWithUTF8String:PLACE_OF_INTEREST_SIGN "{"],
							[NSString stringWithUTF8String:PLACE_OF_INTEREST_SIGN "}"]]
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AIBraces];

	return menu;
}

/*!
 * @brief Construct our menu by hand for easy localization
 */
- (NSMenu *)sendKeysMenu
{
	NSMenu		*menu = [[NSMenu alloc] init];

	[menu addItemWithTitle:AILocalizedString(@"Enter","Enter key for sending messages")
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AISendOnEnter];

	[menu addItemWithTitle:AILocalizedString(@"Return","Return key for sending messages")
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AISendOnReturn];

	[menu addItemWithTitle:AILocalizedString(@"Enter and Return","Enter and return key for sending messages")
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AISendOnBoth];

	return menu;
}

- (IBAction)configureLogCertainAccounts:(id)sender
{
	/* Held in an instance variable rather than a local for the length of the sheet. The one
	 * reference used to be carried by nobody: allocated into a local here, never given up, and
	 * cashed in from -sheetDidEnd: through the sheet's own back pointer. A local goes out of
	 * scope at the end of this method, which is where the sheet begins.
	 */
	logByAccountWindowController = [[AILogByAccountWindowController alloc] initWithWindowNibName:@"AILogByAccountWindow"];

	[self.view.window beginSheet:logByAccountWindowController.window
		   completionHandler:^(NSModalResponse returnCode) {
			[self sheetDidEnd:self->logByAccountWindowController.window returnCode:returnCode contextInfo:NULL];
		}];
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	[sheet orderOut:nil];
	logByAccountWindowController = nil;
}

/*!
 * @brief What an account carries in front of its name in the menus that list accounts
 */
- (NSMenu *)accountMenuIconMenu
{
	NSMenu *menu = [[NSMenu alloc] init];

	[menu addItemWithTitle:AILocalizedString(@"Status and service icon",
											 "Both icons in front of an account's name in a menu")
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AIAccountMenuIconStatusAndService];

	[menu addItemWithTitle:AILocalizedString(@"Service icon only",
											 "Only the service's icon in front of an account's name in a menu")
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AIAccountMenuIconServiceOnly];

	[menu addItemWithTitle:AILocalizedString(@"Status only",
											 "Only the status icon in front of an account's name in a menu")
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AIAccountMenuIconStatusOnly];

	return menu;
}

- (NSMenu *)tabPositionMenu
{
	NSMenu		*menu = [[NSMenu alloc] init];

	[menu addItemWithTitle:AILocalizedString(@"Top","Position menu item for tabs at the top of the message window")
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AdiumTabPositionTop];

	[menu addItemWithTitle:AILocalizedString(@"Bottom","Position menu item for tabs at the bottom of the message window")
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AdiumTabPositionBottom];

	[menu addItemWithTitle:AILocalizedString(@"Left","Position menu item for tabs at the left of the message window")
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AdiumTabPositionLeft];

	/* No right. It is the mirror image of left and nobody reads a window from that side, so it was
	 * one more arrangement to keep working for no one's benefit. A stored right is moved to bottom
	 * when the interface opens, so nothing is left pointing at a choice that is no longer offered. */

	return menu;
}

- (BOOL)chatHistoryDisplayActive
{
	return ([[adium.preferenceController preferenceForKey:@"Display Message Context" group:@"Message Context Display"] boolValue] &&
			[[adium.preferenceController preferenceForKey:@"Enable Logging" group:@"Logging"] boolValue]);
}
- (void)setChatHistoryDisplayActive:(BOOL)flag
{
	[adium.preferenceController setPreference:[NSNumber	numberWithBool:flag]
	 forKey:@"Display Message Context"
	 group:@"Message Context Display"];
}

@end
