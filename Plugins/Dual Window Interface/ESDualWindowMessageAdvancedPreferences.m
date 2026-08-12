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

#import "AIDualWindowInterfacePlugin.h"
#import "ESDualWindowMessageAdvancedPreferences.h"
#import "AIWebkitMessageViewStyle.h"
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIDictionaryAdditions.h>
#import <AIUtilities/AIPopUpButtonAdditions.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIDateFormatterAdditions.h>
#import <AIUtilities/AIImageAdditions.h>

#import <Adium/AIInterfaceControllerProtocol.h>
#import "AIPreferenceWindowController.h"

//Width the form starts out at; the preferences window resizes it to its column.
#define MESSAGE_ADVANCED_PANE_INITIAL_WIDTH	540.0

@interface ESDualWindowMessageAdvancedPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (NSSegmentedControl *)chatTypeSegmentedControl;
- (NSMenu *)_nameFormatMenu;
- (NSMenu *)_fontSizeMenu;
- (NSMenu *)_timeStampMenu;
- (void)_addTimeStampChoice:(NSDateFormatter *)formatter toMenu:(NSMenu *)menu;
- (void)configurePreferencesForTab;
- (IBAction)changeChatType:(id)sender;
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
	/* U+003A and the full width U+FF1A the CJK translations use ("時刻の書式：") */
	NSCharacterSet	*colons = [NSCharacterSet characterSetWithCharactersInString:@":："];
	NSString		*trimmed = [label stringByTrimmingCharactersInSet:whitespace];

	while ([trimmed length] > 0 &&
		   [colons characterIsMember:[trimmed characterAtIndex:([trimmed length] - 1)]]) {
		trimmed = [[trimmed substringToIndex:([trimmed length] - 1)] stringByTrimmingCharactersInSet:whitespace];
	}

	return trimmed;
}

/*!
 * @brief A continuation title reused as a row label: standing on its own.
 *
 * "…only count number of unread mentions" read as the continuation of the
 * checkbox it was indented under. As a row of its own it is a title, so the
 * marks of that continuation go: the leading ellipsis every translation points
 * back at the checkbox with, a trailing full stop, and lower case at the front.
 *
 * All three are applied to the translation, which keeps every existing
 * localization of the string usable instead of forcing a new one. Case is
 * folded in the locale of the localization actually on screen, not in the
 * user's region — Turkish dotted/dotless i is decided by the language of the
 * text, not by the region format. A no-op in scripts without letter case.
 */
