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

#import "AIConfirmationsAdvancedPreferences.h"
#import "AIPreferenceWindowController.h"

#import <Adium/AIPreferenceControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AISettingsFormView.h>

#import <AIUtilities/AIImageAdditions.h>

#define CONFIRMATIONS_PANE_INITIAL_WIDTH	540.0

@interface AIConfirmationsAdvancedPreferences ()
- (AISettingsFormView *)buildSettingsForm;
- (NSArray *)quitConfirmTypeButtons;
- (NSArray *)closeConfirmTypeButtons;
- (void)selectTag:(NSInteger)tag inRadioGroup:(NSArray *)buttons;
- (NSInteger)selectedTagInRadioGroup:(NSArray *)buttons;
- (void)setEnabled:(BOOL)enabled forRadioGroup:(NSArray *)buttons;
@end

@implementation AIConfirmationsAdvancedPreferences
#pragma mark Preference pane settings
- (AIPreferenceCategory)category
{
    return AIPref_Advanced;
}
- (NSString *)label{
    return AILocalizedString(@"Confirmations",nil);
}
- (NSImage *)image{
	return [NSImage imageNamed:@"pref-confirmations" forClass:[AIPreferenceWindowController class]];
}

/* No -nibName: the pane builds its own view below, so AIModularPane never loads
 * a nib for us. AIConfirmationsAdvancedPreferences.xib is dead — and it must
 * stay unloaded: it still wires outlets this class no longer has
 * (matrix_quitConfirmType, matrix_closeConfirmType, label_*), so loading it
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

		view = [form retain];

		[self viewDidLoad];
		[self localizePane];

		[form layoutForWidth:NSWidth([form frame])];

		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

/*!
 * @brief Release the form.
 *
 * -closeView releases the view and is idempotent; without it a deallocated pane
 * would leave the form's rows — and the KVO observations they register on their
 * controls — alive. Same pattern as the other panes built on AISettingsFormView.
 */
- (void)dealloc
{
	[self closeView];
	[super dealloc];
}

/*!
 * @brief Create the controls and stack them into cards.
 *
 * Three cards: one per confirmation, plus one holding the conditions the quit
 * confirmation can be narrowed down to. The nib hung both the choice of when and
 * those conditions off their checkbox as indented blocks; the indentation is
 * gone and a card boundary carries the grouping instead, so the conditions no
 * longer read as further quit settings of equal rank. The dimming rules of the
 * nib are unchanged (see -configureControlDimming).
 *
 * The radio groups carry no label of their own: it would have to repeat what the
 * switch above already says, and the two groups would end up with the same one.
 */
- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[[AISettingsFormView alloc] initWithWidth:CONFIRMATIONS_PANE_INITIAL_WIDTH] autorelease];

	//Window close confirmation
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

	//Quit confirmation
	[form addSectionHeader:AILocalizedString(@"Quit Confirmation", "Preference")];

	checkBox_confirmBeforeQuitting = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Confirm before quitting Adium", "Quit Confirmation preference")
				  control:checkBox_confirmBeforeQuitting];

	radio_quitConfirmAlways = [AISettingsFormView radioButtonWithTitle:AILocalizedString(@"Always", "Confirmation preference")
																target:self
																action:@selector(changePreference:)];
	[radio_quitConfirmAlways setTag:AIQuitConfirmAlways];

	/* The nib's title, minus the ellipsis it used to point at the indented
	 * checkboxes: the same string, so its translations in every localization keep
	 * applying. What it points at is now the card that follows immediately below.
	 */
	radio_quitConfirmSelective = [AISettingsFormView radioButtonWithTitle:AILocalizedString(@"Only when", "Quit Confirmation preference")
																   target:self
																   action:@selector(changePreference:)];
	[radio_quitConfirmSelective setTag:AIQuitConfirmSelective];

	[form addRadioGroupWithLabel:nil buttons:[self quitConfirmTypeButtons]];

	/* The conditions "Only when" narrows the confirmation down to. Their own,
	 * headerless card: they belong to the radio above, not to the quit switch, and
	 * a card boundary is the only grouping System Settings has for that.
	 */
	[form endCard];

	checkBox_quitConfirmFT = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"File transfers are in progress", "Quit Confirmation preference")
				  control:checkBox_quitConfirmFT];

	checkBox_quitConfirmUnread = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"There are unread messages", "Quit Confirmation preference")
				  control:checkBox_quitConfirmUnread];

	checkBox_quitConfirmOpenChats = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"There are open chat windows", "Quit Confirmation preference")
				  control:checkBox_quitConfirmOpenChats];

	return form;
}

/*!
 * @brief The view loaded: fill the controls from the stored preferences
 */
- (void)viewDidLoad
{
	NSDictionary *confirmationDict = [adium.preferenceController preferencesForGroup:PREF_GROUP_CONFIRMATIONS];

	[checkBox_confirmBeforeQuitting setState:([[confirmationDict objectForKey:KEY_CONFIRM_QUIT] boolValue] ?
											  NSControlStateValueOn : NSControlStateValueOff)];
	[self selectTag:[[confirmationDict objectForKey:KEY_CONFIRM_QUIT_TYPE] integerValue]
	   inRadioGroup:[self quitConfirmTypeButtons]];

	/* The three keys suppress a confirmation, so the switch is the inverse of the
	 * stored value — exactly as the checkboxes were.
	 */
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

	[self configureControlDimming];

	[super viewDidLoad];
}

