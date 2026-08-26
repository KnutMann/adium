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

#import "AIAddressBookPictureWindowController.h"

#import <Adium/AIAddressBookController.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIListContact.h>
#import <Adium/AIService.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <Contacts/Contacts.h>

//Keys of one row
#define ENTRY_PERSON		@"Person"
#define ENTRY_CONTACTS		@"Contacts"		//AIListContacts that have a picture, one per service
#define ENTRY_OWNER			@"Owner"		//The metacontact, or the contact itself
#define ENTRY_INDEX			@"Index"		//Which of the pictures is being looked at

#define PICTURE_SIDE		160.0
#define WINDOW_WIDTH		780.0
/* The window opens at the smallest size it works at: everything above the list is fixed in
 * height, so the extra room only ever went to the list, and whoever wants a longer list can
 * pull it open. One constant for both, or the two drift apart. */
#define WINDOW_HEIGHT		320.0

/* AILocalizedString reaches for [self class] to find its bundle, which the plain C helpers below
 * do not have. They name the class instead. */
#define AIPictureString(key, comment)	AILocalizedStringFromTableInBundle(key, nil, \
										[NSBundle bundleForClass:[AIAddressBookPictureWindowController class]], comment)

static AIAddressBookPictureWindowController *sharedController = nil;

@interface AIAddressBookPictureWindowController ()
- (void)buildWindow;
- (void)buildEntries;
- (NSDictionary *)selectedEntry;
- (AIListContact *)shownContactForEntry:(NSDictionary *)entry;
- (void)updateSides;
- (void)transfer:(id)sender;
- (void)stepPicture:(id)sender;
- (void)applyFilter;
- (void)filterChanged:(id)sender;
- (void)rebuild;
- (void)addressBookChanged:(NSNotification *)notification;
@end

@implementation AIAddressBookPictureWindowController

+ (void)showWindow
{
	if (!sharedController)
		sharedController = [[self alloc] init];

	[sharedController buildEntries];
	[sharedController applyFilter];
	[sharedController->table reloadData];
	[sharedController updateSides];

	[sharedController showWindow:nil];
	[[sharedController window] makeKeyAndOrderFront:nil];
}

- (id)init
{
	if ((self = [super initWithWindow:nil])) {
		entries = [[NSMutableArray alloc] init];
		[self buildWindow];

		/* The Contacts app writes to the same database and says so when it does, which matters here
		 * more than anywhere: this window exists to compare two pictures, and comparing against one
		 * that has since been replaced next door is worse than showing none. */
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(addressBookChanged:)
													 name:CNContactStoreDidChangeNotification
												   object:nil];
	}

	return self;
}

/*!
 * @brief Somebody changed the address book from outside Adium
 *
 * After the current round of notifications rather than during it: the address book controller is
 * listening for the same one and rebuilds what it knows about which card belongs to whom, and the
 * list here is built from exactly that.
 */
- (void)addressBookChanged:(NSNotification *)notification
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(rebuild) object:nil];
	[self performSelector:@selector(rebuild) withObject:nil afterDelay:0.0];
}

/*!
 * @brief Build the list again, keeping whoever was selected selected
 */
