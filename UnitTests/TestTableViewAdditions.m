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

#import <AIUtilities/AITableViewAdditions.h>

@interface TestTableViewAdditions : XCTestCase
@end

/* Three rows, a context menu on request, and a count of how often the table asked for the
 * selection to be deleted. */
@interface AITableTestDataSource : NSObject <NSTableViewDataSource, NSTableViewDelegate, AITableViewDelegate>
@property (nonatomic, strong) NSArray<NSString *> *rows;
@property (nonatomic, strong) NSMenu *contextMenu;
@property (nonatomic, assign) NSUInteger deleteRequests;
@property (nonatomic, weak) NSTableView *lastTableAskingToDelete;
@end

@implementation AITableTestDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[self.rows count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	return self.rows[(NSUInteger)row];
}

- (void)tableViewDeleteSelectedRows:(NSTableView *)tableView
{
	self.deleteRequests++;
	self.lastTableAskingToDelete = tableView;
}

- (NSMenu *)tableView:(NSTableView *)inTableView menuForEvent:(NSEvent *)theEvent
{
	return self.contextMenu;
}

@end

//A delegate that has nothing to say about deleting or menus
@interface AIQuietTableDelegate : AITableTestDataSource
@end

@implementation AIQuietTableDelegate

- (BOOL)respondsToSelector:(SEL)selector
{
	if (selector == @selector(tableViewDeleteSelectedRows:) || selector == @selector(tableView:menuForEvent:)) return NO;
	return [super respondsToSelector:selector];
}

@end

@implementation TestTableViewAdditions {
	NSTableView				*tableView;
	NSTableColumn			*column;
	AITableTestDataSource	*dataSource;
}

- (void)setUp
{
	[super setUp];
	tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
	column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	[tableView addTableColumn:column];
	[tableView setAllowsMultipleSelection:YES];
	dataSource = [[AITableTestDataSource alloc] init];
	dataSource.rows = @[@"x", @"y", @"z"];
	dataSource.contextMenu = [[NSMenu alloc] initWithTitle:@"Context"];
	[tableView setDataSource:dataSource];
	[tableView setDelegate:dataSource];
	[tableView reloadData];
}

- (void)selectRows:(NSIndexSet *)rows
{
	[tableView selectRowIndexes:rows byExtendingSelection:NO];
}

- (NSEvent *)keyDownWithCharacter:(unichar)character
{
	NSString *characters = [NSString stringWithCharacters:&character length:1];
	return [NSEvent keyEventWithType:NSEventTypeKeyDown
							location:NSZeroPoint
					   modifierFlags:0
						   timestamp:0
						windowNumber:0
							 context:nil
						  characters:characters
		 charactersIgnoringModifiers:characters
						   isARepeat:NO
							 keyCode:0];
}

#pragma mark Selection by item

- (void)testSelectedItemsFromArrayAreTheItemsOfTheSelectedRowsInRowOrder
{
	NSMutableIndexSet *rows = [NSMutableIndexSet indexSetWithIndex:2];
	[rows addIndex:0];
	[self selectRows:rows];

	XCTAssertEqualObjects([tableView selectedItemsFromArray:dataSource.rows], (@[@"x", @"z"]));
}

- (void)testSelectedItemsFromArrayIsEmptyWithoutASelection
{
	[tableView deselectAll:nil];

	XCTAssertEqualObjects([tableView selectedItemsFromArray:dataSource.rows], @[]);
}

- (void)testSelectItemsInArrayUsingSourceArraySelectsTheMatchingRowsAndIgnoresStrangers
{
	[tableView selectItemsInArray:@[@"z", @"not a row", @"x"] usingSourceArray:dataSource.rows];

	NSMutableIndexSet *expected = [NSMutableIndexSet indexSetWithIndex:0];
	[expected addIndex:2];
	XCTAssertEqualObjects([tableView selectedRowIndexes], expected);
}

- (void)testSelectItemsInArrayUsingSourceArrayReplacesThePreviousSelection
{
	[self selectRows:[NSIndexSet indexSetWithIndex:1]];

	[tableView selectItemsInArray:@[@"z"] usingSourceArray:dataSource.rows];
	XCTAssertEqualObjects([tableView selectedRowIndexes], [NSIndexSet indexSetWithIndex:2]);
}

#pragma mark Cell views

- (void)testLabelCellViewShowsAStringInItsTextField
{
	NSTableCellView *view = [tableView ai_labelCellViewForColumn:column value:@"Hello"];

	XCTAssertTrue([view isKindOfClass:[NSTableCellView class]]);
	XCTAssertNotNil([view textField]);
	XCTAssertEqualObjects([[view textField] stringValue], @"Hello");
	XCTAssertTrue([[view textField] isDescendantOf:view]);
}

- (void)testLabelCellViewShowsOtherValuesByDescriptionAndNothingForNilOrNull
{
	XCTAssertEqualObjects([[[tableView ai_labelCellViewForColumn:column value:@42] textField] stringValue], @"42");
	XCTAssertEqualObjects([[[tableView ai_labelCellViewForColumn:column value:nil] textField] stringValue], @"");
	XCTAssertEqualObjects([[[tableView ai_labelCellViewForColumn:column value:[NSNull null]] textField] stringValue], @"");
}

- (void)testLabelCellViewIsIdentifiedByItsColumn
{
	XCTAssertEqualObjects([[tableView ai_labelCellViewForColumn:column value:@"a"] identifier], @"name");
}

