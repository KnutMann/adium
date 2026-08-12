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

#import "ESContactListAdvancedPreferences.h"
#import "AISCLViewPlugin.h"
#import "AIPreferenceWindowController.h"
#import "AIListWindowController.h"
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIDictionaryAdditions.h>
#import <AIUtilities/AIImageAdditions.h>

//Width the form starts out at; the preferences window resizes it to its column.
#define CONTACT_LIST_ADVANCED_PANE_INITIAL_WIDTH	540.0

/* One string, two rows: the tooltip option and the middle hiding choice. Still a
 * macro rather than a variable, as it was in the nib-driven version, so
 * AILocalizedString() expands where it is used — it asks [self class] for the
 * bundle to look the string up in.
 */
#define WHILE_ADIUM_IS_IN_BACKGROUND	AILocalizedString(@"While Adium is in the background","Checkbox to indicate that something should occur while Adium is not the active application")

@interface ESContactListAdvancedPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (void)configureControlDimming;
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
	/* U+003A and the full width U+FF1A the CJK translations use ("連絡先リストの表示：") */
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
 * "...only while Adium is in the background" read as the continuation of the
 * "On screen edges" cell it was indented under. As a row of its own it is a
 * title, so the marks of that continuation go: the leading dots the
 * translations point back at that cell with ("… nur wenn Adium im Hintergrund
 * ist"), a trailing full stop, and lower case at the front.
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

	NSString	*localization = [[[NSBundle bundleForClass:[ESContactListAdvancedPreferences class]] preferredLocalizations] firstObject];
	NSLocale	*locale = (localization ? [NSLocale localeWithLocaleIdentifier:localization] : [NSLocale currentLocale]);
	NSRange		 first = [trimmed rangeOfComposedCharacterSequenceAtIndex:0];
	NSString	*head = [[trimmed substringWithRange:first] uppercaseStringWithLocale:locale];

	return [trimmed stringByReplacingCharactersInRange:first withString:head];
}

/*!
 * @class ESContactListAdvancedPreferences
 * @brief Advanced contact list preferences
 */
@implementation ESContactListAdvancedPreferences
#pragma mark Preference pane settings

/*!
 * @brief Label
 */
- (NSString *)label{
    return AILocalizedString(@"Contact List","Name of the window which lists contacts");
}

/*!
 * @brief Image
 */
- (NSImage *)image{
	return [NSImage imageNamed:@"pref-contactList" forClass:[AIPreferenceWindowController class]];
}

