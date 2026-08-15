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

/*!
 * @class AIConfirmationsAdvancedPreferences
 * @brief The "Confirmations" pane of the Advanced preferences.
 *
 * Built in code as an AISettingsFormView instead of loaded from a nib: the nib's
 * two blocks of indented controls become cards of equally ranked rows, with the
 * conditions of the quit confirmation in a card of their own instead of indented
 * under the radio button that governs them. The controls keep the preference
 * keys, the radio tags and the enabling rules they had; only their shape changed
 * (checkbox plus title to row plus NSSwitch, NSMatrix to a radio group of plain
 * NSButtons).
 */
@interface AIConfirmationsAdvancedPreferences : AIAdvancedPreferencePane {
	// Quit confirmation
	NSSwitch		*checkBox_quitConfirmAlways;

	NSSwitch		*checkBox_quitConfirmFT;
	NSSwitch		*checkBox_quitConfirmUnread;
	NSSwitch		*checkBox_quitConfirmOpenChats;

	// Message window close confirmation
	NSSwitch		*checkBox_confirmBeforeClosing;
	NSButton		*radio_closeConfirmAlways;		//tag AIMessageCloseAlways
	NSButton		*radio_closeConfirmUnread;		//tag AIMessageCloseUnread
}

- (IBAction)changePreference:(id)sender;

@end
