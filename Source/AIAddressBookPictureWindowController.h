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

#import <Cocoa/Cocoa.h>

/*!
 * @class AIAddressBookPictureWindowController
 * @brief Hands a contact's picture over to their address book card
 *
 * Adium reads the address book and never writes to it, with this one exception, which is why it is
 * a window somebody opens and a button somebody presses rather than anything that happens by
 * itself. Nothing here runs unless it is asked to.
 *
 * Listed are the cards that Adium already knows belong to somebody in the contact list, whether
 * because a card was picked by hand or because the account name matched a number, an address or a
 * chat handle. That is the same question the rest of Adium asks, so the list is exactly what it
 * believes about the two sides.
 */
@interface AIAddressBookPictureWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate> {
	NSMutableArray	*entries;			//One per card with a contact behind it
	NSArray			*shown;				//Those of them the filter lets through

	NSSearchField	*filterField;
	NSTableView		*table;
	NSImageView		*adiumImage;
	NSImageView		*cardImage;
	NSTextField		*adiumCaption;
	NSTextField		*cardCaption;
	NSButton		*previousButton;
	NSButton		*nextButton;
	NSButton		*transferButton;
}

+ (void)showWindow;

@end
