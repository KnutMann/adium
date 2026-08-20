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

#import "AIMessageAlertsAdvancedPreferences.h"
#import "AIStatusController.h"
#import "AIDockController.h"
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIImageAdditions.h>

//Width the form starts out at; the preferences window resizes it to its column.
#define MESSAGE_ALERTS_PANE_INITIAL_WIDTH	540.0

@interface AIMessageAlertsAdvancedPreferences ()
- (AISettingsFormView *)buildSettingsForm;
@end

@implementation AIMessageAlertsAdvancedPreferences
#pragma mark Preference Pane
- (AIPreferenceCategory)category{
    return AIPref_Advanced;
}
/* Unlocalized, unlike the label: the sidebar grouping matches panes by this,
 * and a match must not depend on the user's language. */
- (NSString *)paneIdentifier{
	return @"Message Alerts";
}
- (NSString *)label{
    return AILocalizedString(@"Message Alerts",nil);
}
- (NSImage *)image{
	return [NSImage imageNamed:@"pref-messagealerts" forClass:[self class]];
}

/* No -nibName: the pane builds its own view below, so AIModularPane never loads a nib for us.
 * AIMessageAlertsAdvancedPreferences.xib, which used to hold this interface, has been deleted along with its entry
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
 * Three cards, in the order the nib drew them: what the menu bar icon does, what
 * the dock icon does, and what either of them counts. The nib built each block
 * out of a bold caption, a horizontal line and its checkboxes; a card with a
 * section header is the same thing without drawing the line by hand.
 *
 * The dock card keeps the nib's "When there are unread messages:" as its opening
 * detail line rather than as a caption over two indented checkboxes: the two
 * settings are of equal rank, and the sentence introduces the card the way
 * System Settings introduces a group. It is the nib's string verbatim, colon
 * included, so its translations keep applying.
 */
- (AISettingsFormView *)buildSettingsForm
{
	AISettingsFormView	*form = [[[AISettingsFormView alloc] initWithWidth:MESSAGE_ALERTS_PANE_INITIAL_WIDTH] autorelease];

	//The menu bar icon
	[form addSectionHeader:AILocalizedString(@"Status Menu Item", nil)];

	checkBox_statusMenuItemFlash = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Flash when there are unread messages", nil)
				  control:checkBox_statusMenuItemFlash];

	checkBox_statusMenuItemCount = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Show unread message count in the menu bar", nil)
				  control:checkBox_statusMenuItemCount];

	//The dock icon
	[form addSectionHeader:AILocalizedString(@"Dock Icon", nil)];

	/* Opens the card, so it takes the card's top padding and reads as an
	 * introduction to both rows below instead of clinging to a row above.
	 */
	[form addDetailRow:AILocalizedString(@"When there are unread messages:", nil)];

	checkBox_animateDockIcon = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Animate the dock icon", nil)
				  control:checkBox_animateDockIcon];

	checkBox_badgeDockIcon = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Display a message count badge", nil)
				  control:checkBox_badgeDockIcon];

	/* What the badge and the menu bar count. The nib's caption named both places
	 * the setting reaches, which is exactly what a section header is for; the two
	 * rows stay siblings, because neither preference has ever been conditional on
	 * the other (this pane has no -configureControlDimming, and never had one).
	 */
	[form addSectionHeader:AILocalizedString(@"Dock Icon and Status Menu Item Counts", nil)];

	checkBox_unreadConversations = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Count unread conversations instead of unread messages", nil)
				  control:checkBox_unreadConversations];

	checkBox_unreadContentMention = [AISettingsFormView switchWithTarget:self action:@selector(changePreference:)];
	[form addRowWithLabel:AILocalizedString(@"Only count number of highlights and mentions for group chats", nil)
				  control:checkBox_unreadContentMention];

	return form;
}

#pragma mark Display

/*!
 * @brief The view loaded: fill the controls from the stored preferences
 */