static NSString *AISentenceCaseLabel(NSString *label)
{
	NSMutableCharacterSet	*strip = [[[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopy] autorelease];
	[strip addCharactersInString:@".…。"];

	NSString	*trimmed = [label stringByTrimmingCharactersInSet:strip];
	if ([trimmed length] < 1) return label;

	NSString	*localization = [[[NSBundle bundleForClass:[ESDualWindowMessageAdvancedPreferences class]] preferredLocalizations] firstObject];
	NSLocale	*locale = (localization ? [NSLocale localeWithLocaleIdentifier:localization] : [NSLocale currentLocale]);
	NSRange		 first = [trimmed rangeOfComposedCharacterSequenceAtIndex:0];
	NSString	*head = [[trimmed substringWithRange:first] uppercaseStringWithLocale:locale];

	return [trimmed stringByReplacingCharactersInRange:first withString:head];
}

@implementation ESDualWindowMessageAdvancedPreferences

- (NSString *)label{
    return AILocalizedString(@"Messages",nil);
}
- (NSImage *)image{
	return [NSImage imageNamed:@"pref-messages" forClass:[AIPreferenceWindowController class]];
}

/* No -nibName: the pane builds its own view below, so AIModularPane never loads
 * a nib for us. DualWindowMessageAdvanced.xib is dead — and it must stay
 * unloaded: it still wires nineteen outlets this class no longer has
 * (tabView_messageType, tabViewItem_regular, label_tabs, …), so loading it
 * would raise NSUnknownKeyException rather than fall back to the old interface.
 * Removing it from the target needs project file access we do not have here.
 */

#pragma mark View

/*!
 * @brief Build our view instead of loading a nib.
 *
 * Mirrors -[AIModularPane view] so the subclass hooks fire in the same order.
 */
- (NSView *)view
{
	if (!view) {
		AISettingsFormView	*form = [self buildSettingsForm];

		settingsForm = form;
		view = [form retain];

		[self viewDidLoad];
		[self localizePane];

		/* Every menu here sits in a pop up row, and those measure their button at
		 * each layout, so all that is left after -viewDidLoad filled the four menus
		 * is one more layout pass.
		 */
		[form layoutForWidth:NSWidth([form frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief Undo everything -view built.
 *
 * -closeView releases the view and is idempotent; without it the form would
 * outlive us with the KVO observation every row keeps on its control.
 */
- (void)dealloc
{
	[self closeView];
	[super dealloc];
}

/*!
 * @brief Create the controls and stack them into cards.
 *
 * Three cards. The first holds everything regular chats and group chats keep
 * apart — the nib gave it a two-item tab view, which becomes the segmented
 * control in its first row: the rows below never change, only the values in
 * them, so the card does not jump when the user switches. The other two cards
 * are the nib's "Tabs" and "Window Handling" blocks, whose settings are global
 * and therefore stay out of the switched card.
 *
 * Each control keeps the key, the group and the action its nib counterpart had.
 */
- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[[AISettingsFormView alloc] initWithWidth:MESSAGE_ADVANCED_PANE_INITIAL_WIDTH] autorelease];

	[form addSectionHeader:AILocalizedString(@"Messages",nil)];

	segment_chatType = [self chatTypeSegmentedControl];
	[form addRowWithLabel:AILocalizedString(@"Settings for", "Label of the control choosing which kind of chat the message settings below apply to")
				  control:segment_chatType];
	[form addDetailRow:AILocalizedString(@"Regular chats and group chats each keep their own settings.",
										 "Explanation of the regular chat/group chat switch in the advanced message preferences")];

	//Use custom name format, and the format itself in the row below it
	checkBox_customNameFormatting = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Use custom name format:",nil))
				  control:checkBox_customNameFormatting];

	popUp_nameFormat = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Name format", "Label of the menu choosing how a contact's name is written in the message view")
			  popUpButton:popUp_nameFormat
		  accessoryButton:nil];

	/* Time stamp and minimum font size. Both menus are built at run time — the
	 * time stamps from the user's locale, the sizes from a fixed list — so both
	 * take a pop up row, which re-measures its button at every layout.
	 */
	popUp_timeStampFormat = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Time stamp format:",nil))
			  popUpButton:popUp_timeStampFormat
		  accessoryButton:nil];

	popUp_minimumFontSize = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Minimum Font Size:",nil))
			  popUpButton:popUp_minimumFontSize
		  accessoryButton:nil];

	checkBox_showTabCount = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Show unread message count in tabs",nil)
				  control:checkBox_showTabCount];

	/* The nib showed this one on the group chat tab alone, and the preference it
	 * writes is read for group chats alone (-[AIMessageTabViewItem objectCount]).
	 * A row cannot come and go without the card jumping, so it stays and is
	 * enabled for group chats only; the detail line says why.
	 */
	checkBox_unreadMentionCount = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AISentenceCaseLabel(AILocalizedString(@"…only count number of unread mentions",nil))
				  control:checkBox_unreadMentionCount
				   detail:AILocalizedString(@"Applies to group chats.",
											"Explanation that the unread mention count is a group chat setting")];

	//Tabs
	//Window handling
	[form addSectionHeader:AILocalizedString(@"Window Handling",nil)];

	checkBox_hide = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Hide while Adium is in the background",nil)
				  control:checkBox_hide];

	checkBox_psychicOpen = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Open chats as soon as contacts begin typing",nil)
				  control:checkBox_psychicOpen];

	/* No target/action: every item of the window level menu carries its own,
	 * -selectedWindowLevel:, exactly as it did with the nib's pop up.
	 */
	popUp_windowPosition = [AISettingsFormView popUpButtonWithTitles:nil target:nil action:NULL];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Order message windows:",nil))
			  popUpButton:popUp_windowPosition
		  accessoryButton:nil];

	return form;
}

