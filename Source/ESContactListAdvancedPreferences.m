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
#import "AIAppearancePreferencesPlugin.h"
#import <Adium/AIDockControllerProtocol.h>
#import <AIUtilities/AIPopUpButtonAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "ESPresetNameSheetController.h"
#import "ESPresetManagementController.h"
#import <Adium/AIAbstractListController.h>
#import <AIUtilities/AIDictionaryAdditions.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIStringUtilities.h>

//The widest the two readouts ever get, so their columns do not shift while a slider moves
#define OPACITY_WIDEST_VALUE	@"100%"
#define WIDTH_WIDEST_VALUE		@"640px"

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
	NSMutableCharacterSet	*strip = [[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopy];
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
/* Unlocalized, unlike the label: the sidebar grouping matches panes by this,
 * and a match must not depend on the user's language. */
- (NSString *)paneIdentifier{
	return @"Contact List";
}
- (NSString *)label{
    return AILocalizedString(@"Contact List","Name of the window which lists contacts");
}

/*!
 * @brief Image
 */
- (NSImage *)image{
	return [NSImage imageNamed:@"pref-contactList" forClass:[AIPreferenceWindowController class]];
}

/* No -nibName: the pane builds its own view below, so AIModularPane never loads a nib for us.
 * ContactListAdvancedPrefs.xib, which used to hold this interface, has been deleted along with its entry
 * in the target: nothing loaded it any more, and it still wired outlets this class no longer has,
 * so anything that did load it would have raised rather than fallen back.
 */

#pragma mark View

/*!
 * @brief Build our view instead of loading a nib.
 *
 * Mirrors -[AIModularPane view] so the subclass hooks fire in the same order.
 */
- (NSView *)view
{
	/* Building this pane sets a root page on the navigation controller, which
	 * says so at once, and what is told may ask the pane for its view. That call
	 * must not start the build again, or the settings window hangs. The ivar is
	 * filled early enough below that this should never trigger; it is here so
	 * that a callback added later cannot bring the hang back quietly. */
	if (buildingView) return view;

	if (!view) {
		buildingView = YES;
		/* The form is no longer the pane's view but its first page. What the pane
		 * hands out is the navigation controller's container, so that the settings
		 * of a colour set or a layout can slide in over it without the window
		 * having to know that anything moved. */
		rootForm = [self buildSettingsForm];

		NSViewController *rootPage = [[NSViewController alloc] init];
		[rootPage setView:rootForm];

		navigationController = [[AISettingsNavigationController alloc] init];

		/* The container is taken first, before the delegate is set and before
		 * anything is put in it. Setting the root page says so at once, and what
		 * is told asks this pane for its view; with the ivar still empty that
		 * call builds the whole pane a second time, which sets a root page,
		 * which says so at once. The settings window hangs on the spot.
		 *
		 * The account list gets away with the other order because its nib fills
		 * the same ivar before any of this runs. This pane has no nib. */
		view = [navigationController view];

		[navigationController setDelegate:self];
		[navigationController setRootViewController:rootPage];

		[self viewDidLoad];
		[self localizePane];

		/* The pop up row measures its button itself at every layout, so all that
		 * is left after -viewDidLoad filled the window levels menu is one more
		 * layout pass.
		 */
		[rootForm layoutForWidth:NSWidth([rootForm frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];

		buildingView = NO;
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
	AISettingsFormView	*form = [[AISettingsFormView alloc] initWithWidth:CONTACT_LIST_ADVANCED_PANE_INITIAL_WIDTH];

	//The window the list is drawn in. First card, no header: the pane's name says it.
	popUp_windowStyle = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Window Style:",nil))
			  popUpButton:popUp_windowStyle
		  accessoryButton:nil];

	/* Five percent, not zero, exactly as in the nib this came from: a contact
	 * list at zero opacity is invisible *and* clickable-through in the styles
	 * which do not force the window to catch mouse events, so the only way back
	 * would be this pane. */
	slider_windowOpacity = [AISettingsFormView sliderWithMinValue:5.0
														 maxValue:100.0
														   target:self
														   action:@selector(changePreference:)];
	//As in the nib: the readout and the contact list follow the knob while dragging
	[slider_windowOpacity setContinuous:YES];
	textField_windowOpacity = [AISettingsFormView valueLabelForWidestValue:OPACITY_WIDEST_VALUE];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Opacity:",nil))
				   slider:slider_windowOpacity
			   valueLabel:textField_windowOpacity];

	checkBox_horizontalAutosizing = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Size to fit horizontally",nil)
				  control:checkBox_horizontalAutosizing];

	/* Its label is the one thing here which is not constant: the borderless styles
	 * turn this slider into a plain width slider, and -preferencesChangedForGroup:…
	 * retitles the row accordingly. */
	slider_horizontalWidth = [AISettingsFormView sliderWithMinValue:32.0
														  maxValue:640.0
															target:self
															action:@selector(changePreference:)];
	[slider_horizontalWidth setContinuous:YES];
	textField_horizontalWidthIndicator = [AISettingsFormView valueLabelForWidestValue:WIDTH_WIDEST_VALUE];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Maximum Width:",nil))
				   slider:slider_horizontalWidth
			   valueLabel:textField_horizontalWidthIndicator];

	checkBox_verticalAutosizing = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Size to fit vertically",nil)
				  control:checkBox_verticalAutosizing];

	checkBox_windowHasShadow = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Show window shadow",nil)
				  control:checkBox_windowHasShadow];
	/* Not localized, and not a typo: it has been the pane's Babylon 5 joke since
	 * 2005. On the whole row, not on the switch alone, because in the nib the
	 * checkbox carried its own title and the words showed it too.
	 */
	[form setToolTip:@"Stay close to the Vorlon." forRowWithControl:checkBox_windowHasShadow];

	/* How the list is drawn: two saved sets, each with a page of its own a step
	 * below this one. */
	[form addSectionHeader:AILocalizedString(@"Drawing","Section header above the contact list's colour scheme and layout")];

	popUp_colorTheme = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	button_customizeColorTheme = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Customize",nil)
																 target:self
																 action:@selector(customizeListTheme:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"Color Theme:",nil))
			  popUpButton:popUp_colorTheme
		  accessoryButton:button_customizeColorTheme];

	popUp_listLayout = [AISettingsFormView popUpButtonWithTitles:nil target:self action:@selector(changePreference:)];
	button_customizeListLayout = [AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Customize",nil)
																 target:self
																 action:@selector(customizeListLayout:)];
	[form addRowWithLabel:AIRowLabel(AILocalizedString(@"List Layout:",nil))
			  popUpButton:popUp_listLayout
		  accessoryButton:button_customizeListLayout];

	//How the list behaves, which is not how it is drawn
	[form addSectionHeader:AILocalizedString(@"Behavior","Section header above what the contact list does rather than how it looks")];

	checkBox_flash = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Flash names with unviewed messages",nil)
				  control:checkBox_flash];

	checkBox_animateChanges = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Animate changes","This string is under the heading 'Contact List' and refers to changes such as sort order in the contact list being animated rather than occurring instantenously")
				  control:checkBox_animateChanges];

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

	//What the contact list window is drawn as, and which of the saved sets it is drawn with
	[popUp_windowStyle setMenu:[self _windowStyleMenu]];
	[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_APPEARANCE];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(xtrasChanged:)
												 name:AIXtrasDidChangeNotification
											   object:nil];
	[self xtrasChanged:nil];

	[super viewDidLoad];
}

