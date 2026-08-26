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

#import <Adium/AIWindowController.h>

@class AIService, AIAddressBookPerson;

/*!
 * @brief Pick an address book card for a contact being created
 *
 * A filterable list of every card, as a sheet. The old people-picker nib and its
 * side entrance for creating a new card are gone: cards are made in the Contacts
 * app, this window only finds one.
 */
@interface OWABSearchWindowController : AIWindowController <NSWindowDelegate, NSTableViewDelegate, NSTableViewDataSource> {
	NSSearchField		*filterField;
	NSTableView			*table;
	NSButton			*selectButton;
	NSButton			*cancelButton;

	//Both point back out of the sheet at things which outlive it, so neither is owned here
	__unsafe_unretained NSWindow	*carryingWindow;
	__unsafe_unretained id			delegate;

	AIAddressBookPerson	*person;
	AIService			*service;

	NSArray				*people;	//Every card, sorted by name
	NSArray				*shown;		//What the filter leaves visible
}

+ (id)promptForNewPersonSearchOnWindow:(NSWindow *)parentWindow initialService:(AIService *)inService;
- (IBAction)select:(id)sender;
- (IBAction)cancel:(id)sender;

- (id)delegate;
- (void)setDelegate:(id)newDelegate;

- (AIAddressBookPerson *)selectedPerson;
- (NSString *)selectedScreenName;
- (NSString *)selectedName;
- (NSString *)selectedAlias;
- (AIService *)selectedService;

@end

//Delegate Methods
@interface NSObject (OWABSearchWindowControllerDelegate)
- (void)absearchWindowControllerDidSelectPerson:(OWABSearchWindowController *)controller;
@end
