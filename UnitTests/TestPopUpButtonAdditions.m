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

#import <AIUtilities/AIPopUpButtonAdditions.h>

@interface TestPopUpButtonAdditions : XCTestCase
@end

@implementation TestPopUpButtonAdditions

- (NSPopUpButton *)buttonWithRepresentedObjects:(NSArray *)objects
{
	NSPopUpButton *button = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 22) pullsDown:NO];
	for (id object in objects) {
		[button addItemWithTitle:[NSString stringWithFormat:@"Item %@", object]];
		if (object != [NSNull null]) [[button lastItem] setRepresentedObject:object];
	}
	return button;
}

#pragma mark By equality

- (void)testSelectItemWithRepresentedObjectSelectsTheMatchingItem
{
	NSPopUpButton *button = [self buttonWithRepresentedObjects:@[@"one", @"two", @"three"]];

	XCTAssertTrue([button selectItemWithRepresentedObject:@"two"]);
	XCTAssertEqual([button indexOfSelectedItem], 1);
	XCTAssertEqualObjects([[button selectedItem] representedObject], @"two");
}

- (void)testSelectItemWithRepresentedObjectMatchesByEqualityNotIdentity
{
	NSPopUpButton *button = [self buttonWithRepresentedObjects:@[@10, @20]];

	XCTAssertTrue([button selectItemWithRepresentedObject:[NSNumber numberWithInt:20]]);
	XCTAssertEqual([button indexOfSelectedItem], 1);
}

- (void)testSelectItemWithRepresentedObjectLeavesTheSelectionAloneWhenNothingMatches
{
	NSPopUpButton *button = [self buttonWithRepresentedObjects:@[@"one", @"two"]];
	[button selectItemAtIndex:1];

	XCTAssertFalse([button selectItemWithRepresentedObject:@"nine"]);
	XCTAssertEqual([button indexOfSelectedItem], 1);
}

- (void)testSelectItemWithRepresentedObjectOnAnEmptyButtonIsNo
{
	NSPopUpButton *button = [self buttonWithRepresentedObjects:@[]];

	XCTAssertFalse([button selectItemWithRepresentedObject:@"one"]);
}

#pragma mark By compare:

- (void)testSelectItemWithRepresentedObjectUsingCompareSelectsTheItemThatComparesEqual
{
	NSPopUpButton *button = [self buttonWithRepresentedObjects:@[@10, @20, @30]];

	XCTAssertTrue([button selectItemWithRepresentedObjectUsingCompare:@30]);
	XCTAssertEqual([button indexOfSelectedItem], 2);

	XCTAssertTrue([button selectItemWithRepresentedObjectUsingCompare:[NSNumber numberWithDouble:10.0]]);
	XCTAssertEqual([button indexOfSelectedItem], 0);
}

- (void)testSelectItemWithRepresentedObjectUsingCompareIsNoWhenNothingComparesEqual
{
	NSPopUpButton *button = [self buttonWithRepresentedObjects:@[@10, @20]];
	[button selectItemAtIndex:1];

	XCTAssertFalse([button selectItemWithRepresentedObjectUsingCompare:@25]);
	XCTAssertEqual([button indexOfSelectedItem], 1);
}

- (void)testSelectItemWithRepresentedObjectUsingCompareOnAnEmptyButtonIsNo
{
	XCTAssertFalse([[self buttonWithRepresentedObjects:@[]] selectItemWithRepresentedObjectUsingCompare:@1]);
}

- (void)testSelectItemWithRepresentedObjectUsingCompareDoesNotMatchAnItemWithoutARepresentedObject
{
	XCTExpectFailure(@"selectItemWithRepresentedObjectUsingCompare: (AIPopUpButtonAdditions.m) sends compare: to a nil represented object, and nil answers 0, which is NSOrderedSame: the first item without a represented object matches whatever is asked for");
	NSPopUpButton *button = [self buttonWithRepresentedObjects:@[[NSNull null], @"b"]];

	XCTAssertTrue([button selectItemWithRepresentedObjectUsingCompare:@"b"]);
	XCTAssertEqual([button indexOfSelectedItem], 1);
}

#pragma mark The cell

- (void)testCellSelectItemWithRepresentedObjectSelectsTheMatchingItem
{
	NSPopUpButton *button = [self buttonWithRepresentedObjects:@[@"one", @"two"]];

	XCTAssertTrue([[button cell] selectItemWithRepresentedObject:@"two"]);
	XCTAssertEqual([button indexOfSelectedItem], 1);
}

- (void)testCellSelectItemWithRepresentedObjectLeavesTheSelectionAloneWhenNothingMatches
{
	XCTExpectFailure(@"-[NSPopUpButtonCell(AIPopUpButtonAdditions) selectItemWithRepresentedObject:] (AIPopUpButtonAdditions.m, last method) tests the index against NSNotFound while indexOfItemWithRepresentedObject: answers -1, so a miss selects index -1, clearing the selection, and reports YES");
	NSPopUpButton *button = [self buttonWithRepresentedObjects:@[@"one", @"two"]];
	[button selectItemAtIndex:1];

	XCTAssertFalse([[button cell] selectItemWithRepresentedObject:@"nine"]);
	XCTAssertEqual([button indexOfSelectedItem], 1);
}

#pragma mark Layout

- (void)testAutosizeAndCenterHorizontallyCentresTheButtonInItsSuperview
{
	NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
	NSPopUpButton *button = [self buttonWithRepresentedObjects:@[@"one"]];
	[container addSubview:button];

	[button autosizeAndCenterHorizontally];
	XCTAssertEqualWithAccuracy(NSMidX([button frame]), 150, 0.5);
	XCTAssertLessThan(NSWidth([button frame]), 300);
	XCTAssertGreaterThan(NSWidth([button frame]), 0);
}

- (void)testAutosizeAndCenterHorizontallyWithoutATitleLeavesTheFrameAlone
{
	NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
	NSPopUpButton *button = [self buttonWithRepresentedObjects:@[]];
	[button setFrame:NSMakeRect(7, 3, 100, 22)];
	[container addSubview:button];

	[button autosizeAndCenterHorizontally];
	XCTAssertTrue(NSEqualRects([button frame], NSMakeRect(7, 3, 100, 22)), @"%@", NSStringFromRect([button frame]));
}

@end