- (void)viewWillClose
{
	//The controller keeps a non-retained pointer to us
	[adium.preferenceController unregisterPreferenceObserver:self];

	/* Only our own registration: removeObserver:self would silently take any
	 * other one, a category's or a superclass's, with it. */
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:AIXtrasDidChangeNotification
												  object:nil];

	/* Everything we scheduled: a relayout from a changed menu, but also the page
	 * that -presetNameSheetControllerDidEnd:… opens after a turn of the run loop.
	 * A deferred call reaching a closed pane would ask -view for a window and so
	 * raise a second form, with a second set of observers, that nothing would
	 * ever close again. */
	[NSObject cancelPreviousPerformRequestsWithTarget:self];

	/* An open page is written and taken down here rather than left to be torn off
	 * with the view: its settings belong in a set on disk, and the view going
	 * away is not a reason to lose them. */
	[self commitOpenAppearancePage];
	[navigationController popToRootViewController];
	[detailPage tearDown];
	detailPage = nil;
	[navigationController setDelegate:nil];
	navigationController = nil;
	rootForm = nil;

	popUp_windowStyle = nil;
	popUp_colorTheme = nil;
	popUp_listLayout = nil;
	button_customizeColorTheme = nil;
	button_customizeListLayout = nil;
	checkBox_verticalAutosizing = nil;
	checkBox_horizontalAutosizing = nil;
	slider_windowOpacity = nil;
	textField_windowOpacity = nil;
	slider_horizontalWidth = nil;
	textField_horizontalWidthIndicator = nil;

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
	if (object) return;

	//What the list is drawn as and which sets it is drawn with live in the appearance group
	if ([group isEqualToString:PREF_GROUP_APPEARANCE]) {
		[self appearancePreferencesChangedForKey:key preferenceDict:prefDict firstTime:firstTime];
		return;
	}

	if (![group isEqualToString:PREF_GROUP_CONTACT_LIST]) return;

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