/* No -nibName: the pane builds its own view below, so AIModularPane never loads
 * a nib for us. ContactListAdvancedPrefs.xib is dead — and it must stay
 * unloaded: it still wires outlets this class no longer has (matrix_hiding,
 * label_appearance, label_tooltips, label_windowHandling, label_hide,
 * label_orderTheContactList), so loading it would raise NSUnknownKeyException
 * rather than fall back to the old interface. Removing it from the target needs
 * project file access we do not have here.
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

		view = [form retain];

		[self viewDidLoad];
		[self localizePane];

		/* The pop up row measures its button itself at every layout, so all that
		 * is left after -viewDidLoad filled the window levels menu is one more
		 * layout pass.
		 */
		[form layoutForWidth:NSWidth([form frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief Undo everything -view built.
 *
 * -closeView unregisters the preference observer, releases the view and is
 * idempotent. Without it a deallocated pane would leave the form's rows — and
 * the KVO observations they register on their controls — alive, and the
 * preference controller would keep a non-retained pointer to us.
 */
- (void)dealloc
{
	[self closeView];
	[super dealloc];
}

/*!
 * @brief Create the controls and stack them into cards.
 *
 * Four cards. The nib had three bold labels with a rule under each — Appearance,
 * Tooltips, Window Handling — and expressed everything below them by
 * indentation: the "while Adium is in the background" tooltip option hung under
 * the tooltip checkbox, the "only while Adium is in the background" option under
 * the hiding matrix. Both are plain rows of their card now, and the hiding
 * choice moved into a card of its own, so what belongs together is a group
 * rather than a step to the right.
 *
 * Every control keeps the preference key and group its nib counterpart was bound
 * to; only the presentation changes. The nib wrote seven of these through
 * bindings on adium.preferenceController and left -changePreference: with
 * nothing but the dimming to do — the pane reads and writes all nine itself now
 * (see -preferencesChangedForGroup:… and -changePreference:), because a form
 * built in code has no binding to inherit.
 */
- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[[AISettingsFormView alloc] initWithWidth:CONTACT_LIST_ADVANCED_PANE_INITIAL_WIDTH] autorelease];

	//The nib's "Appearance" label, kept as the card's section header
	[form addSectionHeader:AILocalizedString(@"Appearance",nil)];

	checkBox_flash = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Flash names with unviewed messages",nil)
				  control:checkBox_flash];

	checkBox_animateChanges = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Animate changes","This string is under the heading 'Contact List' and refers to changes such as sort order in the contact list being animated rather than occurring instantenously")
				  control:checkBox_animateChanges];

	checkBox_windowHasShadow = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Show window shadow",nil)
				  control:checkBox_windowHasShadow];
	/* Not localized, and not a typo: it has been the pane's Babylon 5 joke since
	 * 2005. On the whole row, not on the switch alone — in the nib the checkbox
	 * carried its own title, so the words showed it too.
	 */
	[form setToolTip:@"Stay close to the Vorlon." forRowWithControl:checkBox_windowHasShadow];

	//The nib's "Tooltips" label
	[form addSectionHeader:AILocalizedString(@"Tooltips",nil)];

	checkBox_showTooltips = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Show contact information tooltips",nil)
				  control:checkBox_showTooltips];

	/* Indented under the checkbox above in the nib; a row of equal rank now, dimmed
	 * with it exactly as before (-configureControlDimming).
	 */
	checkBox_showTooltipsInBackground = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:WHILE_ADIUM_IS_IN_BACKGROUND
				  control:checkBox_showTooltipsInBackground];

	//The nib's "Window Handling" label
	[form addSectionHeader:AILocalizedString(@"Window Handling",nil)];

	/* Where the contact list sits in the window order. A pop up row rather than a
	 * plain control row: the menu is built by the interface controller in
	 * -viewDidLoad, and only this row re-measures its button at every layout.
	 */
	popUp_windowPosition = [AISettingsFormView popUpButtonWithTitles:nil target:nil action:NULL];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Show the contact list:",nil))
			  popUpButton:popUp_windowPosition
		  accessoryButton:nil];

	checkBox_showOnAllSpaces = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Show on all spaces", nil)
				  control:checkBox_showOnAllSpaces];

	/* When the list takes itself off screen. Its own, header-less card: the choice
	 * and the option qualifying it belong together and to neither of the two rows
	 * above, and a card boundary is the only grouping System Settings has for that.
	 * A pop up rather than the nib's three radio buttons: every other choice on this
	 * page is one, and three mutually exclusive options read as a menu here.
	 */
	[form endCard];

	popUp_hidingStyle = [AISettingsFormView popUpButtonWithTitles:[NSArray arrayWithObjects:
																   AILocalizedString(@"Never", nil),
																   WHILE_ADIUM_IS_IN_BACKGROUND,
																   AILocalizedString(@"On screen edges", "Advanced contact list: hide the contact list: On screen edges"),
																   nil]
														   target:self
														   action:@selector(changePreference:)];
	[[popUp_hidingStyle itemAtIndex:0] setTag:AIContactListWindowHidingStyleNone];
	[[popUp_hidingStyle itemAtIndex:1] setTag:AIContactListWindowHidingStyleBackground];
	[[popUp_hidingStyle itemAtIndex:2] setTag:AIContactListWindowHidingStyleSliding];

	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Automatically hide the contact list:",nil))
			  popUpButton:popUp_hidingStyle
		  accessoryButton:nil];

	/* The nib pointed this at the cell above it with a leading ellipsis and an
	 * indent. Standing on its own it needs a sentence of its own to say which of
	 * the three choices it narrows down; it is dimmed unless that choice is made.
	 */
	checkBox_hideOnScreenEdgesOnlyInBackground = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AISentenceCaseLabel(AILocalizedString(@"...only while Adium is in the background", "Checkbox under 'on screen edges' in the advanced contact list preferences"))
				  control:checkBox_hideOnScreenEdgesOnlyInBackground
				   detail:AILocalizedString(@"Only applies when the contact list hides on screen edges.", "Explanation below the option which restricts hiding on screen edges to the time Adium is not the active application")];

	return form;
}

#pragma mark Configuration

/*!
 * @brief View loaded; configure it for display
 */
