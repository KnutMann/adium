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

#import <Adium/AIContactInfoPane.h>

@class AIListObject;

/*!
 * @class AIAddressBookInspectorPane
 * @brief Which address book card belongs to this contact, and nothing else
 *
 * There are three states, not two, because a card reaches a contact by two different routes. Adium
 * looks one up by itself from a chat handle, a phone number or an email address, and somebody can
 * also pick one by hand, which is remembered. So a contact has no card, a card that was found, or a
 * card that was chosen.
 *
 * That is why there is no on and off switch here. What can be done depends on which of the three it
 * is, and the pane shows the state rather than asking anybody to deduce it from a control: a chosen
 * card can be let go, a found one can only be overruled by choosing another.
 */
@interface AIAddressBookInspectorPane : AIContactInfoPane <NSTableViewDataSource, NSTableViewDelegate> {
	AIListObject	*displayedObject;

	NSArray			*people;			//Every card, sorted by name
	NSArray			*shown;				//Those of them the filter lets through

	NSView			*inspectorContentView;

	//Shown while a card is attached
	NSView			*summaryView;
	NSImageView		*cardImage;
	NSTextField		*cardName;
	NSTextField		*cardOrigin;

	//Shown while none is, and while choosing another
	NSView			*chooserView;
	NSSearchField	*filterField;
	NSTableView		*table;

	NSButton		*actionButton;

	BOOL			 choosing;			//Overruling a card that is already attached
}

@end
