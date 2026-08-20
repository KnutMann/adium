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

#import "OWABSearchWindowController.h"
#import <Adium/AIAddressBookController.h>
#import <Adium/AIService.h>

#define SEARCH_WINDOW_WIDTH		380.0
#define SEARCH_WINDOW_HEIGHT	440.0
#define MARGIN					16.0
#define BUTTON_AREA_HEIGHT		48.0

@interface OWABSearchWindowController ()
- (id)initWithParentWindow:(NSWindow *)parentWindow initialService:(AIService *)inService;
- (void)buildWindow;
- (void)applyFilter;
- (NSString *)nameForPerson:(AIAddressBookPerson *)aPerson;
@end

@implementation OWABSearchWindowController

+ (id)promptForNewPersonSearchOnWindow:(NSWindow *)parentWindow initialService:(AIService *)inService
{
	OWABSearchWindowController *controller = [[[self alloc] initWithParentWindow:parentWindow
																  initialService:inService] autorelease];

	//Alive for as long as the sheet runs; the completion below lets go again
	[controller retain];

	[parentWindow beginSheet:[controller window] completionHandler:^(NSModalResponse returnCode) {
		if (returnCode == NSModalResponseOK && controller->delegate)
			[controller->delegate absearchWindowControllerDidSelectPerson:controller];

		[controller autorelease];
	}];

	return controller;
}

- (id)initWithParentWindow:(NSWindow *)parentWindow initialService:(AIService *)inService
{
	if ((self = [super initWithWindowNibName:@""])) {
		carryingWindow = parentWindow;
		service = [inService retain];

		people = [[[AIAddressBookController allPeople] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
			return [[self nameForPerson:a] localizedCaseInsensitiveCompare:[self nameForPerson:b]];
		}] retain];
		shown = [people retain];

		[self buildWindow];
	}
	return self;
}

- (void)dealloc
{
	[table setDelegate:nil];
	[table setDataSource:nil];

	[service release];
	[person release];
	[people release];
	[shown release];

	[super dealloc];
}

//The designated initializer of NSWindowController loads nothing when the window is set by hand
- (void)loadWindow
{
	//Handled in buildWindow
}

/*!
 * @brief The name a card goes by in the list
 */
- (NSString *)nameForPerson:(AIAddressBookPerson *)aPerson
{
	NSMutableArray	*parts = [NSMutableArray array];

	if ([aPerson.firstName length]) [parts addObject:aPerson.firstName];
	if ([aPerson.lastName length]) [parts addObject:aPerson.lastName];

	if ([parts count])
		return [parts componentsJoinedByString:@" "];

	if ([aPerson.organization length])
		return aPerson.organization;

	return AILocalizedString(@"Unnamed card", "Name shown for an address book card that has no name on it");
}

- (void)buildWindow
{
	NSWindow *panel = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, SEARCH_WINDOW_WIDTH, SEARCH_WINDOW_HEIGHT)
												   styleMask:NSWindowStyleMaskTitled
													 backing:NSBackingStoreBuffered
													   defer:NO] autorelease];
	[panel setTitle:AILocalizedString(@"Choose Address Book Card", nil)];
	NSView *content = [panel contentView];

	CGFloat innerWidth = SEARCH_WINDOW_WIDTH - 2 * MARGIN;

	filterField = [[[NSSearchField alloc] initWithFrame:NSMakeRect(MARGIN, SEARCH_WINDOW_HEIGHT - MARGIN - 26.0, innerWidth, 26.0)] autorelease];
	[filterField setTarget:self];
	[filterField setAction:@selector(filterChanged:)];
	[[filterField cell] setSendsSearchStringImmediately:YES];
	[filterField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
	[content addSubview:filterField];

	table = [[[NSTableView alloc] initWithFrame:NSZeroRect] autorelease];
	NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
	[table addTableColumn:column];
	[table setHeaderView:nil];
	[table setDataSource:self];
	[table setDelegate:self];
	[table setTarget:self];
	[table setDoubleAction:@selector(select:)];
	[table setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];

	NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(MARGIN, MARGIN + BUTTON_AREA_HEIGHT,
																		   innerWidth,
																		   SEARCH_WINDOW_HEIGHT - (2 * MARGIN) - BUTTON_AREA_HEIGHT - 34.0)] autorelease];
	[scroll setDocumentView:table];
	[scroll setHasVerticalScroller:YES];
	[scroll setBorderType:NSBezelBorder];
	[scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
	[content addSubview:scroll];

	selectButton = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
	[selectButton setBezelStyle:NSBezelStyleRounded];
	[selectButton setTitle:AILocalizedString(@"Select", nil)];
	[selectButton setKeyEquivalent:@"\r"];
	[selectButton setTarget:self];
	[selectButton setAction:@selector(select:)];
	[selectButton sizeToFit];

	cancelButton = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
	[cancelButton setBezelStyle:NSBezelStyleRounded];
	[cancelButton setTitle:AILocalizedString(@"Cancel", nil)];
	[cancelButton setKeyEquivalent:@"\033"];
	[cancelButton setTarget:self];
	[cancelButton setAction:@selector(cancel:)];
	[cancelButton sizeToFit];

	NSRect selectFrame = [selectButton frame];
	NSRect cancelFrame = [cancelButton frame];
	CGFloat buttonWidth = MAX(NSWidth(selectFrame), 90.0);
	CGFloat cancelWidth = MAX(NSWidth(cancelFrame), 90.0);

	[selectButton setFrame:NSMakeRect(SEARCH_WINDOW_WIDTH - MARGIN - buttonWidth, MARGIN, buttonWidth, 32.0)];
	[selectButton setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin)];
	[cancelButton setFrame:NSMakeRect(SEARCH_WINDOW_WIDTH - MARGIN - buttonWidth - 8.0 - cancelWidth, MARGIN, cancelWidth, 32.0)];
	[cancelButton setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin)];
	[content addSubview:selectButton];
	[content addSubview:cancelButton];

	[self setWindow:panel];
	[panel setDelegate:self];
	[self updateSelectButton];
}