/*!
 * @brief The switch between the regular chat and the group chat settings.
 *
 * The nib's tab view, minus the tabs: a two-segment control keeps both choices
 * visible and, unlike a tab view, does not put a frame around half the pane. The
 * titles are the ones the tabs carried, so every existing translation applies.
 */
- (NSSegmentedControl *)chatTypeSegmentedControl
{
	NSSegmentedControl	*segment = [[[NSSegmentedControl alloc] initWithFrame:NSZeroRect] autorelease];

	[segment setSegmentCount:2];
	[segment setSegmentStyle:NSSegmentStyleAutomatic];
	[segment setTrackingMode:NSSegmentSwitchTrackingSelectOne];
	[segment setLabel:AILocalizedString(@"Regular Chats", nil) forSegment:AIWebkitRegularChat];
	[segment setLabel:AILocalizedString(@"Group Chats", nil) forSegment:AIWebkitGroupChat];
	[segment setSelectedSegment:AIWebkitRegularChat];
	[segment setTarget:self];
	[segment setAction:@selector(changeChatType:)];
	[segment sizeToFit];

	return segment;
}

- (void)viewWillClose
{
	settingsForm = nil;

	segment_chatType = nil;
	checkBox_customNameFormatting = nil;
	popUp_nameFormat = nil;
	popUp_timeStampFormat = nil;
	popUp_minimumFontSize = nil;
	checkBox_showTabCount = nil;
	checkBox_unreadMentionCount = nil;
	checkBox_hide = nil;
	checkBox_psychicOpen = nil;
	popUp_windowPosition = nil;

	[super viewWillClose];
}

#pragma mark The two sets of preferences

- (AIWebkitStyleType)currentTab
{
	/* Read from the ivar rather than from the control: a stray action arriving
	 * after -viewWillClose still has to know which group it was writing to.
	 */
	return selectedChatType;
}

- (NSString *)preferenceGroupForCurrentTab
{
	NSString *prefGroup = nil;

	switch(self.currentTab) {
		case AIWebkitRegularChat:
			prefGroup = PREF_GROUP_WEBKIT_REGULAR_MESSAGE_DISPLAY;
			break;

		case AIWebkitGroupChat:
			prefGroup = PREF_GROUP_WEBKIT_GROUP_MESSAGE_DISPLAY;
			break;
	}

	return prefGroup;
}

/*!
 * @brief The user switched between regular and group chats.
 *
 * Only the values in the rows change, never the rows themselves — a card that
 * gained or lost a row here would jump under the pointer. Nothing is written:
 * which of the two sets is on screen is not a preference.
 */
- (IBAction)changeChatType:(id)sender
{
	selectedChatType = (([sender selectedSegment] == AIWebkitGroupChat) ? AIWebkitGroupChat : AIWebkitRegularChat);

	[self configurePreferencesForTab];

	/* The new values may be wider or narrower than the old ones — a pop up row
	 * sizes its button to the title it shows, so ask for a fresh layout.
	 */
	[settingsForm noteContentSizeChanged];
}

/*!
 * @brief Show the values of whichever chat type is selected.
 *
 * The menus themselves do not depend on the selection and are built once, in
 * -viewDidLoad; only the selected items and the switch states change here.
 */
