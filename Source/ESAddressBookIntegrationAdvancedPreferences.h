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
 * @class ESAddressBookIntegrationAdvancedPreferences
 * @brief The "Address Book" pane of the Advanced preferences.
 *
 * Built in code as an AISettingsFormView instead of loaded from a nib. The nib's
 * boxed palette of draggable name elements became an "Insert" pull down under
 * the format card: the same elements land in the same field, only by menu
 * instead of by drag, and each inserted element keeps its menu for switching
 * between full name and initial. The controls keep the preference keys and the
 * enabling rules they had; only their shape changed (checkbox plus title to row
 * plus NSSwitch).
 */
@interface ESAddressBookIntegrationAdvancedPreferences : AIAdvancedPreferencePane <NSTokenFieldDelegate> {
	// Names
	NSSwitch		*checkBox_enableImport;
	NSSwitch		*checkBox_useFirstName;
	NSSwitch		*checkBox_useNickName;

	NSTokenField	*tokenField_format;
	NSPopUpButton	*popUp_insertNameElement;

	// Images
	NSSwitch		*checkBox_useABImages;
	NSSwitch		*checkBox_preferABImages;

	// Contacts
	NSSwitch		*checkBox_metaContacts;

	/* Never created, and it was not in the nib either: the note sync setting lost
	 * its checkbox long ago and nothing reads KEY_AB_NOTE_SYNC anymore. The write
	 * path in -changePreference: is kept so the setting can return without being
	 * re-plumbed.
	 */
	NSSwitch		*checkBox_enableNoteSync;
}

- (IBAction)changePreference:(id)sender;

@end