/*!
 * @brief The window style, its sliders, and the names of the two saved sets
 *
 * Which rows make sense depends on the style: a bubble list draws no window, so
 * it has to size itself vertically, and the width slider means a different thing
 * once horizontal sizing is off. AIListWindowController must match this for it to
 * make sense.
 */
- (void)appearancePreferencesChangedForKey:(NSString *)key
							preferenceDict:(NSDictionary *)prefDict
								 firstTime:(BOOL)firstTime
{
	if (firstTime) {
		[popUp_windowStyle selectItemWithTag:[[prefDict objectForKey:KEY_LIST_LAYOUT_WINDOW_STYLE] integerValue]];
		[checkBox_verticalAutosizing setState:[[prefDict objectForKey:KEY_LIST_LAYOUT_VERTICAL_AUTOSIZE] boolValue]];
		[checkBox_horizontalAutosizing setState:[[prefDict objectForKey:KEY_LIST_LAYOUT_HORIZONTAL_AUTOSIZE] boolValue]];
		[slider_windowOpacity setDoubleValue:([[prefDict objectForKey:KEY_LIST_LAYOUT_WINDOW_OPACITY] doubleValue] * 100.0)];
		[slider_horizontalWidth setIntegerValue:[[prefDict objectForKey:KEY_LIST_LAYOUT_HORIZONTAL_WIDTH] integerValue]];
		[self updateSliderValues];
	}

	if (firstTime ||
		[key isEqualToString:KEY_LIST_LAYOUT_WINDOW_STYLE] ||
		[key isEqualToString:KEY_LIST_LAYOUT_HORIZONTAL_AUTOSIZE]) {

		AIContactListWindowStyle windowStyle = [[prefDict objectForKey:KEY_LIST_LAYOUT_WINDOW_STYLE] intValue];
		BOOL horizontalAutosize = [[prefDict objectForKey:KEY_LIST_LAYOUT_HORIZONTAL_AUTOSIZE] boolValue];

		if (windowStyle == AIContactListWindowStyleStandard) {
			//A regular window is dragged to its width, so the slider is only a limit
			[self updateHorizontalWidthLabel:AILocalizedString(@"Maximum Width:",nil)];
			[slider_horizontalWidth setEnabled:horizontalAutosize];

		} else {
			//Every other style draws no frame to drag, so the slider sets the width itself
			[self updateHorizontalWidthLabel:(horizontalAutosize ?
											  AILocalizedString(@"Maximum Width:",nil) :
											  AILocalizedString(@"Width:",nil))];
			[slider_horizontalWidth setEnabled:YES];
		}

		switch (windowStyle) {
			case AIContactListWindowStyleStandard:
			case AIContactListWindowStyleBorderless:
			case AIContactListWindowStyleGroupChat:
				//These have a window, so sizing to fit is a choice
				[checkBox_verticalAutosizing setEnabled:YES];
				[checkBox_verticalAutosizing setState:[[adium.preferenceController preferenceForKey:KEY_LIST_LAYOUT_VERTICAL_AUTOSIZE
																							 group:PREF_GROUP_APPEARANCE] integerValue]];
				break;
			case AIContactListWindowStyleGroupBubbles:
			case AIContactListWindowStyleContactBubbles:
			case AIContactListWindowStyleContactBubbles_Fitted:
				//The bubble styles show no window; they have to size themselves
				[checkBox_verticalAutosizing setEnabled:NO];
				[checkBox_verticalAutosizing setState:YES];
		}

		//A page open below this one shows different rows for a different style
		if (detailPage) [detailPage rebuildForStyleChange];
	}

	if (firstTime || [key isEqualToString:KEY_LIST_LAYOUT_NAME]) {
		[popUp_listLayout selectItemWithRepresentedObject:[prefDict objectForKey:KEY_LIST_LAYOUT_NAME]];
	}
	if (firstTime || [key isEqualToString:KEY_LIST_THEME_NAME]) {
		[popUp_colorTheme selectItemWithRepresentedObject:[prefDict objectForKey:KEY_LIST_THEME_NAME]];
	}
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
	if (sender == popUp_windowStyle) {
		[adium.preferenceController setPreference:[NSNumber numberWithInteger:[[sender selectedItem] tag]]
										   forKey:KEY_LIST_LAYOUT_WINDOW_STYLE
											group:PREF_GROUP_APPEARANCE];
	}

	if (sender == checkBox_verticalAutosizing) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_verticalAutosizing state] == NSControlStateValueOn)]
										   forKey:KEY_LIST_LAYOUT_VERTICAL_AUTOSIZE
											group:PREF_GROUP_APPEARANCE];
	}

	if (sender == checkBox_horizontalAutosizing) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([checkBox_horizontalAutosizing state] == NSControlStateValueOn)]
										   forKey:KEY_LIST_LAYOUT_HORIZONTAL_AUTOSIZE
											group:PREF_GROUP_APPEARANCE];
	}

	if (sender == slider_windowOpacity) {
		/* Continuous, so this arrives once per pixel of the drag: keep the readout
		 * in step with the knob, but only write the preference, which redraws every
		 * contact list window, when the value has really moved. The written value is
		 * the whole percent the readout shows, so a drag costs at most one write per
		 * percent instead of one per pixel. */
		double newValue = (NSInteger)[slider_windowOpacity doubleValue] / 100.0;
		double oldValue = [[adium.preferenceController preferenceForKey:KEY_LIST_LAYOUT_WINDOW_OPACITY
																 group:PREF_GROUP_APPEARANCE] doubleValue];

		[self updateSliderValues];

		if (fabs(newValue - oldValue) > 0.0001) {
			[adium.preferenceController setPreference:[NSNumber numberWithDouble:newValue]
											   forKey:KEY_LIST_LAYOUT_WINDOW_OPACITY
												group:PREF_GROUP_APPEARANCE];
		}
	}

	if (sender == slider_horizontalWidth) {
		NSInteger newValue = [slider_horizontalWidth integerValue];
		NSInteger oldValue = [[adium.preferenceController preferenceForKey:KEY_LIST_LAYOUT_HORIZONTAL_WIDTH
																	group:PREF_GROUP_APPEARANCE] integerValue];

		//Continuous as well; same rule as the opacity slider above
		[self updateSliderValues];

		if (newValue != oldValue) {
			[adium.preferenceController setPreference:[NSNumber numberWithInteger:newValue]
											   forKey:KEY_LIST_LAYOUT_HORIZONTAL_WIDTH
												group:PREF_GROUP_APPEARANCE];
		}
	}

	if (sender == popUp_listLayout) {
		[adium.preferenceController setPreference:[[sender selectedItem] title]
										   forKey:KEY_LIST_LAYOUT_NAME
											group:PREF_GROUP_APPEARANCE];
	}

	if (sender == popUp_colorTheme) {
		[adium.preferenceController setPreference:[[sender selectedItem] title]
										   forKey:KEY_LIST_THEME_NAME
											group:PREF_GROUP_APPEARANCE];
	}

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