- (void)configurePreferencesForTab
{
	NSDictionary *prefDict = [adium.preferenceController preferencesForGroup:self.preferenceGroupForCurrentTab];

	[checkBox_customNameFormatting setState:([[prefDict objectForKey:KEY_WEBKIT_USE_NAME_FORMAT] boolValue] ?
											 NSControlStateValueOn : NSControlStateValueOff)];

	/* AIDefaultName — what a fresh installation has stored — has no item in this
	 * menu, and neither did it have one in the nib, where the pop up was left
	 * showing "User Name" instead of nothing at all. Keep that: with custom
	 * formatting off the menu is dimmed anyway, and the first thing the user picks
	 * is what gets written.
	 */
	if (![popUp_nameFormat selectItemWithTag:[[prefDict objectForKey:KEY_WEBKIT_NAME_FORMAT] integerValue]]) {
		[popUp_nameFormat selectItemWithTag:AIScreenName];
	}

	[popUp_minimumFontSize selectItemWithTag:[[prefDict objectForKey:KEY_WEBKIT_MIN_FONT_SIZE] integerValue]];

	/* No format stored — the usual case, since none is registered as a default —
	 * means the message style decides, which the first item stands for. The nib
	 * rebuilt this menu at every chat type switch and so fell back to item 0 all
	 * by itself; -selectItemWithRepresentedObject: leaves the old selection alone
	 * when nothing matches, which would show the other chat type's format here.
	 */
	if (![popUp_timeStampFormat selectItemWithRepresentedObject:[prefDict objectForKey:KEY_WEBKIT_TIME_STAMP_FORMAT]] &&
		[popUp_timeStampFormat numberOfItems]) {
		[popUp_timeStampFormat selectItemAtIndex:0];
	}

	BOOL showTabCount = [[adium.preferenceController preferenceForKey:(self.currentTab == AIWebkitGroupChat ? KEY_TABBAR_SHOW_UNREAD_COUNT_GROUP : KEY_TABBAR_SHOW_UNREAD_COUNT)
																group:PREF_GROUP_DUAL_WINDOW_INTERFACE] boolValue];
	[checkBox_showTabCount setState:(showTabCount ? NSControlStateValueOn : NSControlStateValueOff)];

	[checkBox_unreadMentionCount setState:([[adium.preferenceController preferenceForKey:KEY_TABBAR_SHOW_UNREAD_MENTION_ONLYGROUP
																				  group:PREF_GROUP_DUAL_WINDOW_INTERFACE] boolValue] ?
										   NSControlStateValueOn : NSControlStateValueOff)];

	[self configureControlDimming];
}

#pragma mark Changing preferences

/* Every control writes at once. The preference window only calls -closeView when
 * the whole window closes — switching to another pane merely takes our view out
 * of it — so anything kept back until then would be kept back for good.
 */

//Called in response to all preference controls, applies new settings
- (IBAction)changePreference:(id)sender
{
    if (sender == checkBox_hide) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
											 forKey:KEY_WINDOW_HIDE
											  group:PREF_GROUP_DUAL_WINDOW_INTERFACE];

	} else if (sender == checkBox_psychicOpen) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
											 forKey:KEY_PSYCHIC
											  group:PREF_GROUP_DUAL_WINDOW_INTERFACE];

	} else if (sender == checkBox_customNameFormatting) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
											 forKey:KEY_WEBKIT_USE_NAME_FORMAT
											  group:self.preferenceGroupForCurrentTab];

	} else if (sender == popUp_nameFormat) {
		[adium.preferenceController setPreference:[NSNumber numberWithInteger:[[sender selectedItem] tag]]
											 forKey:KEY_WEBKIT_NAME_FORMAT
											  group:self.preferenceGroupForCurrentTab];

	} else if (sender == popUp_minimumFontSize) {
		[adium.preferenceController setPreference:[NSNumber numberWithInteger:[[sender selectedItem] tag]]
											 forKey:KEY_WEBKIT_MIN_FONT_SIZE
											  group:self.preferenceGroupForCurrentTab];

	} else if (sender == popUp_timeStampFormat) {
		[adium.preferenceController setPreference:[[sender selectedItem] representedObject]
											 forKey:KEY_WEBKIT_TIME_STAMP_FORMAT
											  group:self.preferenceGroupForCurrentTab];

	} else if (sender == checkBox_showTabCount) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
										   forKey:(self.currentTab == AIWebkitGroupChat ? KEY_TABBAR_SHOW_UNREAD_COUNT_GROUP : KEY_TABBAR_SHOW_UNREAD_COUNT)
											group:PREF_GROUP_DUAL_WINDOW_INTERFACE];

	} else if (sender == checkBox_unreadMentionCount) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
										   forKey:KEY_TABBAR_SHOW_UNREAD_MENTION_ONLYGROUP
											group:PREF_GROUP_DUAL_WINDOW_INTERFACE];
	}

	[self configureControlDimming];

	/* A menu selection is a new button title and therefore a new button width;
	 * the pop up row measures it again when it is asked for a layout.
	 */
	if ([sender isKindOfClass:[NSPopUpButton class]]) [settingsForm noteContentSizeChanged];
}

