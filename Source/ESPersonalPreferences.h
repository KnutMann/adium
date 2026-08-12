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

#import <Adium/AIPreferencePane.h>

@class AIAutoScrollView, AIImageViewWithImagePicker;

/*!
 * @class ESPersonalPreferences
 * @brief The Personal pane, built as an AISettingsFormView
 *
 * Three cards: the name sent to contacts, the profile shown when they ask for
 * information, and the icon standing for the user. Every control below is
 * created by -buildSettingsForm and owned by that form (which the inherited
 * 'view' ivar retains), so the references here are non-owning and are cleared
 * again in -viewWillClose. There is no nib.
 *
 * The pane is its own text delegate on purpose: the name field and the profile
 * view have no action to fall back on, and the preferences window only calls
 * -closeView when it closes and never when the sidebar changes pane, so this is
 * where what was typed is picked up and stored (see SAVE_DELAY in the
 * implementation).
 */
@interface ESPersonalPreferences : AIPreferencePane <NSTextFieldDelegate, NSTextViewDelegate> {
	NSTextField					*textField_displayName;
	//A keystroke was gathered but not stored yet; see SAVE_DELAY in the implementation
	BOOL						 displayNameSavePending;
	BOOL						 profileSavePending;

	/* The profile editor. The document view really is an AIMessageEntryTextView;
	 * it is held as a plain NSTextView because that is all this pane asks of it
	 * once -buildSettingsForm has configured it. */
	AIAutoScrollView			*scrollView_profile;
	NSTextView					*textView_profile;
	//Set while the stored profile is put into the view, so that filling it writes nothing back
	BOOL						 configuringProfile;

	//The two cells matrix_userIcon used to hold, in display order
	NSPopUpButton				*popUp_iconChoice;	//"Use no icon" / "Use this icon", tags 0 and 1

	NSButton					*button_chooseIcon;
	AIImageViewWithImagePicker	*imageView_userIcon;
}

@end