//The contact list's own window ---------------------------------------------------------------------------------------
#pragma mark The window

- (NSMenu *)_windowStyleMenu
{
	NSMenu	*menu = [[NSMenu alloc] init];

	/* The titled window is the only style whose width the user can drag: every other style
	 * takes its width from the setting below and refuses to grow past it. It was taken out
	 * once because the system draws a taller title bar than it used to, and that turned out
	 * to cost more than it saved. */
	[self _addWindowStyleOption:AILocalizedString(@"Regular Window",nil)
						withTag:AIContactListWindowStyleStandard
						 toMenu:menu];
	[menu addItem:[NSMenuItem separatorItem]];
	[self _addWindowStyleOption:AILocalizedString(@"Borderless Window",nil)
						withTag:AIContactListWindowStyleBorderless
						 toMenu:menu];
	[self _addWindowStyleOption:AILocalizedString(@"Group Bubbles",nil)
						withTag:AIContactListWindowStyleGroupBubbles
						 toMenu:menu];
	[self _addWindowStyleOption:AILocalizedString(@"Contact Bubbles",nil)
						withTag:AIContactListWindowStyleContactBubbles
						 toMenu:menu];
	[self _addWindowStyleOption:AILocalizedString(@"Contact Bubbles (To Fit)",nil)
						withTag:AIContactListWindowStyleContactBubbles_Fitted
						 toMenu:menu];

	return menu;
}
- (void)_addWindowStyleOption:(NSString *)option withTag:(NSInteger)tag toMenu:(NSMenu *)menu{
    NSMenuItem	*menuItem = [[NSMenuItem alloc] initWithTitle:option
																				  target:nil
																				  action:nil
																		   keyEquivalent:@""];
	[menuItem setTag:tag];
	[menu addItem:menuItem];
}


//Contact list layout & theme ----------------------------------------------------------------------------------------
#pragma mark Contact list layout & theme