- (void)rebuild
{
	NSDictionary	*wasSelected = [self selectedEntry];
	NSString		*uniqueID = [[wasSelected objectForKey:ENTRY_PERSON] uniqueId];

	[self buildEntries];
	[self applyFilter];
	[table reloadData];

	if (uniqueID) {
		NSUInteger index = 0;

		for (NSDictionary *entry in shown) {
			if ([[[entry objectForKey:ENTRY_PERSON] uniqueId] isEqualToString:uniqueID]) {
				[table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
				[table scrollRowToVisible:index];
				break;
			}
			index++;
		}
	}

	[self updateSides];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

//Building the window ---------------------------------------------------------------------------------------------
#pragma mark Building the window

static NSTextField *AICaption(NSRect frame, NSTextAlignment alignment)
{
	NSTextField *field = [[NSTextField alloc] initWithFrame:frame];

	[field setEditable:NO];
	[field setSelectable:NO];
	[field setBordered:NO];
	[field setDrawsBackground:NO];
	[field setAlignment:alignment];
	[field setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[field setTextColor:[NSColor secondaryLabelColor]];
	[[field cell] setLineBreakMode:NSLineBreakByTruncatingTail];
	[field setStringValue:@""];

	return field;
}

static NSImageView *AIPictureWell(NSRect frame)
{
	NSImageView *view = [[NSImageView alloc] initWithFrame:frame];

	[view setEditable:NO];
	[view setImageScaling:NSImageScaleProportionallyUpOrDown];
	[view setImageFrameStyle:NSImageFrameGrayBezel];

	return view;
}

- (void)buildWindow
{
	NSRect		 frame = NSMakeRect(0.0, 0.0, WINDOW_WIDTH, WINDOW_HEIGHT);
	NSWindow	*window = [[NSWindow alloc] initWithContentRect:frame
													   styleMask:(NSWindowStyleMaskTitled |
																  NSWindowStyleMaskClosable |
																  NSWindowStyleMaskResizable)
														 backing:NSBackingStoreBuffered
														   defer:YES];
	NSView		*content = [window contentView];

	[window setTitle:AILocalizedString(@"Contact Pictures", "Title of the window which hands contact pictures to address book cards")];
	[window setMinSize:NSMakeSize(WINDOW_WIDTH, WINDOW_HEIGHT)];
	[window setReleasedWhenClosed:NO];
	[self setWindow:window];

	CGFloat top = WINDOW_HEIGHT - 20.0 - PICTURE_SIDE;

	//The picture Adium holds, on the left
	adiumImage = AIPictureWell(NSMakeRect(20.0, top, PICTURE_SIDE, PICTURE_SIDE));
	[adiumImage setAutoresizingMask:NSViewMinYMargin];
	[content addSubview:adiumImage];

	adiumCaption = AICaption(NSMakeRect(20.0, top - 20.0, PICTURE_SIDE, 16.0), NSTextAlignmentCenter);
	[adiumCaption setAutoresizingMask:NSViewMinYMargin];
	[content addSubview:adiumCaption];

	/* Leafing through the pictures. A contact who is one person across several services has one
	 * picture per service, and only the person looking at them can say which one belongs on a card. */
	previousButton = [[NSButton alloc] initWithFrame:NSMakeRect(20.0, top - 48.0, 40.0, 24.0)];
	[previousButton setBezelStyle:NSBezelStyleRounded];
	[previousButton setTitle:@"◀"];
	[previousButton setTarget:self];
	[previousButton setAction:@selector(stepPicture:)];
	[previousButton setTag:-1];
	[previousButton setAutoresizingMask:NSViewMinYMargin];
	[content addSubview:previousButton];

	nextButton = [[NSButton alloc] initWithFrame:NSMakeRect(140.0, top - 48.0, 40.0, 24.0)];
	[nextButton setBezelStyle:NSBezelStyleRounded];
	[nextButton setTitle:@"▶"];
	[nextButton setTarget:self];
	[nextButton setAction:@selector(stepPicture:)];
	[nextButton setTag:1];
	[nextButton setAutoresizingMask:NSViewMinYMargin];
	[content addSubview:nextButton];

	//The list in the middle, with the filter sitting over it
	CGFloat listX = 200.0;
	CGFloat listWidth = WINDOW_WIDTH - listX - 20.0 - PICTURE_SIDE - 20.0;

	filterField = [[NSSearchField alloc] initWithFrame:NSMakeRect(listX, WINDOW_HEIGHT - 20.0 - 24.0, listWidth, 24.0)];
	[[filterField cell] setPlaceholderString:AILocalizedString(@"Filter", "Placeholder of the field which narrows the list of cards")];
	[filterField setTarget:self];
	[filterField setAction:@selector(filterChanged:)];
	[filterField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
	[content addSubview:filterField];

	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(listX, 20.0,
																		  listWidth,
																		  WINDOW_HEIGHT - 20.0 - 24.0 - 8.0 - 20.0)];
	[scroll setHasVerticalScroller:YES];
	[scroll setAutohidesScrollers:YES];
	[scroll setBorderType:NSBezelBorder];
	[scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

	table = [[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]];
	[table setUsesAlternatingRowBackgroundColors:YES];
	[table setRowSizeStyle:NSTableViewRowSizeStyleDefault];
	[table setAllowsMultipleSelection:NO];
	[table setDataSource:self];
	[table setDelegate:self];

	/* One column, and no header over it. The card and the contact carry the same name in every row
	 * that can appear here, since a card is only listed because Adium matched it to that contact,
	 * so a second column would have repeated the first one all the way down. */
	NSTableColumn *cardColumn = [[NSTableColumn alloc] initWithIdentifier:@"card"];
	[cardColumn setWidth:360.0];
	[table addTableColumn:cardColumn];

	[table setHeaderView:nil];
	[table setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];

	[scroll setDocumentView:table];
	[content addSubview:scroll];

	//The picture the card holds, on the right
	CGFloat rightX = WINDOW_WIDTH - 20.0 - PICTURE_SIDE;

	cardImage = AIPictureWell(NSMakeRect(rightX, top, PICTURE_SIDE, PICTURE_SIDE));
	[cardImage setAutoresizingMask:(NSViewMinXMargin | NSViewMinYMargin)];
	[content addSubview:cardImage];

	cardCaption = AICaption(NSMakeRect(rightX, top - 20.0, PICTURE_SIDE, 16.0), NSTextAlignmentCenter);
	[cardCaption setAutoresizingMask:(NSViewMinXMargin | NSViewMinYMargin)];
	[content addSubview:cardCaption];

	transferButton = [[NSButton alloc] initWithFrame:NSMakeRect(rightX, top - 52.0, PICTURE_SIDE, 28.0)];
	[transferButton setBezelStyle:NSBezelStyleRounded];
	[transferButton setTitle:AILocalizedString(@"Put on Card", "Button which writes the shown contact picture onto the address book card")];
	[transferButton setTarget:self];
	[transferButton setAction:@selector(transfer:)];
	[transferButton setAutoresizingMask:(NSViewMinXMargin | NSViewMinYMargin)];
	[content addSubview:transferButton];

	[window center];
}

//What there is to show -------------------------------------------------------------------------------------------
#pragma mark What there is to show

/*!
 * @brief The name a card goes by
 */
static NSString *AICardName(AIAddressBookPerson *person)
{
	NSString		*first = person.firstName;
	NSString		*last = person.lastName;
	NSMutableArray	*parts = [NSMutableArray array];

	if ([first length]) [parts addObject:first];
	if ([last length]) [parts addObject:last];

	if ([parts count])
		return [parts componentsJoinedByString:@" "];

	NSString *organisation = person.organization;

	return ([organisation length] ? organisation : AIPictureString(@"Unnamed card", "Name shown for an address book card that has no name on it"));
}

/*!
 * @brief Collect every card that Adium already believes belongs to somebody in the contact list
 *
 * Grouped by card rather than by contact, because that is the side being written to: two contacts
 * on the same card are two pictures to choose between, not two rows.
 */
- (void)buildEntries
{
	NSMutableDictionary *byPerson = [NSMutableDictionary dictionary];

	[entries removeAllObjects];

	for (AIListContact *contact in adium.contactController.allContacts) {
		AIListObject	*owner = ([contact parentContact] ? (AIListObject *)[contact parentContact] : (AIListObject *)contact);
		AIAddressBookPerson	*person = [AIAddressBookController personForListObject:owner];

		if (!person)
			continue;

		NSMutableDictionary *entry = [byPerson objectForKey:[person uniqueId]];

		if (!entry) {
			entry = [NSMutableDictionary dictionary];
			[entry setObject:person forKey:ENTRY_PERSON];
			[entry setObject:owner forKey:ENTRY_OWNER];
			[entry setObject:[NSMutableArray array] forKey:ENTRY_CONTACTS];
			[entry setObject:[NSNumber numberWithInteger:0] forKey:ENTRY_INDEX];

			[byPerson setObject:entry forKey:[person uniqueId]];
			[entries addObject:entry];
		}

		//Only a contact that actually has a picture is worth leafing to
		if ([contact userIcon])
			[(NSMutableArray *)[entry objectForKey:ENTRY_CONTACTS] addObject:contact];
	}

	[entries sortUsingComparator:^NSComparisonResult(id a, id b) {
		return [AICardName([a objectForKey:ENTRY_PERSON])
				localizedCaseInsensitiveCompare:AICardName([b objectForKey:ENTRY_PERSON])];
	}];
}

- (NSDictionary *)selectedEntry
{
	NSInteger row = [table selectedRow];

	return ((row >= 0 && row < (NSInteger)[shown count]) ? [shown objectAtIndex:row] : nil);
}

/*!
 * @brief Narrow the list to what was typed
 *
 * Matched against the name on the card, which is the only thing the list shows.
 */
- (void)applyFilter
{
	NSString *text = [[filterField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

	if (![text length]) {
		shown = [entries copy];

	} else {
		NSMutableArray *matching = [NSMutableArray array];

		for (NSDictionary *entry in entries) {
			if ([AICardName([entry objectForKey:ENTRY_PERSON]) rangeOfString:text
																	options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)].location != NSNotFound)
				[matching addObject:entry];
		}

		shown = [matching copy];
	}
}

- (void)filterChanged:(id)sender
{
	[self applyFilter];
	[table reloadData];
	[self updateSides];
}

- (AIListContact *)shownContactForEntry:(NSDictionary *)entry
{
	NSArray *contacts = [entry objectForKey:ENTRY_CONTACTS];

	if (![contacts count])
		return nil;

	NSInteger index = [[entry objectForKey:ENTRY_INDEX] integerValue];

	return [contacts objectAtIndex:(index % [contacts count])];
}

/*!
 * @brief Redraw both pictures and everything said about them
 */
- (void)updateSides
{
	NSDictionary	*entry = [self selectedEntry];
	AIListContact	*contact = [self shownContactForEntry:entry];
	NSArray			*contacts = [entry objectForKey:ENTRY_CONTACTS];
	NSImage			*icon = [contact userIcon];

	[adiumImage setImage:icon];

	if (!entry) {
		[adiumCaption setStringValue:@""];

	} else if (!icon) {
		[adiumCaption setStringValue:AILocalizedString(@"No picture", "Shown where a contact has no picture to hand over")];

	} else {
		NSSize	 size = [icon size];
		NSString *service = [[contact service] shortDescription];

		/* The size is worth saying out loud: a service that only ever hands over a thumbnail can be
		 * told from one that hands over the real thing, and this window can do nothing about it. */
		NSString *where = ([contacts count] > 1 ?
						   [NSString stringWithFormat:AILocalizedString(@"%@ (%li of %li)", "Which service a contact picture is from, and which of several it is"),
							service, (long)([[entry objectForKey:ENTRY_INDEX] integerValue] % [contacts count]) + 1, (long)[contacts count]] :
						   service);

		[adiumCaption setStringValue:[NSString stringWithFormat:@"%@, %li × %li",
									  where, (long)size.width, (long)size.height]];
	}

	//What the card holds today
	NSData	*cardData = [[entry objectForKey:ENTRY_PERSON] imageData];
	NSImage	*cardIcon = ([cardData length] ? [[NSImage alloc] initWithData:cardData] : nil);

	[cardImage setImage:cardIcon];

	if (!entry) {
		[cardCaption setStringValue:@""];
	} else if (!cardIcon) {
		[cardCaption setStringValue:AILocalizedString(@"Card has no picture", "Shown where an address book card carries no picture")];
	} else {
		NSSize size = [cardIcon size];
		[cardCaption setStringValue:[NSString stringWithFormat:@"%li × %li", (long)size.width, (long)size.height]];
	}

	[previousButton setEnabled:([contacts count] > 1)];
	[nextButton setEnabled:([contacts count] > 1)];
	[transferButton setEnabled:(icon != nil)];
}

//Doing it --------------------------------------------------------------------------------------------------------
#pragma mark Doing it

- (void)stepPicture:(id)sender
{
	NSMutableDictionary *entry = (NSMutableDictionary *)[self selectedEntry];
	NSArray				*contacts = [entry objectForKey:ENTRY_CONTACTS];

	if ([contacts count] < 2)
		return;

	NSInteger index = [[entry objectForKey:ENTRY_INDEX] integerValue] + [sender tag];

	//Wrap rather than stop, so leafing never dead ends
	while (index < 0)
		index += [contacts count];

	[entry setObject:[NSNumber numberWithInteger:(index % [contacts count])] forKey:ENTRY_INDEX];

	[self updateSides];
}

/*!
 * @brief Write the picture being shown onto the card
 *
 * The picture as Adium holds it, which is whatever the service handed over: it is scaled down for
 * the contact list and for menus, never in what is kept, so nothing is lost on the way here.
 */
- (void)transfer:(id)sender
{
	NSDictionary		*entry = [self selectedEntry];
	AIListContact		*contact = [self shownContactForEntry:entry];
	AIAddressBookPerson	*person = [entry objectForKey:ENTRY_PERSON];
	NSImage				*icon = [contact userIcon];
	NSData				*data = [icon PNGRepresentation];

	if (!person || ![data length]) {
		NSBeep();
		return;
	}

	CNMutableContact	*mutableContact = [person.contact mutableCopy];
	CNSaveRequest		*saveRequest = [[CNSaveRequest alloc] init];

	mutableContact.imageData = data;
	[saveRequest updateContact:mutableContact];

	/* Nothing is said when it works: the picture on the right changes, which says it better. A
	 * refusal has to speak up, because nothing would look any different. */
	if (![[[CNContactStore alloc] init] executeSaveRequest:saveRequest error:NULL]) {
		NSAlert *alert = [[NSAlert alloc] init];

		[alert setMessageText:AILocalizedString(@"The Address Book would not save the picture.",
												"Said when writing a contact picture onto a card failed")];
		[alert beginSheetModalForWindow:[self window] completionHandler:nil];
	}

	[self updateSides];
}

//The list --------------------------------------------------------------------------------------------------------
#pragma mark The list

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [shown count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	return AICardName([[shown objectAtIndex:row] objectForKey:ENTRY_PERSON]);
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self updateSides];
}

@end
