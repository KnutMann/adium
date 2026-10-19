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

#import <AIUtilities/AIOutlineViewAdditions.h>

@interface TestOutlineViewAdditions : XCTestCase
@end

/* A tree of strings: the roots and, under one of them, two children. */
@interface AIOutlineTestDataSource : NSObject <NSOutlineViewDataSource>
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSString *> *> *children;
@end

@implementation AIOutlineTestDataSource

- (NSArray<NSString *> *)childrenOf:(id)item
{
	return self.children[item ?: @"root"] ?: @[];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	return (NSInteger)[[self childrenOf:item] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	return [self childrenOf:item][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [[self childrenOf:item] count] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	return item;
}

@end

/* Off screen nothing is ever displayed, so what a redisplay asks for is recorded as it is asked. */
@interface AIRecordingOutlineView : NSOutlineView
@property (nonatomic, strong) NSMutableArray<NSValue *> *invalidatedRects;
@property (nonatomic, assign) NSUInteger wholeViewInvalidations;
@end

@implementation AIRecordingOutlineView

- (void)setNeedsDisplayInRect:(NSRect)rect
{
	[self.invalidatedRects addObject:[NSValue valueWithRect:rect]];
	[super setNeedsDisplayInRect:rect];
}

- (void)setNeedsDisplay:(BOOL)flag
{
	if (flag) self.wholeViewInvalidations++;
	[super setNeedsDisplay:flag];
}

- (void)forget
{
	[self.invalidatedRects removeAllObjects];
	self.wholeViewInvalidations = 0;
}

@end

@implementation TestOutlineViewAdditions {
	AIRecordingOutlineView		*outlineView;
	AIOutlineTestDataSource		*dataSource;
}

- (void)setUp
{
	[super setUp];
	outlineView = [[AIRecordingOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
	outlineView.invalidatedRects = [NSMutableArray array];
	NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	[outlineView addTableColumn:column];
	[outlineView setOutlineTableColumn:column];
	[outlineView setAllowsMultipleSelection:YES];
	dataSource = [[AIOutlineTestDataSource alloc] init];
	dataSource.children = @{ @"root": @[@"A", @"B", @"C"], @"B": @[@"B1", @"B2"], @"C": @[@"C1"] };
	[outlineView setDataSource:dataSource];
	[outlineView reloadData];
	[outlineView expandItem:@"B"];
	//Rows are now A, B, B1, B2, C; C1 is folded away
}

#pragma mark Reading the selection

- (void)testFirstSelectedItemIsNilWithoutASelection
{
	[outlineView deselectAll:nil];

	XCTAssertNil([outlineView firstSelectedItem]);
}

- (void)testFirstSelectedItemIsTheSelectedItem
{
	[outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:3] byExtendingSelection:NO];

	XCTAssertEqualObjects([outlineView firstSelectedItem], @"B2");
}

- (void)testFirstSelectedItemIsTheItemOfTheFirstSelectedRow
{
	XCTExpectFailure(@"firstSelectedItem (AIOutlineViewAdditions.m, first method) reads selectedRow, which NSTableView documents as the last selected row, so with rows 1 and 3 selected it answers row 3's item instead of row 1's");
	NSMutableIndexSet *rows = [NSMutableIndexSet indexSetWithIndex:3];
	[rows addIndex:1];
	[outlineView selectRowIndexes:rows byExtendingSelection:NO];

	XCTAssertEqualObjects([outlineView firstSelectedItem], @"B");
}

- (void)testArrayOfSelectedItemsListsEverySelectedItemInRowOrder
{
	NSMutableIndexSet *rows = [NSMutableIndexSet indexSetWithIndex:4];
	[rows addIndex:0];
	[rows addIndex:2];
	[outlineView selectRowIndexes:rows byExtendingSelection:NO];

	XCTAssertEqualObjects([outlineView arrayOfSelectedItems], (@[@"A", @"B1", @"C"]));
}

- (void)testArrayOfSelectedItemsIsEmptyWithoutASelection
{
	[outlineView deselectAll:nil];

	XCTAssertEqualObjects([outlineView arrayOfSelectedItems], @[]);
}

#pragma mark Setting the selection

- (void)testSelectItemsInArraySelectsExactlyThoseItems
{
	[outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

	[outlineView selectItemsInArray:@[@"B2", @"C"]];
	NSMutableIndexSet *expected = [NSMutableIndexSet indexSetWithIndex:3];
	[expected addIndex:4];
	XCTAssertEqualObjects([outlineView selectedRowIndexes], expected);
	XCTAssertEqualObjects([outlineView arrayOfSelectedItems], (@[@"B2", @"C"]));
}

- (void)testSelectItemsInArrayIgnoresItemsThatAreNotShown
{
	[outlineView selectItemsInArray:@[@"A", @"C1", @"nowhere"]];

	XCTAssertEqualObjects([outlineView selectedRowIndexes], [NSIndexSet indexSetWithIndex:0]);
}

- (void)testSelectItemsInArrayWithNothingClearsTheSelection
{
	[outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];

	[outlineView selectItemsInArray:@[]];
	XCTAssertEqual([outlineView numberOfSelectedRows], 0);
}

#pragma mark Redisplaying

- (void)testRedisplayItemMarksThatRowDirty
{
	NSRect rowRect = [outlineView rectOfRow:[outlineView rowForItem:@"B1"]];
	[outlineView forget];

	[outlineView redisplayItem:@"B1"];
	XCTAssertTrue([outlineView.invalidatedRects containsObject:[NSValue valueWithRect:rowRect]], @"%@", outlineView.invalidatedRects);
	XCTAssertEqual(outlineView.wholeViewInvalidations, 0u);
}

- (void)testRedisplayItemWithNilMarksTheWholeView
{
	[outlineView forget];

	[outlineView redisplayItem:nil];
	XCTAssertGreaterThan(outlineView.wholeViewInvalidations, 0u);
}

- (void)testRedisplayItemThatIsNotShownMarksNothing
{
	[outlineView forget];

	[outlineView redisplayItem:@"C1"];
	[outlineView redisplayItem:@"nowhere"];
	XCTAssertEqual([outlineView.invalidatedRects count], 0u, @"%@", outlineView.invalidatedRects);
	XCTAssertEqual(outlineView.wholeViewInvalidations, 0u);
}

@end