/*!
 * @brief Create a new theme
 */
- (IBAction)createListTheme:(id)sender
{
	NSString *theme = [adium.preferenceController preferenceForKey:KEY_LIST_THEME_NAME group:PREF_GROUP_APPEARANCE];
	
	ESPresetNameSheetController *presetNameSheetController = [[ESPresetNameSheetController alloc] initWithDefaultName:[[theme stringByAppendingString:@" "] stringByAppendingString:AILocalizedString(@"(Copy)", nil)]
																									  explanatoryText:AILocalizedString(@"Enter a unique name for this new theme.",nil)
																									  notifyingTarget:self
																											 userInfo:@"theme"];
	
	[presetNameSheetController showOnWindow:[self paneWindow]];
}

/*!
 * @brief Open the colours a step below this page
 */
- (IBAction)customizeListTheme:(id)sender
{
	[self openAppearancePageWithScope:AIContactListAppearanceScopeTheme];
}

/*!
 * @brief Write the changed colours back into the set they belong to
 */
- (void)saveListThemeNamed:(NSString *)name
{
	if ([plugin createSetFromPreferenceGroup:PREF_GROUP_LIST_THEME
									withName:name
								   extension:LIST_THEME_EXTENSION
									inFolder:LIST_THEME_FOLDER]) {
		[adium.preferenceController setPreference:name
										   forKey:KEY_LIST_THEME_NAME
											group:PREF_GROUP_APPEARANCE];
	}
}

/*!
 * @brief Manage available themes
 */
- (void)manageListThemes:(id)sender
{
	_listThemes = [plugin availableThemeSets];
	ESPresetManagementController *presetManagementController = [[ESPresetManagementController alloc] initWithPresets:_listThemes
																										  namedByKey:@"name"
																										withDelegate:self];
	[presetManagementController showOnWindow:[self paneWindow]];
	
	[popUp_colorTheme selectItemWithRepresentedObject:[adium.preferenceController preferenceForKey:KEY_LIST_THEME_NAME
																							   group:PREF_GROUP_APPEARANCE]];		
}

/*!
 * @brief Create a new layout
 */
- (IBAction)createListLayout:(id)sender
{
	NSString *layout = [adium.preferenceController preferenceForKey:KEY_LIST_LAYOUT_NAME group:PREF_GROUP_APPEARANCE];
	
	ESPresetNameSheetController *presetNameSheetController = [[ESPresetNameSheetController alloc] initWithDefaultName:[[layout stringByAppendingString:@" "] stringByAppendingString:AILocalizedString(@"(Copy)",nil)]
																									  explanatoryText:AILocalizedString(@"Enter a unique name for this new layout.",nil)
																									  notifyingTarget:self
																											 userInfo:@"layout"];
	
	[presetNameSheetController showOnWindow:[self paneWindow]];
}

/*!
 * @brief Open the layout a step below this page
 */
- (IBAction)customizeListLayout:(id)sender
{
	[self openAppearancePageWithScope:AIContactListAppearanceScopeLayout];
}

/*!
 * @brief Slide in the settings for one of the two saved sets
 *
 * A step below this page rather than a window in front of it. There is nothing to
 * confirm and nothing to cancel: every control there writes its preference at
 * once and the real contact list redraws, which is the only preview worth having.
 * Going back writes the set, and only if something was actually touched.
 */
- (void)openAppearancePageWithScope:(AIContactListAppearanceScope)scope
{
	if (!navigationController || [navigationController isTransitioning]) return;

	detailPage = [[AIContactListAppearancePage alloc] initWithScope:scope];
	[navigationController pushViewController:detailPage animated:YES];
}

/*!
 * @brief Write the changed layout back into the set it belongs to
 */
- (void)saveListLayoutNamed:(NSString *)name
{
	if ([plugin createSetFromPreferenceGroup:PREF_GROUP_LIST_LAYOUT
									withName:name
								   extension:LIST_LAYOUT_EXTENSION
									inFolder:LIST_LAYOUT_FOLDER]) {
		[adium.preferenceController setPreference:name
										   forKey:KEY_LIST_LAYOUT_NAME
											group:PREF_GROUP_APPEARANCE];
	}
}

/*!
 * @brief Manage available layouts
 */
- (void)manageListLayouts:(id)sender
{
	_listLayouts = [plugin availableLayoutSets];
	ESPresetManagementController *presetManagementController = [[ESPresetManagementController alloc] initWithPresets:_listLayouts
																										  namedByKey:@"name"
																										withDelegate:self];
	[presetManagementController showOnWindow:[self paneWindow]];

	[popUp_listLayout selectItemWithRepresentedObject:[adium.preferenceController preferenceForKey:KEY_LIST_LAYOUT_NAME
																							   group:PREF_GROUP_APPEARANCE]];		
}

