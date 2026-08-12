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

#import <Adium/AIAdvancedPreferencePane.h>

#define PREF_GROUP_STATUS_MENU_ITEM     @"Status Menu Item"
#define KEY_STATUS_MENU_ITEM_ENABLED    @"Status Menu Item Enabled"
#define	KEY_STATUS_MENU_ITEM_COUNT		@"Status Menu Item Unread Count"
#define	KEY_STATUS_MENU_ITEM_BADGE		@"Status Menu Item Badge"
#define KEY_STATUS_MENU_ITEM_FLASH		@"Status Menu Item Flash Unviewed"

/*!
 * @class AIMessageAlertsAdvancedPreferences
 * @brief The "Message Alerts" pane of the Advanced preferences.
 *
 * Built in code as an AISettingsFormView instead of loaded from a nib. The nib's
 * three blocks — each a bold caption over a horizontal line over its checkboxes —
 * become three cards, and the two dock settings the nib indented under "When
 * there are unread messages:" become equally ranked rows introduced by that same
 * sentence as the card's opening detail line. Every preference key and every
 * title is the one the nib had; only the shape changed (checkbox plus title to
 * row plus NSSwitch).
 */
@interface AIMessageAlertsAdvancedPreferences : AIAdvancedPreferencePane {
	// Status menu item (the menu bar icon)
	NSSwitch	*checkBox_statusMenuItemFlash;
	NSSwitch	*checkBox_statusMenuItemCount;

	// Dock icon
	NSSwitch	*checkBox_animateDockIcon;
	NSSwitch	*checkBox_badgeDockIcon;

	// What both of the above count
	NSSwitch	*checkBox_unreadConversations;
	NSSwitch	*checkBox_unreadContentMention;
}

- (IBAction)changePreference:(id)sender;

@end