- (void)viewDidLoad
{
	/* Built by the interface controller, whose items carry their own target and
	 * -selectedWindowLevel: action — which is why the button itself needs none.
	 */
	[popUp_windowPosition setMenu:[adium.interfaceController menuForWindowLevelsNotifyingTarget:self]];

	/* Fills every control: the registration itself calls us back with
	 * firstTime YES. The nib had bindings do this; an observer is what replaces
	 * them, so a change made elsewhere still shows up here.
	 */
	[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_CONTACT_LIST];

	[super viewDidLoad];
}

- (void)viewWillClose
{
	//The controller keeps a non-retained pointer to us
	[adium.preferenceController unregisterPreferenceObserver:self];

	/* The form owns every control; these are the pane's non-owning references to
	 * them and must not outlive the view.
	 */
	popUp_windowPosition = nil;
	popUp_hidingStyle = nil;
	checkBox_hideOnScreenEdgesOnlyInBackground = nil;
	checkBox_flash = nil;
	checkBox_animateChanges = nil;
	checkBox_showTooltips = nil;
	checkBox_showTooltipsInBackground = nil;
	checkBox_windowHasShadow = nil;
	checkBox_showOnAllSpaces = nil;

	[super viewWillClose];
}

#pragma mark Reading the preferences

/*!
 * @brief A preference of our group changed: show it.
 *
 * Also our way in: -registerPreferenceObserver:forGroup: calls this with
 * firstTime YES, which is what fills the controls initially.
 */
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key object:(AIListObject *)object
					preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	//Nothing here is set per contact; an object-specific update is none of our business
	if (object || ![group isEqualToString:PREF_GROUP_CONTACT_LIST]) return;

	if (firstTime || [key isEqualToString:KEY_CL_FLASH_UNVIEWED_CONTENT]) {
		[checkBox_flash setState:([[prefDict objectForKey:KEY_CL_FLASH_UNVIEWED_CONTENT] boolValue] ?
								  NSControlStateValueOn : NSControlStateValueOff)];
	}

	if (firstTime || [key isEqualToString:KEY_CL_ANIMATE_CHANGES]) {
		[checkBox_animateChanges setState:([[prefDict objectForKey:KEY_CL_ANIMATE_CHANGES] boolValue] ?
										   NSControlStateValueOn : NSControlStateValueOff)];
	}

	if (firstTime || [key isEqualToString:KEY_CL_WINDOW_HAS_SHADOW]) {
		[checkBox_windowHasShadow setState:([[prefDict objectForKey:KEY_CL_WINDOW_HAS_SHADOW] boolValue] ?
											NSControlStateValueOn : NSControlStateValueOff)];
	}

	if (firstTime || [key isEqualToString:KEY_CL_SHOW_TOOLTIPS]) {
		[checkBox_showTooltips setState:([[prefDict objectForKey:KEY_CL_SHOW_TOOLTIPS] boolValue] ?
										 NSControlStateValueOn : NSControlStateValueOff)];
	}

	if (firstTime || [key isEqualToString:KEY_CL_SHOW_TOOLTIPS_IN_BACKGROUND]) {
		[checkBox_showTooltipsInBackground setState:([[prefDict objectForKey:KEY_CL_SHOW_TOOLTIPS_IN_BACKGROUND] boolValue] ?
													 NSControlStateValueOn : NSControlStateValueOff)];
	}

	if (firstTime || [key isEqualToString:KEY_CL_ALL_SPACES]) {
		[checkBox_showOnAllSpaces setState:([[prefDict objectForKey:KEY_CL_ALL_SPACES] boolValue] ?
											NSControlStateValueOn : NSControlStateValueOff)];
	}

	if (firstTime || [key isEqualToString:KEY_CL_SLIDE_ONLY_IN_BACKGROUND]) {
		[checkBox_hideOnScreenEdgesOnlyInBackground setState:([[prefDict objectForKey:KEY_CL_SLIDE_ONLY_IN_BACKGROUND] boolValue] ?
															  NSControlStateValueOn : NSControlStateValueOff)];
	}

	if (firstTime || [key isEqualToString:KEY_CL_WINDOW_HIDING_STYLE]) {
		/* A stored value outside the enum must not leave the menu showing whatever
		 * happened to be selected: -selectItemWithTag: answers NO and changes nothing,
		 * so fall back to the first item the way the nib's matrix did.
		 */
		if (![popUp_hidingStyle selectItemWithTag:[[prefDict objectForKey:KEY_CL_WINDOW_HIDING_STYLE] integerValue]]) {
			[popUp_hidingStyle selectItemAtIndex:0];
		}
	}

	if (firstTime || [key isEqualToString:KEY_CL_WINDOW_LEVEL]) {
		/* The menu is the interface controller's, so it may not hold the stored
		 * level at all; leaving the selection alone beats picking a level the user
		 * never chose.
		 */
		NSInteger	menuIndex = [popUp_windowPosition indexOfItemWithTag:[[prefDict objectForKey:KEY_CL_WINDOW_LEVEL] integerValue]];

		if (menuIndex >= 0 && menuIndex < [popUp_windowPosition numberOfItems]) {
			[popUp_windowPosition selectItemAtIndex:menuIndex];
		}
	}

	[self configureControlDimming];
}

