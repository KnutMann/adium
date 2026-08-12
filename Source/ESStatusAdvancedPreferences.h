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

@class AISettingsFormView;

/*!
 * @class ESStatusAdvancedPreferences
 * @brief The Status pane of the Advanced preferences.
 *
 * The pane builds its view programmatically on top of AISettingsFormView (the
 * System Settings style card list); it no longer loads StatusPreferencesAdvanced.xib.
 *
 * The palette of drag sources the nib carried — seven read-only token fields in a
 * two column box, plus the line explaining that they were to be dragged — is
 * gone. The format is plain text in a plain field now, and the tokens are put in
 * at the caret from a pull down menu: one row instead of a third of the pane, and
 * a shape that works with the keyboard alone.
 *
 * The controls below are owned by the view hierarchy, exactly as the nib's
 * outlets were; the ivars are unretained references to them.
 */
@interface ESStatusAdvancedPreferences : AIAdvancedPreferencePane <NSTextFieldDelegate> {
	NSTextField		*textField_format;
	NSPopUpButton	*popUp_insertToken;

	NSMutableArray	*establishedBindings;		//NSArrays of (object, binding name), unbound when the view closes

	/* Where the caret stood when the format field last gave up editing. Choosing
	 * from the pull down can take the focus away, and the token still has to land
	 * where the user left off. */
	NSRange			 savedSelectedRange;
	BOOL			 hasSavedSelectedRange;

	BOOL			 formatChangePending;		//A coalesced format announcement is still outstanding
}

@end