- (void)viewDidLoad
{
	NSDictionary *menuItemPreferences = [adium.preferenceController preferencesForGroup:PREF_GROUP_STATUS_MENU_ITEM];

	[checkBox_statusMenuItemFlash setState:([[menuItemPreferences objectForKey:KEY_STATUS_MENU_ITEM_FLASH] boolValue] ?
											NSControlStateValueOn : NSControlStateValueOff)];
	[checkBox_statusMenuItemCount setState:([[menuItemPreferences objectForKey:KEY_STATUS_MENU_ITEM_COUNT] boolValue] ?
											NSControlStateValueOn : NSControlStateValueOff)];

	NSDictionary *appearancePreferences = [adium.preferenceController preferencesForGroup:PREF_GROUP_APPEARANCE];

	[checkBox_animateDockIcon setState:([[appearancePreferences objectForKey:KEY_ANIMATE_DOCK_ICON] boolValue] ?
										NSControlStateValueOn : NSControlStateValueOff)];
	[checkBox_badgeDockIcon setState:([[appearancePreferences objectForKey:KEY_BADGE_DOCK_ICON] boolValue] ?
									  NSControlStateValueOn : NSControlStateValueOff)];

	NSDictionary *statusPreferences = [adium.preferenceController preferencesForGroup:PREF_GROUP_STATUS_PREFERENCES];

	[checkBox_unreadConversations setState:([[statusPreferences objectForKey:KEY_STATUS_CONVERSATION_COUNT] boolValue] ?
											NSControlStateValueOn : NSControlStateValueOff)];
	[checkBox_unreadContentMention setState:([[statusPreferences objectForKey:KEY_STATUS_MENTION_COUNT] boolValue] ?
											 NSControlStateValueOn : NSControlStateValueOff)];

	[self configureControlDimming];

	[super viewDidLoad];
}

/*!
 * @brief The window is closing: drop our references to the form's controls.
 *
 * The controls belong to the form, which -closeView releases; the pane only ever
 * held them as back references, so nil is all there is to do here.
 */
- (void)viewWillClose
{
	checkBox_statusMenuItemFlash = nil;
	checkBox_statusMenuItemCount = nil;
	checkBox_animateDockIcon = nil;
	checkBox_badgeDockIcon = nil;
	checkBox_unreadConversations = nil;
	checkBox_unreadContentMention = nil;

	[super viewWillClose];
}

#pragma mark Preference toggling

/*!
 * @brief A switch was flipped: write the preference straight away.
 *
 * The preference window only sends -closeView when it closes, not when the user
 * switches panes, so there is no later chance to save.
 */
- (IBAction)changePreference:(id)sender
{
	if (sender == checkBox_statusMenuItemFlash) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
										   forKey:KEY_STATUS_MENU_ITEM_FLASH
											group:PREF_GROUP_STATUS_MENU_ITEM];
	}

	if (sender == checkBox_statusMenuItemCount) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
										   forKey:KEY_STATUS_MENU_ITEM_COUNT
											group:PREF_GROUP_STATUS_MENU_ITEM];
	}

	if (sender == checkBox_animateDockIcon) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
										   forKey:KEY_ANIMATE_DOCK_ICON
											group:PREF_GROUP_APPEARANCE];
	}

	if (sender == checkBox_badgeDockIcon) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
										   forKey:KEY_BADGE_DOCK_ICON
											group:PREF_GROUP_APPEARANCE];
	}

	if (sender == checkBox_unreadConversations) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
										   forKey:KEY_STATUS_CONVERSATION_COUNT
											group:PREF_GROUP_STATUS_PREFERENCES];
	}

	if (sender == checkBox_unreadContentMention) {
		[adium.preferenceController setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
										   forKey:KEY_STATUS_MENTION_COUNT
											group:PREF_GROUP_STATUS_PREFERENCES];
	}
}

@end
