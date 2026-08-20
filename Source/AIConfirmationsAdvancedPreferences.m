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

/* No -nibName: the pane builds its own view below, so AIModularPane never loads a nib for us.
 * AIConfirmationsAdvancedPreferences.xib, which used to hold this interface, has been deleted
 * along with its entry in the target: nothing loaded it any more, and it still wired outlets this
 * class no longer has, so anything that did load it would have raised rather than fallen back.
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

	/* Four switches of equal rank, where there used to be a switch, a choice between always and
	 * only when, and three conditions hanging off the second answer. Three levels for what is one
	 * question: under which circumstances shall quitting be questioned. The first switch answers
	 * "any", the other three name their own, and what is stored underneath is unchanged, so
	 * whatever decides at quitting time never learns that the interface was rearranged.
	 */
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

	return form;
}

/*!
 * @brief The view loaded: fill the controls from the stored preferences
 */
- (void)viewDidLoad
{
	NSDictionary *confirmationDict = [adium.preferenceController preferencesForGroup:PREF_GROUP_CONFIRMATIONS];

	/* Asking always is the two stored answers together: confirm at all, and confirm regardless of
	 * what is going on. */
	BOOL always = ([[confirmationDict objectForKey:KEY_CONFIRM_QUIT] boolValue] &&
				   [[confirmationDict objectForKey:KEY_CONFIRM_QUIT_TYPE] integerValue] == AIQuitConfirmAlways);

	[checkBox_quitConfirmAlways setState:(always ? NSControlStateValueOn : NSControlStateValueOff)];

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
	checkBox_quitConfirmAlways = nil;
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

/*!
 * @brief Write the two stored answers the four switches together stand for
 *
 * Whether to ask at all is now nothing anybody sets directly: it follows from whether any of the
 * four switches wants a question. Whether to ask regardless follows from the first one alone.
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


- (IBAction)changePreference:(id)sender
{
	if (sender == checkBox_quitConfirmAlways) {
		[self writeQuitConfirmation];
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

	if (sender == checkBox_quitConfirmFT || sender == checkBox_quitConfirmUnread ||
		sender == checkBox_quitConfirmOpenChats) {
		[self writeQuitConfirmation];
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
	/* Asking in every case answers the other three as well, so they have nothing left to decide
	 * and say so by dimming. They keep their state while dimmed, and get it back the moment the
	 * first switch goes off again. */
	BOOL		enableSpecificConfirmations = (checkBox_quitConfirmAlways.state != NSControlStateValueOn);

	[checkBox_quitConfirmFT	setEnabled:enableSpecificConfirmations];
	[checkBox_quitConfirmUnread	setEnabled:enableSpecificConfirmations];
	[checkBox_quitConfirmOpenChats setEnabled:enableSpecificConfirmations];

	BOOL		confirmCloseEnabled			= (checkBox_confirmBeforeClosing.state == NSControlStateValueOn);
	[self setEnabled:confirmCloseEnabled forRadioGroup:[self closeConfirmTypeButtons]];
}

@end