/*!
 * @brief Validate a layout or theme name to ensure it is unique
 */
- (BOOL)presetNameSheetController:(ESPresetNameSheetController *)controller
			  shouldAcceptNewName:(NSString *)newName
						 userInfo:(id)userInfo
{
	NSEnumerator	*enumerator;
	NSDictionary	*presetDict;

	//Scan the correct presets to ensure this name doesn't already exist
	if ([userInfo isEqualToString:@"theme"]) {
		enumerator = [[plugin availableThemeSets] objectEnumerator];
	} else {
		enumerator = [[plugin availableLayoutSets] objectEnumerator];
	}
	
	while ((presetDict = [enumerator nextObject])) {
		if ([newName isEqualToString:[presetDict objectForKey:@"name"]]) return NO;
	}
	
	return YES;
}

/*!
 * @brief Create a new theme with the user supplied name, activate and edit it
 */
- (void)presetNameSheetControllerDidEnd:(ESPresetNameSheetController *)controller 
							 returnCode:(ESPresetNameSheetReturnCode)returnCode
								newName:(NSString *)newName
							   userInfo:(id)userInfo
{
	switch (returnCode) {
		case ESPresetNameSheetOkayReturn:
			//User has created a new theme/layout	: show the editor
			if ([userInfo isEqualToString:@"theme"]) {
				[self performSelector:@selector(_editListThemeWithName:) withObject:newName afterDelay:0];
			} else {
				[self performSelector:@selector(_editListLayoutWithName:) withObject:newName afterDelay:0];
			}
		break;
			
		case ESPresetNameSheetCancelReturn:
			//User has canceled the operation	: revert back to the current theme 
			if ([userInfo isEqualToString:@"theme"]) {
				[popUp_colorTheme selectItemWithTitle:[adium.preferenceController preferenceForKey:KEY_LIST_THEME_NAME group:PREF_GROUP_APPEARANCE]];
			} else {
				[popUp_listLayout selectItemWithTitle:[adium.preferenceController preferenceForKey:KEY_LIST_LAYOUT_NAME group:PREF_GROUP_APPEARANCE]];
			}			
		break;	
	}
}
- (void)_editListThemeWithName:(NSString *)name{
	[self openAppearancePageWithScope:AIContactListAppearanceScopeTheme];
}
- (void)_editListLayoutWithName:(NSString *)name{
	[self openAppearancePageWithScope:AIContactListAppearanceScopeLayout];
}

/*!
 * 
 */
- (NSArray *)renamePreset:(NSDictionary *)preset toName:(NSString *)newName inPresets:(NSArray *)presets renamedPreset:(id *)renamedPreset
{
	NSArray		*newPresets;
	
	if (presets == _listLayouts) {
		[plugin renameSetWithName:[preset objectForKey:@"name"]
						extension:LIST_LAYOUT_EXTENSION
						 inFolder:LIST_LAYOUT_FOLDER
						   toName:newName];		
		_listLayouts = [plugin availableLayoutSets];
		newPresets = _listLayouts;
		
	} else if (presets == _listThemes) {
		[plugin renameSetWithName:[preset objectForKey:@"name"]
						extension:LIST_THEME_EXTENSION
						 inFolder:LIST_THEME_FOLDER
						   toName:newName];		
		_listThemes = [plugin availableThemeSets];
		newPresets = _listThemes;
		
	} else {
		newPresets = nil;
	}
	
	//Return the new duplicate by reference for the preset controller
	if (renamedPreset) {
		NSDictionary	*aPreset;
		
		for (aPreset in newPresets) {
			if ([newName isEqualToString:[aPreset objectForKey:@"name"]]) {
				*renamedPreset = aPreset;
				break;
			}
		}
	}
	
	return newPresets;
}

/*!
 * 
 */