#pragma mark Filtering

- (void)applyFilter
{
	NSString *text = [[filterField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

	[shown release];

	if (![text length]) {
		shown = [people retain];
	} else {
		NSMutableArray *matching = [NSMutableArray array];

		for (AIAddressBookPerson *aPerson in people) {
			if ([[self nameForPerson:aPerson] rangeOfString:text
													options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)].location != NSNotFound)
				[matching addObject:aPerson];
		}
		shown = [matching retain];
	}

	[table reloadData];
	[self updateSelectButton];
}

- (IBAction)filterChanged:(id)sender
{
	[self applyFilter];
}

#pragma mark Actions

- (IBAction)select:(id)sender
{
	NSInteger row = [table selectedRow];
	if (row < 0 || row >= (NSInteger)[shown count]) return;

	[person release];
	person = [[shown objectAtIndex:row] retain];

	[[[self window] sheetParent] endSheet:[self window] returnCode:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender
{
	[[[self window] sheetParent] endSheet:[self window] returnCode:NSModalResponseCancel];
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [shown count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if (rowIndex < 0 || rowIndex >= (NSInteger)[shown count]) return nil;

	return [self nameForPerson:[shown objectAtIndex:rowIndex]];
}

- (void)updateSelectButton
{
	[selectButton setEnabled:([table selectedRow] >= 0)];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	[self updateSelectButton];
}

#pragma mark Delegate

- (id)delegate
{
	return delegate;
}

- (void)setDelegate:(id)newDelegate
{
	delegate = newDelegate;
}

#pragma mark What was chosen

- (AIAddressBookPerson *)selectedPerson
{
	return person;
}

/*!
 * @brief The chat name the card carries for the requested service, if any
 *
 * Jabber cards say so in their instant-message entries (or through a Google
 * address); a service that knows people by number or address takes the card's
 * first one of those.
 */
- (NSString *)selectedScreenName
{
	if (!person) return nil;

	if ([service.serviceClass isEqualToString:@"Jabber"]) {
		NSArray *jabberNames = person.jabberNames;
		if ([jabberNames count]) return [jabberNames objectAtIndex:0];

		for (NSString *email in person.emailAddresses) {
			if ([email hasSuffix:@"gmail.com"] || [email hasSuffix:@"googlemail.com"])
				return email;
		}
	}

	if (service.userNamesArePhoneNumbers) {
		NSArray *numbers = person.phoneNumbers;
		if ([numbers count]) return [numbers objectAtIndex:0];
	}

	if (service.userNamesAreEmailAddresses) {
		NSArray *addresses = person.emailAddresses;
		if ([addresses count]) return [addresses objectAtIndex:0];
	}

	return nil;
}

- (NSString *)selectedName
{
	return (person ? [self nameForPerson:person] : nil);
}

- (NSString *)selectedAlias
{
	return [self selectedName];
}

- (AIService *)selectedService
{
	return service;
}

@end