#pragma mark Changing preferences

/*!
 * @brief Called in response to all preference controls, applies new settings
 *
 * Every control writes the moment it is touched. The preferences window only
 * calls -closeView when it closes — switching to another pane takes the view out
 * with -removeFromSuperview — so there is no later point at which anything could
 * be saved.
 */
- (IBAction)changePreference:(id)sender
{
	/* Read through the ivar rather than through sender: -state is declared on
	 * NSSwitch and on NSButton alike, and asking an untyped id for it leaves the
	 * compiler to pick one of them.
	 */
	if (sender == checkBox_flash) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_flash state] == NSControlStateValueOn)]
										   forKey:KEY_CL_FLASH_UNVIEWED_CONTENT
											group:PREF_GROUP_CONTACT_LIST];
	}

	if (sender == checkBox_animateChanges) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_animateChanges state] == NSControlStateValueOn)]
										   forKey:KEY_CL_ANIMATE_CHANGES
											group:PREF_GROUP_CONTACT_LIST];
	}

	if (sender == checkBox_windowHasShadow) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_windowHasShadow state] == NSControlStateValueOn)]
										   forKey:KEY_CL_WINDOW_HAS_SHADOW
											group:PREF_GROUP_CONTACT_LIST];
	}

	if (sender == checkBox_showTooltips) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_showTooltips state] == NSControlStateValueOn)]
										   forKey:KEY_CL_SHOW_TOOLTIPS
											group:PREF_GROUP_CONTACT_LIST];
	}

	if (sender == checkBox_showTooltipsInBackground) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_showTooltipsInBackground state] == NSControlStateValueOn)]
										   forKey:KEY_CL_SHOW_TOOLTIPS_IN_BACKGROUND
											group:PREF_GROUP_CONTACT_LIST];
	}

	if (sender == checkBox_showOnAllSpaces) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_showOnAllSpaces state] == NSControlStateValueOn)]
										   forKey:KEY_CL_ALL_SPACES
											group:PREF_GROUP_CONTACT_LIST];
	}

	if (sender == checkBox_hideOnScreenEdgesOnlyInBackground) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_hideOnScreenEdgesOnlyInBackground state] == NSControlStateValueOn)]
										   forKey:KEY_CL_SLIDE_ONLY_IN_BACKGROUND
											group:PREF_GROUP_CONTACT_LIST];
	}

	if (sender == popUp_hidingStyle) {
		[adium.preferenceController setPreference:[NSNumber numberWithInteger:[[popUp_hidingStyle selectedItem] tag]]
										   forKey:KEY_CL_WINDOW_HIDING_STYLE
											group:PREF_GROUP_CONTACT_LIST];
	}

	[self configureControlDimming];
}

/*!
 * @brief Restricting the sliding to the background is only a choice while it slides
 */
- (BOOL)hideOnScreenEdgesOnlyInBackgroundEnabled
{
	return ([[popUp_hidingStyle selectedItem] tag] == AIContactListWindowHidingStyleSliding);
}

- (void)configureControlDimming
{
	[checkBox_hideOnScreenEdgesOnlyInBackground setEnabled:[self hideOnScreenEdgesOnlyInBackgroundEnabled]];

	/* The nib bound this checkbox's enabled state straight to "Show Tooltips";
	 * the switch above holds that same value, and dimming follows it here.
	 */
	[checkBox_showTooltipsInBackground setEnabled:([checkBox_showTooltips state] == NSControlStateValueOn)];
}

/*!
 * @brief An item of the window levels menu was chosen
 */
- (void)selectedWindowLevel:(id)sender
{
	[adium.preferenceController setPreference:[NSNumber numberWithInteger:[sender tag]]
										 forKey:KEY_CL_WINDOW_LEVEL
										  group:PREF_GROUP_CONTACT_LIST];
}

@end