- (NSArray *)duplicatePreset:(NSDictionary *)preset inPresets:(NSArray *)presets createdDuplicate:(id *)duplicatePreset
{
	NSString	*newName = [NSString stringWithFormat:@"%@ (%@)", [preset objectForKey:@"name"], AILocalizedString(@"Copy",nil)];
	NSArray		*newPresets = nil;
	
	if (presets == _listLayouts) {
		[plugin duplicateSetWithName:[preset objectForKey:@"name"]
						   extension:LIST_LAYOUT_EXTENSION
							inFolder:LIST_LAYOUT_FOLDER
							 newName:newName];		
		_listLayouts = [plugin availableLayoutSets];
		newPresets = _listLayouts;
		
	} else if (presets == _listThemes) {
		[plugin duplicateSetWithName:[preset objectForKey:@"name"]
						   extension:LIST_THEME_EXTENSION
							inFolder:LIST_THEME_FOLDER
							 newName:newName];
		_listThemes = [plugin availableThemeSets];
		newPresets = _listThemes;
	}
	
	//Return the new duplicate by reference for the preset controller
	if (duplicatePreset) {
		NSDictionary	*aPreset;
		
		for (aPreset in newPresets) {
			if ([newName isEqualToString:[aPreset objectForKey:@"name"]]) {
				*duplicatePreset = aPreset;
				break;
			}
		}
	}

	return newPresets;
}

/*!
 * 
 */
- (NSArray *)deletePreset:(NSDictionary *)preset inPresets:(NSArray *)presets
{
	if (presets == _listLayouts) {
		[plugin deleteSetWithName:[preset objectForKey:@"name"]
						extension:LIST_LAYOUT_EXTENSION
						 inFolder:LIST_LAYOUT_FOLDER];		
		_listLayouts = [plugin availableLayoutSets];
		
		return _listLayouts;
		
	} else if (presets == _listThemes) {
		[plugin deleteSetWithName:[preset objectForKey:@"name"]
						extension:LIST_THEME_EXTENSION
						 inFolder:LIST_THEME_FOLDER];		
		_listThemes = [plugin availableThemeSets];
		
		return _listThemes;
		
	} else {
		return nil;
	}
}

/*!
 *
 */
- (NSMenu *)_listLayoutMenu
{
	NSMenu			*menu = [[NSMenu alloc] init];
	NSEnumerator	*enumerator = [[plugin availableLayoutSets] objectEnumerator];
	NSDictionary	*set;
	NSMenuItem		*menuItem;
	NSString		*name;
	
	//Available Layouts
	while ((set = [enumerator nextObject])) {
		name = [set objectForKey:@"name"];
		menuItem = [[NSMenuItem alloc] initWithTitle:name
																		 target:nil
																		 action:nil
																  keyEquivalent:@""];
		[menuItem setRepresentedObject:name];
		[menu addItem:menuItem];
	}

	//Divider
	[menu addItem:[NSMenuItem separatorItem]];

	//Preset management
	menuItem = [[NSMenuItem alloc] initWithTitle:[AILocalizedString(@"Add New Layout",nil) stringByAppendingEllipsis]
																	 target:self
																	 action:@selector(createListLayout:)
															  keyEquivalent:@""];
	[menu addItem:menuItem];

	menuItem = [[NSMenuItem alloc] initWithTitle:[AILocalizedString(@"Edit Layouts",nil) stringByAppendingEllipsis]
																	 target:self
																	 action:@selector(manageListLayouts:)
															  keyEquivalent:@""];
	[menu addItem:menuItem];

	return menu;
}

/*!
 *
 */
- (NSMenu *)_colorThemeMenu
{
	NSMenu			*menu = [[NSMenu alloc] init];
	NSEnumerator	*enumerator = [[plugin availableThemeSets] objectEnumerator];
	NSDictionary	*set;
	NSMenuItem		*menuItem;
	NSString		*name;
	
	//Available themes
	while ((set = [enumerator nextObject])) {
		name = [set objectForKey:@"name"];
		menuItem = [[NSMenuItem alloc] initWithTitle:name
																		 target:nil
																		 action:nil
																  keyEquivalent:@""];
		[menuItem setRepresentedObject:name];
		[menu addItem:menuItem];
	}

	//Divider
	[menu addItem:[NSMenuItem separatorItem]];

	//Preset management
	menuItem = [[NSMenuItem alloc] initWithTitle:[AILocalizedString(@"Add New Theme",nil) stringByAppendingEllipsis]
																	 target:self
																	 action:@selector(createListTheme:)
															  keyEquivalent:@""];
	[menu addItem:menuItem];

	menuItem = [[NSMenuItem alloc] initWithTitle:[AILocalizedString(@"Edit Themes",nil) stringByAppendingEllipsis]
																	 target:self
																	 action:@selector(manageListThemes:)
															  keyEquivalent:@""];
	[menu addItem:menuItem];

	return menu;
}


//Dock icons -----------------------------------------------------------------------------------------------------------


/*!
 * @brief The window our sheets belong on, or nil once the pane has closed
 *
 * Deliberately not [[self view] window]: -view builds the whole pane when it
 * finds none, so a stray call after -closeView would raise a second form, with a
 * second set of preference observers, that nothing ever closes again.
 */
