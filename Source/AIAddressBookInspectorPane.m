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

#import "AIAddressBookInspectorPane.h"

#import <Adium/AIAddressBookController.h>
#import <Adium/AIListContact.h>
#import <Adium/AIListObject.h>
#import <AIUtilities/AIStringAdditions.h>

#define PANE_WIDTH			300.0
#define PANE_HEIGHT			258.0
#define MARGIN				12.0
#define CARD_SIDE			48.0
#define BUTTON_HEIGHT		28.0

/* AILocalizedString reaches for [self class] to find its bundle, which the plain C helper below
 * does not have. It names the class instead. */
#define AICardString(key, comment)	AILocalizedStringFromTableInBundle(key, nil, \
									[NSBundle bundleForClass:[AIAddressBookInspectorPane class]], comment)

@interface AIAddressBookInspectorPane ()
- (void)buildView;
- (ABPerson *)attachedPerson;
- (BOOL)attachmentWasChosen;
- (void)applyFilter;
- (void)filterChanged:(id)sender;
- (void)performAction:(id)sender;
- (void)updateState;
- (void)loadPeople;
- (void)reloadCards;
- (void)addressBookChanged:(NSNotification *)notification;
@end

@implementation AIAddressBookInspectorPane

/*!
 * @brief The name a card goes by
 */
static NSString *AICardName(ABPerson *person)
{
	NSString		*first = [person valueForProperty:kABFirstNameProperty];
	NSString		*last = [person valueForProperty:kABLastNameProperty];
	NSMutableArray	*parts = [NSMutableArray array];

	if ([first length]) [parts addObject:first];
	if ([last length]) [parts addObject:last];

	if ([parts count])
		return [parts componentsJoinedByString:@" "];

	NSString *organisation = [person valueForProperty:kABOrganizationProperty];

	return ([organisation length] ? organisation : AICardString(@"Unnamed card", "Name shown for an address book card that has no name on it"));
}

- (id)init
{
	if ((self = [super init])) {
		[self buildView];

		/* The Contacts app writes to the same database, and says so when it does. Without this the
		 * list would show whatever was there when the window opened, which for a pane that stays
		 * open while somebody edits a card next door is exactly the wrong moment to be stale. */
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(addressBookChanged:)
													 name:kABDatabaseChangedExternallyNotification
												   object:nil];
	}

	return self;
}

/*!
 * @brief Somebody changed the address book from outside Adium
 *
 * Done after the current round of notifications rather than during it, because the address book
 * controller is listening for the same one and rebuilds what it knows; asking it anything while
 * that is still going on would be asking too early.
 */
- (void)addressBookChanged:(NSNotification *)notification
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadCards) object:nil];
	[self performSelector:@selector(reloadCards) withObject:nil afterDelay:0.0];
}

- (void)reloadCards
{
	if (!displayedObject) return;

	[self loadPeople];
	[self applyFilter];
	[table reloadData];
	[self updateState];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];

	[displayedObject release];
	[people release];
	[shown release];
	[inspectorContentView release];

	[super dealloc];
}

//Building --------------------------------------------------------------------------------------------------------
#pragma mark Building

static NSTextField *AILabel(NSRect frame, CGFloat size, NSColor *colour)
{
	NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];

	[field setEditable:NO];
	[field setSelectable:NO];
	[field setBordered:NO];
	[field setDrawsBackground:NO];
	[field setFont:[NSFont systemFontOfSize:size]];
	[field setTextColor:colour];
	[[field cell] setLineBreakMode:NSLineBreakByTruncatingTail];
	[field setStringValue:@""];

	return field;
}

/*!
 * @brief Build the pane's view
 *
 * Two views take turns in the same place rather than standing beside each other, because there is
 * not room for both and no reason to show both: either a card is attached, and then which one is
 * what matters, or none is, and then finding one is. The button underneath stays where it is and
 * says what it does, so the state is read off the content rather than off the control.
 */
