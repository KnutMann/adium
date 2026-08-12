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

/* Which of those terms are switched on, as NSNumber, index for index with the terms above. A second
 * key rather than a richer shape for the first one: "Saved Mentions" is an array of strings in
 * everybody's preferences, and anything that reads it - this pane, AIMentionEventPlugin, an older
 * build of Adium - goes on finding exactly what it always found there. Missing, short, or holding
 * something which is not a number means "on", which is what every list looked like before there
 * were switches; so there is nothing to migrate and nothing that can be lost. */
#define PREF_KEY_MENTIONS_ENABLED	@"Saved Mentions Enabled"

@class AISettingsFormView, AIPassthroughScrollView;

/*!
 * @class AIMentionAdvancedPreferences
 * @brief The terms which highlight a message, as a System Settings style list
 *
 * Two preferences, kept index for index: the array of terms under @c PREF_KEY_MENTIONS and the
 * array of switches under @c PREF_KEY_MENTIONS_ENABLED. The list is the edge to edge row of a card
 * (see -buildSettingsForm), every row is an editable text field, a warning sign, a switch and a ⊖,
 * and every keystroke is written straight to the preference controller - the pane is taken off
 * screen without -viewWillClose when the user picks another one in the sidebar, so nothing may ever
 * wait for it.
 *
 * The switch says whether a term is applied, and it answers for itself: a term of the /…/ form which
 * is not a valid regular expression switches itself off when the user is done typing it, and refuses
 * to be switched back on until it is. What "valid" means is not decided here - AIMentionEventPlugin
 * is asked, so that the switch cannot say one thing while the filter does another. A switch we threw
 * that way comes back on by itself as soon as the term is mended; one the user threw stays where
 * they left it (@c mentionSwitchedOffByPane tells the two apart).
 *
 * The nib outlets are gone with the nib: the pane no longer answers -nibName and builds its view in
 * code, so nothing here is ever connected by Interface Builder.
 */
@interface AIMentionAdvancedPreferences : AIAdvancedPreferencePane <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate> {
	AISettingsFormView		*settingsForm;		//Our view, typed; unretained (-view owns it)

	AIPassthroughScrollView	*scrollView;		//The list's container; retained (the form holds its own reference)
	NSTableView				*tableView;			//Owned by the scroll view, which is its document view's owner

	NSMutableArray			*mentionTerms;		//NSString, in display order
	NSMutableArray			*mentionEnabled;	//NSNumber, one per term, same order

	/* Which of those switches we threw ourselves rather than the user, so that a term we switched
	 * off can be switched back on the moment it is mended. NSNumber, one per term, same order.
	 * Never written to the preferences: it says nothing about how Adium behaves, only how this
	 * switch came to be off, and a note kept for as long as the pane is open is exactly as long as
	 * anybody could still be mending the term it belongs to. */
	NSMutableArray			*mentionSwitchedOffByPane;

	NSPopover				*invalidTermPopover;	//Shown only when a switch was refused by hand; retained

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
