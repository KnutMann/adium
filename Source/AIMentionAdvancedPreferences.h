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

#define PREF_KEY_MENTIONS		@"Saved Mentions"

@class AISettingsFormView, AIPassthroughScrollView;

/*!
 * @class AIMentionAdvancedPreferences
 * @brief The terms which highlight a message, as a System Settings style list
 *
 * One preference: the array of terms under @c PREF_KEY_MENTIONS. The list is the edge to edge row
 * of a card (see -buildSettingsForm), every row is an editable text field plus a ⊖, and every
 * keystroke is written straight to the preference controller - the pane is taken off screen without
 * -viewWillClose when the user picks another one in the sidebar, so nothing may ever wait for it.
 *
 * The nib outlets are gone with the nib: the pane no longer answers -nibName and builds its view in
 * code, so nothing here is ever connected by Interface Builder.
 */
@interface AIMentionAdvancedPreferences : AIAdvancedPreferencePane <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate> {
	AISettingsFormView		*settingsForm;		//Our view, typed; unretained (-view owns it)

	AIPassthroughScrollView	*scrollView;		//The list's container; retained (the form holds its own reference)
	NSTableView				*tableView;			//Owned by the scroll view, which is its document view's owner

	NSMutableArray			*mentionTerms;		//NSString, in display order

	CGFloat					 cachedLayoutWidth;	//Width the rows were last laid out for
	CGFloat					 columnMargin;		//Room the table style keeps beside its column
	BOOL					 layoutScheduled;
}

/*!
 * @brief Add a term and put the cursor in it
 *
 * The action of the "+" below the card. Nothing is written yet: an empty term is never saved.
 */
- (IBAction)add:(id)sender;

@end