/*!
* @brief User selected a window level
 */
- (void)selectedWindowLevel:(id)sender
{
	[adium.preferenceController setPreference:[NSNumber numberWithInteger:[sender tag]]
										 forKey:KEY_WINDOW_LEVEL
										  group:PREF_GROUP_DUAL_WINDOW_INTERFACE];

	//The chosen level is the button's new title, and titles have widths
	[settingsForm noteContentSizeChanged];
}

//Configure the preference view
- (void)viewDidLoad
{
    NSDictionary	*prefDict;
	NSInteger				menuIndex;

	/* The menus do not depend on which chat type is selected, so they are built
	 * once: rebuilding them on every switch would only cost a layout pass.
	 */
	[popUp_nameFormat setMenu:[self _nameFormatMenu]];
	[popUp_minimumFontSize setMenu:[self _fontSizeMenu]];
	[popUp_timeStampFormat setMenu:[self _timeStampMenu]];

	prefDict = [adium.preferenceController preferencesForGroup:PREF_GROUP_DUAL_WINDOW_INTERFACE];
	//Window position
	[popUp_windowPosition setMenu:[adium.interfaceController menuForWindowLevelsNotifyingTarget:self]];
	menuIndex =  [popUp_windowPosition indexOfItemWithTag:[[prefDict objectForKey:KEY_WINDOW_LEVEL] integerValue]];
	if (menuIndex >= 0 && menuIndex < [popUp_windowPosition numberOfItems]) {
		[popUp_windowPosition selectItemAtIndex:menuIndex];
	}

	[checkBox_hide setState:([[prefDict objectForKey:KEY_WINDOW_HIDE] boolValue] ?
							NSControlStateValueOn : NSControlStateValueOff)];
	[checkBox_psychicOpen setState:([[prefDict objectForKey:KEY_PSYCHIC] boolValue] ?
									NSControlStateValueOn : NSControlStateValueOff)];

	[segment_chatType setSelectedSegment:self.currentTab];

	[self configurePreferencesForTab];
    [self configureControlDimming];

	[super viewDidLoad];
}

- (void)configureControlDimming
{
	[popUp_nameFormat setEnabled:([checkBox_customNameFormatting state] == NSControlStateValueOn)];

	/* Only group chat tabs ever show a mention count, so the row follows the
	 * chat type as well as the count switch above it.
	 */
	[checkBox_unreadMentionCount setEnabled:((self.currentTab == AIWebkitGroupChat) &&
											 ([checkBox_showTabCount state] == NSControlStateValueOn))];
}

#pragma mark Menus

/*!
 * @brief Build & return the menu of name formats
 *
 * Built here rather than in the nib for easy localization; the tags are the
 * AINameFormat values the message style reads.
 */