- (void)viewWillClose
{
	checkBox_confirmBeforeQuitting = nil;
	radio_quitConfirmAlways = nil;
	radio_quitConfirmSelective = nil;
	checkBox_quitConfirmFT = nil;
	checkBox_quitConfirmUnread = nil;
	checkBox_quitConfirmOpenChats = nil;
	checkBox_confirmBeforeClosing = nil;
	radio_closeConfirmAlways = nil;
	radio_closeConfirmUnread = nil;

	[super viewWillClose];
}

#pragma mark Radio groups

/*!
 * @brief The buttons of the "when to confirm quitting" choice, in display order
 */
- (NSArray *)quitConfirmTypeButtons
{
	return [NSArray arrayWithObjects:radio_quitConfirmAlways, radio_quitConfirmSelective, nil];
}

/*!
 * @brief The buttons of the "when to confirm closing" choice, in display order
 */
- (NSArray *)closeConfirmTypeButtons
{
	return [NSArray arrayWithObjects:radio_closeConfirmAlways, radio_closeConfirmUnread, nil];
}

/*!
 * @brief Select the button carrying @a tag, as -[NSMatrix selectCellWithTag:] did.
 *
 * A tag no button carries — a stored value outside the enum, say — falls back to
 * the first button. The matrix did not allow an empty selection (and the nib
 * pre-selected a cell), so a group must never end up with nothing selected:
 * -selectedTagInRadioGroup: would report -1 and -configureControlDimming would
 * grey out controls the user has no selected option to re-enable them with.
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

/*!
 * @brief The tag of the selected button, or -1 while the view is gone
 */
- (NSInteger)selectedTagInRadioGroup:(NSArray *)buttons
{
	for (NSButton *button in buttons) {
		if ([button state] == NSControlStateValueOn) return [button tag];
	}

	return -1;
}

- (void)setEnabled:(BOOL)enabled forRadioGroup:(NSArray *)buttons
{
	for (NSButton *button in buttons) {
		[button setEnabled:enabled];
	}
}

#pragma mark Changing preferences

- (IBAction)changePreference:(id)sender
{
	if (sender == checkBox_confirmBeforeQuitting) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:[sender state]]
										   forKey:KEY_CONFIRM_QUIT
											group:PREF_GROUP_CONFIRMATIONS];

		[self configureControlDimming];
	}

	if (sender == checkBox_quitConfirmFT) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:![sender state]]
										   forKey:KEY_CONFIRM_QUIT_FT
											group:PREF_GROUP_CONFIRMATIONS];
	}

	if (sender == checkBox_quitConfirmUnread) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:![sender state]]
										   forKey:KEY_CONFIRM_QUIT_UNREAD
											group:PREF_GROUP_CONFIRMATIONS];
	}

	if (sender == checkBox_quitConfirmOpenChats) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:![sender state]]
										   forKey:KEY_CONFIRM_QUIT_OPEN
											group:PREF_GROUP_CONFIRMATIONS];
	}

	if (sender == radio_quitConfirmAlways || sender == radio_quitConfirmSelective) {
		[adium.preferenceController setPreference:[NSNumber numberWithInteger:[(NSButton *)sender tag]]
								   forKey:KEY_CONFIRM_QUIT_TYPE
									group:PREF_GROUP_CONFIRMATIONS];

		[self configureControlDimming];
	}

	if (sender == checkBox_confirmBeforeClosing) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:[sender state]]
										   forKey:KEY_CONFIRM_MSG_CLOSE
											group:PREF_GROUP_CONFIRMATIONS];

		[self configureControlDimming];
	}

	if (sender == radio_closeConfirmAlways || sender == radio_closeConfirmUnread) {
		[adium.preferenceController setPreference:[NSNumber numberWithInteger:[(NSButton *)sender tag]]
								   forKey:KEY_CONFIRM_MSG_CLOSE_TYPE
									group:PREF_GROUP_CONFIRMATIONS];
	}

	[self viewDidLoad];
}

- (void)configureControlDimming
{
	BOOL		confirmQuitEnabled			= (checkBox_confirmBeforeQuitting.state == NSControlStateValueOn);
	BOOL		enableSpecificConfirmations = (confirmQuitEnabled &&
											   [self selectedTagInRadioGroup:[self quitConfirmTypeButtons]] == AIQuitConfirmSelective);

	[self setEnabled:confirmQuitEnabled forRadioGroup:[self quitConfirmTypeButtons]];
	[checkBox_quitConfirmFT	setEnabled:enableSpecificConfirmations];
	[checkBox_quitConfirmUnread	setEnabled:enableSpecificConfirmations];
	[checkBox_quitConfirmOpenChats setEnabled:enableSpecificConfirmations];

	BOOL		confirmCloseEnabled			= (checkBox_confirmBeforeClosing.state == NSControlStateValueOn);
	[self setEnabled:confirmCloseEnabled forRadioGroup:[self closeConfirmTypeButtons]];
}

@end