- (void)buildView
{
	NSRect	 frame = NSMakeRect(0.0, 0.0, PANE_WIDTH, PANE_HEIGHT);
	CGFloat	 innerWidth = PANE_WIDTH - (2 * MARGIN);
	CGFloat	 contentBottom = MARGIN + BUTTON_HEIGHT + 8.0;

	inspectorContentView = [[NSView alloc] initWithFrame:frame];
	[inspectorContentView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

	NSRect contentFrame = NSMakeRect(MARGIN, contentBottom, innerWidth, PANE_HEIGHT - contentBottom - MARGIN);

	//The card that is attached
	summaryView = [[[NSView alloc] initWithFrame:contentFrame] autorelease];
	[summaryView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
	[inspectorContentView addSubview:summaryView];

	CGFloat summaryTop = NSHeight(contentFrame) - CARD_SIDE;

	cardImage = [[[NSImageView alloc] initWithFrame:NSMakeRect(0.0, summaryTop, CARD_SIDE, CARD_SIDE)] autorelease];
	[cardImage setEditable:NO];
	[cardImage setImageScaling:NSImageScaleProportionallyUpOrDown];
	[cardImage setImageFrameStyle:NSImageFrameGrayBezel];
	[cardImage setAutoresizingMask:NSViewMinYMargin];
	[summaryView addSubview:cardImage];

	CGFloat textX = CARD_SIDE + 10.0;
	CGFloat textWidth = innerWidth - textX;

	cardName = AILabel(NSMakeRect(textX, summaryTop + CARD_SIDE - 20.0, textWidth, 17.0),
					   [NSFont systemFontSize], [NSColor labelColor]);
	[cardName setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
	[summaryView addSubview:cardName];

	/* Where the card came from, which is the whole reason this pane has three states: one Adium
	 * found by itself cannot be let go, only overruled. */
	cardOrigin = AILabel(NSMakeRect(textX, summaryTop + CARD_SIDE - 38.0, textWidth, 14.0),
						 [NSFont smallSystemFontSize], [NSColor secondaryLabelColor]);
	[cardOrigin setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
	[summaryView addSubview:cardOrigin];

	//Finding one
	chooserView = [[[NSView alloc] initWithFrame:contentFrame] autorelease];
	[chooserView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
	[inspectorContentView addSubview:chooserView];

	CGFloat filterTop = NSHeight(contentFrame) - 22.0;

	filterField = [[[NSSearchField alloc] initWithFrame:NSMakeRect(0.0, filterTop, innerWidth, 22.0)] autorelease];
	[[filterField cell] setPlaceholderString:AILocalizedString(@"Filter", "Placeholder of the field which narrows the list of cards")];
	[filterField setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[filterField setTarget:self];
	[filterField setAction:@selector(filterChanged:)];
	[filterField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
	[chooserView addSubview:filterField];

	NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, innerWidth, filterTop - 6.0)] autorelease];
	[scroll setHasVerticalScroller:YES];
	[scroll setAutohidesScrollers:YES];
	[scroll setBorderType:NSBezelBorder];
	[scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

	table = [[[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]] autorelease];
	[table setUsesAlternatingRowBackgroundColors:YES];
	[table setAllowsMultipleSelection:NO];
	[table setHeaderView:nil];
	[table setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
	[table setDataSource:self];
	[table setDelegate:self];

	NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"card"] autorelease];
	[column setWidth:innerWidth - 4.0];
	[table addTableColumn:column];

	[scroll setDocumentView:table];
	[chooserView addSubview:scroll];

	//The one button, whose meaning follows the state above it
	actionButton = [[[NSButton alloc] initWithFrame:NSMakeRect(MARGIN, MARGIN, innerWidth, BUTTON_HEIGHT)] autorelease];
	[actionButton setBezelStyle:NSBezelStyleRounded];
	[actionButton setTarget:self];
	[actionButton setAction:@selector(performAction:)];
	[actionButton setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
	[inspectorContentView addSubview:actionButton];
}

- (NSView *)inspectorContentView
{
	return inspectorContentView;
}

//What is attached ------------------------------------------------------------------------------------------------
#pragma mark What is attached

- (ABPerson *)attachedPerson
{
	return (displayedObject ? [AIAddressBookController personForListObject:displayedObject] : nil);
}

/*!
 * @brief Whether the attached card was picked by somebody rather than found by Adium
 */
- (BOOL)attachmentWasChosen
{
	NSString	*stored = [displayedObject preferenceForKey:KEY_AB_UNIQUE_ID group:PREF_GROUP_ADDRESSBOOK];

	/* Not merely whether a choice is on record, but whether the card being shown is the one that was
	 * chosen. Delete that card in the Contacts app and the record still names it while the search
	 * quietly turns up a different one; calling that "chosen by you" would offer to let go of
	 * something nobody picked, and letting go would change nothing anybody could see. */
	return ([stored length] && [[[self attachedPerson] uniqueId] isEqualToString:stored]);
}

/*!
 * @brief Every card, once, sorted the way the list will show them
 */
- (void)loadPeople
{
	[people release];
	people = [[[[ABAddressBook sharedAddressBook] people] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
		return [AICardName(a) localizedCaseInsensitiveCompare:AICardName(b)];
	}] retain];
}

- (void)updateForListObject:(AIListObject *)inObject
{
	//The card belongs to the person, not to one of their accounts
	AIListObject *owner = ([inObject isKindOfClass:[AIListContact class]] ?
						   (AIListObject *)[(AIListContact *)inObject parentContact] :
						   inObject);

	[displayedObject release];
	displayedObject = [owner retain];

	choosing = NO;

	[self loadPeople];

	[filterField setStringValue:@""];
	[self applyFilter];
	[table reloadData];

	[self updateState];
}

/*!
 * @brief Show the state the contact is in, and offer what can be done from there
 */
- (void)updateState
{
	ABPerson	*person = [self attachedPerson];
	BOOL		 chosen = [self attachmentWasChosen];
	BOOL		 showSummary = (person && !choosing);

	[summaryView setHidden:!showSummary];
	[chooserView setHidden:showSummary];

	if (showSummary) {
		NSData	*imageData = [person imageData];

		[cardImage setImage:([imageData length] ? [[[NSImage alloc] initWithData:imageData] autorelease] : nil)];
		[cardName setStringValue:AICardName(person)];
		[cardOrigin setStringValue:(chosen ?
									AILocalizedString(@"Chosen by you", "Where an attached address book card came from") :
									AILocalizedString(@"Found by Adium", "Where an attached address book card came from"))];

		/* Only a card somebody chose can be let go. Letting go of one Adium found would achieve
		 * nothing: there is no choice stored to forget, and the same card would be found again on
		 * the spot. Overruling it is all that is left, so that is what the button offers. */
		[actionButton setTitle:(chosen ?
								AILocalizedString(@"Detach Card", "Button which forgets the address book card chosen for a contact") :
								AILocalizedString(@"Choose Another Card", "Button which replaces the address book card Adium found with a chosen one"))];
		[actionButton setEnabled:YES];

	} else {
		[actionButton setTitle:AILocalizedString(@"Attach Card", "Button which attaches the selected address book card to a contact")];
		[actionButton setEnabled:([table selectedRow] >= 0)];
	}
}

//Doing it --------------------------------------------------------------------------------------------------------
#pragma mark Doing it

- (void)performAction:(id)sender
{
	if (![displayedObject isKindOfClass:[AIListContact class]])
		return;

	AIListContact	*contact = (AIListContact *)displayedObject;
	ABPerson		*person = [self attachedPerson];

	if (person && !choosing) {
		if ([self attachmentWasChosen]) {
			//Forget the choice. Adium may well find one by itself again, and then says so.
			[contact setAddressBookPerson:nil];

		} else {
			//Nothing stored to forget, so move on to picking one instead
			choosing = YES;
		}

	} else {
		NSInteger row = [table selectedRow];

		if (row < 0 || row >= (NSInteger)[shown count])
			return;

		[contact setAddressBookPerson:[shown objectAtIndex:row]];
		choosing = NO;
	}

	[self updateState];
}

//The list --------------------------------------------------------------------------------------------------------
#pragma mark The list

- (void)applyFilter
{
	NSString *text = [[filterField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

	[shown release];

	if (![text length]) {
		shown = [people copy];

	} else {
		NSMutableArray *matching = [NSMutableArray array];

		for (ABPerson *person in people) {
			if ([AICardName(person) rangeOfString:text
										  options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)].location != NSNotFound)
				[matching addObject:person];
		}

		shown = [matching copy];
	}
}

- (void)filterChanged:(id)sender
{
	[self applyFilter];
	[table reloadData];
	[self updateState];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [shown count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	return AICardName([shown objectAtIndex:row]);
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self updateState];
}

@end