- (NSWindow *)paneWindow
{
	return [rootForm window];
}

/*!
 * @brief A menu grew or shrank, so its button needs a different amount of room
 */
- (void)menusChanged
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(layOutChangedMenus) object:nil];
	[self performSelector:@selector(layOutChangedMenus) withObject:nil afterDelay:0.0];
}

- (void)layOutChangedMenus
{
	[rootForm noteContentSizeChanged];
}

/*!
 * @brief Retitle the row of the horizontal width slider
 */
- (void)updateHorizontalWidthLabel:(NSString *)label
{
	[rootForm setLabel:AIRowLabel(label) forRowWithControl:slider_horizontalWidth];
}

- (void)updateSliderValues
{
	[textField_windowOpacity setStringValue:[NSString stringWithFormat:@"%ld%%", (NSInteger)[slider_windowOpacity doubleValue]]];
	[textField_horizontalWidthIndicator setStringValue:[NSString stringWithFormat:@"%ldpx", [slider_horizontalWidth integerValue]]];
}

/*!
 * @brief A colour set or a layout was installed or removed; rebuild its menu
 */
- (void)xtrasChanged:(NSNotification *)notification
{
	NSString *filenameExtension = [notification object];
	UTType *type = (filenameExtension ?
					[UTType typeWithTag:filenameExtension
							   tagClass:UTTagClassFilenameExtension
					   conformingToType:nil] :
					nil);

	//Is this that type, not is it a kind of it. No extension at all means everything changed.
	BOOL (^changed)(NSString *) = ^BOOL(NSString *identifier) {
		return (!type || [[type identifier] isEqualToString:identifier]);
	};

	if (changed(@"com.adiumx.contactlisttheme")) {
		[popUp_colorTheme setMenu:[self _colorThemeMenu]];
		[popUp_colorTheme selectItemWithRepresentedObject:[adium.preferenceController preferenceForKey:KEY_LIST_THEME_NAME
																								group:PREF_GROUP_APPEARANCE]];
	}

	if (changed(@"com.adiumx.contactlistlayout")) {
		[popUp_listLayout setMenu:[self _listLayoutMenu]];
		[popUp_listLayout selectItemWithRepresentedObject:[adium.preferenceController preferenceForKey:KEY_LIST_LAYOUT_NAME
																								group:PREF_GROUP_APPEARANCE]];
	}

	[self menusChanged];
}

//What this page does when one of its own pages is open --------------------------------------------------------------
#pragma mark Navigation

/*!
 * @brief Write the open page's set, if anything on it was touched
 *
 * Only when it was: opening a set that ships with the program and leaving it
 * again would otherwise turn it into a copy of itself in the user's own folder.
 */
- (void)commitOpenAppearancePage
{
	if (!detailPage || ![detailPage hasChanges]) return;

	//A field the user is still in writes its value when it is left
	[[view window] makeFirstResponder:nil];

	if ([detailPage scope] == AIContactListAppearanceScopeTheme) {
		[self saveListThemeNamed:[adium.preferenceController preferenceForKey:KEY_LIST_THEME_NAME
																	   group:PREF_GROUP_APPEARANCE]];
	} else {
		[self saveListLayoutNamed:[adium.preferenceController preferenceForKey:KEY_LIST_LAYOUT_NAME
																		group:PREF_GROUP_APPEARANCE]];
	}
}

- (void)settingsNavigationControllerDidChangeStack:(AISettingsNavigationController *)controller
{
	if (![controller canGoBack] && detailPage) {
		[detailPage tearDown];
		detailPage = nil;
	}

	/* Through the ivar, never through -view: this can be reached while the pane
	 * is being built or after it has been closed, and -view builds a whole new
	 * pane when it finds none. */
	id windowController = [[view window] windowController];
	if ([windowController respondsToSelector:@selector(paneNavigationChanged)])
		[windowController performSelector:@selector(paneNavigationChanged)];
}

- (BOOL)preferencePaneCanNavigateBack
{
	return [navigationController canGoBack];
}

- (void)preferencePaneNavigateBack
{
	[self commitOpenAppearancePage];
	[navigationController popViewControllerAnimated:YES];
}

/*!
 * @brief What the window calls itself while a page is open: the set being written
 */
- (NSString *)preferencePaneNavigationTitle
{
	if (!detailPage) return nil;

	return [adium.preferenceController preferenceForKey:([detailPage scope] == AIContactListAppearanceScopeTheme ?
														 KEY_LIST_THEME_NAME : KEY_LIST_LAYOUT_NAME)
												  group:PREF_GROUP_APPEARANCE];
}

@end