- (void)testImageCellViewShowsTheImageAndNothingForNil
{
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(8, 8)];

	NSTableCellView *view = [tableView ai_imageCellViewForColumn:column image:image];
	XCTAssertNotNil([view imageView]);
	XCTAssertTrue([[view imageView] image] == image);
	XCTAssertTrue([[view imageView] isDescendantOf:view]);
	XCTAssertEqualObjects([view identifier], @"name");

	XCTAssertNil([[[tableView ai_imageCellViewForColumn:column image:nil] imageView] image]);
}

- (void)testIconLabelCellViewFillsItsOwnOutletsAndLeavesTheStandardOnesEmpty
{
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(8, 8)];

	AISidebarCellView *view = [tableView ai_iconLabelCellViewForColumn:column image:image value:@"Name"];
	XCTAssertTrue([view isKindOfClass:[AISidebarCellView class]]);
	XCTAssertEqualObjects([[view sidebarLabel] stringValue], @"Name");
	XCTAssertTrue([[view sidebarIcon] image] == image);
	XCTAssertNil([view textField], @"the outlet AppKit recolours through stays empty on purpose");
	XCTAssertNil([view imageView]);
	XCTAssertEqualObjects([view identifier], @"name");
}

- (void)testIconLabelCellViewWithoutAnImageLeavesTheIconEmpty
{
	AISidebarCellView *view = [tableView ai_iconLabelCellViewForColumn:column image:nil value:@7];

	XCTAssertNotNil([view sidebarIcon]);
	XCTAssertNil([[view sidebarIcon] image]);
	XCTAssertEqualObjects([[view sidebarLabel] stringValue], @"7");
}

- (void)testCheckboxCellViewConfiguresATitlelessCheckbox
{
	AICheckboxTableCellView *view = [tableView ai_checkboxCellViewForColumn:column
																	on:YES
															   enabled:NO
																target:dataSource
																action:@selector(description)];

	XCTAssertTrue([view isKindOfClass:[AICheckboxTableCellView class]]);
	NSButton *checkbox = [view checkbox];
	XCTAssertNotNil(checkbox);
	XCTAssertEqual([checkbox state], NSControlStateValueOn);
	XCTAssertFalse([checkbox isEnabled]);
	XCTAssertTrue([checkbox target] == dataSource);
	XCTAssertTrue([checkbox action] == @selector(description));
	XCTAssertEqualObjects([checkbox title], @"");
	XCTAssertTrue([checkbox isDescendantOf:view]);
}

- (void)testCheckboxCellViewOffIsOff
{
	AICheckboxTableCellView *view = [tableView ai_checkboxCellViewForColumn:column on:NO enabled:YES target:nil action:NULL];

	XCTAssertEqual([[view checkbox] state], NSControlStateValueOff);
	XCTAssertTrue([[view checkbox] isEnabled]);
}

#pragma mark Sidebar colours

- (void)testSidebarCellViewDimsItsLabelWhileItsWindowIsNotKey
{
	//No window at all is the furthest from key a view gets
	AISidebarCellView *view = [tableView ai_iconLabelCellViewForColumn:column image:nil value:@"Name"];

	XCTAssertEqualObjects([[view sidebarLabel] textColor], [NSColor secondaryLabelColor]);
}

- (void)testSidebarCellViewUsesTheTertiaryColourForAGroupRow
{
	AISidebarCellView *view = [tableView ai_iconLabelCellViewForColumn:column image:nil value:@"Group"];
	[view setIsGroupRow:YES];

	[view updateTextColors];
	XCTAssertEqualObjects([[view sidebarLabel] textColor], [NSColor tertiaryLabelColor]);
}

#pragma mark Keys and menus

- (void)testDeleteKeysAskTheDelegateToDeleteTheSelectedRows
{
	[self selectRows:[NSIndexSet indexSetWithIndex:1]];

	[tableView keyDown:[self keyDownWithCharacter:NSDeleteCharacter]];
	[tableView keyDown:[self keyDownWithCharacter:NSBackspaceCharacter]];
	[tableView keyDown:[self keyDownWithCharacter:NSDeleteFunctionKey]];
	XCTAssertEqual(dataSource.deleteRequests, 3u);
	XCTAssertTrue(dataSource.lastTableAskingToDelete == tableView);
}

- (void)testOtherKeysStillReachTheTable
{
	[self selectRows:[NSIndexSet indexSetWithIndex:0]];

	[tableView keyDown:[self keyDownWithCharacter:NSDownArrowFunctionKey]];
	XCTAssertEqual(dataSource.deleteRequests, 0u);
	XCTAssertEqual([tableView selectedRow], 1, @"the arrow moved the selection, as it does in any table");
}

- (void)testDeleteKeyWithADelegateThatCannotDeleteDoesNothing
{
	AIQuietTableDelegate *quiet = [[AIQuietTableDelegate alloc] init];
	quiet.rows = dataSource.rows;
	[tableView setDataSource:quiet];
	[tableView setDelegate:quiet];
	[tableView reloadData];
	[self selectRows:[NSIndexSet indexSetWithIndex:1]];

	XCTAssertNoThrow([tableView keyDown:[self keyDownWithCharacter:NSDeleteCharacter]]);
	XCTAssertEqual(quiet.deleteRequests, 0u);
	XCTAssertEqual([tableView selectedRow], 1);
}

- (void)testMenuForEventAsksTheDelegate
{
	NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown
										location:NSMakePoint(10, 10)
								   modifierFlags:0
									   timestamp:0
									windowNumber:0
										 context:nil
									 eventNumber:0
									  clickCount:1
										pressure:1];

	XCTAssertTrue([tableView menuForEvent:click] == dataSource.contextMenu);
}

@end