- (NSMenu *)_nameFormatMenu
{
	NSMenu	*menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];

	[menu addItemWithTitle:AILocalizedString(@"Alias", nil)
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AIDisplayName];
	[menu addItemWithTitle:AILocalizedString(@"Alias (User Name)", nil)
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AIDisplayName_ScreenName];
	[menu addItemWithTitle:AILocalizedString(@"User Name (Alias)", nil)
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AIScreenName_DisplayName];
	[menu addItemWithTitle:AILocalizedString(@"User Name", nil)
					target:nil
					action:nil
			 keyEquivalent:@""
					   tag:AIScreenName];

	return menu;
}

/*!
 * @brief Build & return a time stamp menu
 */
- (NSMenu *)_timeStampMenu
{
	NSMenu	*menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];

	//Generate all the available time stamp formats
	//If there is no difference between the time stamp with AM/PM and the one without, the localized time stamp must
	//not include AM/PM.  Since these menu items would appear as duplicates we exclude them.

    __block NSString	*sampleStampA, *sampleStampB;

	[NSDateFormatter withLocalizedDateFormatterShowingSeconds:NO showingAMorPM:YES perform:^(NSDateFormatter *noSecondsAMPM){
		sampleStampA = [[noSecondsAMPM stringForObjectValue:[NSDate date]] retain];
	}];
	[sampleStampA autorelease];

	[NSDateFormatter withLocalizedDateFormatterShowingSeconds:NO showingAMorPM:NO perform:^(NSDateFormatter *noSecondsNoAMPM){
		sampleStampB = [[noSecondsNoAMPM stringForObjectValue:[NSDate date]] retain];
	}];
	[sampleStampB autorelease];

	BOOL		noAMPM = [sampleStampA isEqualToString:sampleStampB];

	//Build the menu from the available formats
	[NSDateFormatter withLocalizedDateFormatterShowingSeconds:NO showingAMorPM:NO perform:^(NSDateFormatter *noSecondsNoAMPM){
		[self _addTimeStampChoice:noSecondsNoAMPM toMenu:menu];
	}];

	[NSDateFormatter withLocalizedDateFormatterShowingSeconds:NO showingAMorPM:YES perform:^(NSDateFormatter *noSecondsAMPM){
		if (!noAMPM) [self _addTimeStampChoice:noSecondsAMPM toMenu:menu];
	}];

	[NSDateFormatter withLocalizedDateFormatterShowingSeconds:YES showingAMorPM:NO perform:^(NSDateFormatter *secondsNoAMPM){
		[self _addTimeStampChoice:secondsNoAMPM toMenu:menu];
	}];

	[NSDateFormatter withLocalizedDateFormatterShowingSeconds:YES showingAMorPM:YES perform:^(NSDateFormatter *secondsAMPM){
		if (!noAMPM) [self _addTimeStampChoice:secondsAMPM toMenu:menu];
	}];

	return menu;
}
- (void)_addTimeStampChoice:(NSDateFormatter *)formatter toMenu:(NSMenu *)menu
{
	[menu addItemWithTitle:[formatter stringForObjectValue:[NSDate date]]
					target:nil
					action:nil
			 keyEquivalent:@""
		 representedObject:[formatter dateFormat]];
}

/*!
 * @brief Build & return a font size menu
 */
- (NSMenu *)_fontSizeMenu
{
	NSMenu		*menu = [[[NSMenu alloc] init] autorelease];
	NSMenuItem	*menuItem;

	NSUInteger sizes[] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,18,20,22,24,36,48,64,72,96};
	NSUInteger loopCounter;

	for (loopCounter = 0; loopCounter < 23; loopCounter++) {
		menuItem = [[[NSMenuItem alloc] initWithTitle:[[NSNumber numberWithInteger:sizes[loopCounter]] stringValue]
																		 target:nil
																		 action:nil
																  keyEquivalent:@""] autorelease];
		[menuItem setTag:sizes[loopCounter]];
		[menu addItem:menuItem];
	}

	return menu;
}

@end
