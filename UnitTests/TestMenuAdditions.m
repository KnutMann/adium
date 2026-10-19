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

#import <AIUtilities/AIMenuAdditions.h>

@interface TestMenuAdditions : XCTestCase
@end

@implementation TestMenuAdditions

- (NSMenu *)menuWithTitles:(NSArray<NSString *> *)titles
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Test"];
	[menu setAutoenablesItems:NO];
	for (NSString *title in titles) {
		[menu addItemWithTitle:title action:NULL keyEquivalent:@""];
	}
	return menu;
}

- (NSArray<NSString *> *)titlesOf:(NSMenu *)menu
{
	return [[menu itemArray] valueForKey:@"title"];
}

#pragma mark Adding items

- (void)testAddItemWithTitleTargetActionKeyEquivalentAppendsAConfiguredItem
{
	NSMenu *menu = [self menuWithTitles:@[@"First"]];

	NSMenuItem *item = [menu addItemWithTitle:@"Second" target:self action:@selector(description) keyEquivalent:@"s"];
	XCTAssertEqual([menu numberOfItems], 2);
	XCTAssertTrue([menu itemAtIndex:1] == item);
	XCTAssertEqualObjects([item title], @"Second");
	XCTAssertTrue([item target] == self);
	XCTAssertTrue([item action] == @selector(description));
	XCTAssertEqualObjects([item keyEquivalent], @"s");
}

- (void)testAddItemWithTagSetsTheTag
{
	NSMenu *menu = [self menuWithTitles:@[]];

	NSMenuItem *item = [menu addItemWithTitle:@"Tagged" target:nil action:NULL keyEquivalent:@"" tag:42];
	XCTAssertEqual([item tag], 42);
	XCTAssertTrue([menu itemWithTag:42] == item);
}

- (void)testAddItemWithRepresentedObjectSetsIt
{
	NSMenu *menu = [self menuWithTitles:@[]];
	NSObject *represented = [[NSObject alloc] init];

	NSMenuItem *item = [menu addItemWithTitle:@"Represents" target:nil action:NULL keyEquivalent:@"" representedObject:represented];
	XCTAssertTrue([item representedObject] == represented);
	XCTAssertTrue([menu itemAtIndex:0] == item);
}

#pragma mark Removing items

- (void)testRemoveAllItemsButFirstKeepsOnlyTheFirst
{
	NSMenu *menu = [self menuWithTitles:@[@"A", @"B", @"C"]];
	NSMenuItem *first = [menu itemAtIndex:0];

	[menu removeAllItemsButFirst];
	XCTAssertEqual([menu numberOfItems], 1);
	XCTAssertTrue([menu itemAtIndex:0] == first);
}

- (void)testRemoveAllItemsButFirstLeavesAnEmptyOrSingleItemMenuAlone
{
	NSMenu *empty = [self menuWithTitles:@[]];
	NSMenu *single = [self menuWithTitles:@[@"Only"]];

	[empty removeAllItemsButFirst];
	[single removeAllItemsButFirst];
	XCTAssertEqual([empty numberOfItems], 0);
	XCTAssertEqualObjects([self titlesOf:single], @[@"Only"]);
}

- (void)testRemoveAllItemsAfterIndexKeepsTheItemsUpToAndIncludingIt
{
	NSMenu *menu = [self menuWithTitles:@[@"A", @"B", @"C", @"D", @"E"]];

	[menu removeAllItemsAfterIndex:1];
	XCTAssertEqualObjects([self titlesOf:menu], (@[@"A", @"B"]));
}

- (void)testRemoveAllItemsAfterTheLastIndexRemovesNothing
{
	NSMenu *menu = [self menuWithTitles:@[@"A", @"B"]];

	[menu removeAllItemsAfterIndex:1];
	XCTAssertEqualObjects([self titlesOf:menu], (@[@"A", @"B"]));
}

- (void)testRemoveAllItemsAfterAnIndexBeyondTheEndIsRefused
{
	NSMenu *menu = [self menuWithTitles:@[@"A"]];

	XCTAssertThrows([menu removeAllItemsAfterIndex:3]);
}

#pragma mark Creating items

- (void)testMenuItemInitWithTargetSetsTitleTargetActionAndKey
{
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Do" target:self action:@selector(description) keyEquivalent:@"d"];

	XCTAssertEqualObjects([item title], @"Do");
	XCTAssertTrue([item target] == self);
	XCTAssertTrue([item action] == @selector(description));
	XCTAssertEqualObjects([item keyEquivalent], @"d");
}

- (void)testMenuItemInitWithNilTitleGetsAnEmptyTitle
{
	XCTAssertEqualObjects([[[NSMenuItem alloc] initWithTitle:nil target:nil action:NULL keyEquivalent:@""] title], @"");
	XCTAssertEqualObjects([[[NSMenuItem alloc] initWithTitle:nil target:nil action:NULL keyEquivalent:@"" representedObject:nil] title], @"");
	XCTAssertEqualObjects([[[NSMenuItem alloc] initWithTitle:nil target:nil action:NULL keyEquivalent:@"" keyMask:0] title], @"");
}

- (void)testMenuItemInitWithKeyMaskSetsTheModifiers
{
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Shifted"
												  target:self
												  action:@selector(description)
										   keyEquivalent:@"s"
												 keyMask:(NSEventModifierFlagCommand | NSEventModifierFlagShift)];

	XCTAssertEqual([item keyEquivalentModifierMask], (NSEventModifierFlags)(NSEventModifierFlagCommand | NSEventModifierFlagShift));
	XCTAssertEqualObjects([item keyEquivalent], @"s");
}

- (void)testMenuItemInitWithRepresentedObjectSetsIt
{
	NSObject *represented = [[NSObject alloc] init];

	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"R" target:self action:NULL keyEquivalent:@"" representedObject:represented];
	XCTAssertTrue([item representedObject] == represented);
	XCTAssertTrue([item target] == self);
}

- (void)testRemoveKeyEquivalentClearsTheKeyAndLeavesTheItemWhereItWas
{
	NSMenu *menu = [self menuWithTitles:@[@"A", @"C"]];
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"B" target:nil action:NULL keyEquivalent:@"b"];
	[menu insertItem:item atIndex:1];

	[item removeKeyEquivalent];
	XCTAssertEqualObjects([item keyEquivalent], @"");
	XCTAssertEqual([menu indexOfItem:item], 1);
	XCTAssertTrue([item menu] == menu);
	XCTAssertEqualObjects([self titlesOf:menu], (@[@"A", @"B", @"C"]));
}

- (void)testRemoveKeyEquivalentWorksForAnItemOutsideAnyMenu
{
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Loose" target:nil action:NULL keyEquivalent:@"l"];

	[item removeKeyEquivalent];
	XCTAssertEqualObjects([item keyEquivalent], @"");
	XCTAssertNil([item menu]);
}

- (void)testTitleCompareOrdersNumericallyAndIgnoresCase
{
	NSMenuItem *two = [[NSMenuItem alloc] initWithTitle:@"Item 2" action:NULL keyEquivalent:@""];
	NSMenuItem *ten = [[NSMenuItem alloc] initWithTitle:@"item 10" action:NULL keyEquivalent:@""];
	NSMenuItem *lower = [[NSMenuItem alloc] initWithTitle:@"abc" action:NULL keyEquivalent:@""];
	NSMenuItem *upper = [[NSMenuItem alloc] initWithTitle:@"ABC" action:NULL keyEquivalent:@""];

	XCTAssertEqual([two titleCompare:ten], NSOrderedAscending);
	XCTAssertEqual([ten titleCompare:two], NSOrderedDescending);
	XCTAssertEqual([lower titleCompare:upper], NSOrderedSame);
}

#pragma mark Whole menus

- (void)testSetAllMenuItemsToStateReachesEveryItem
{
	NSMenu *menu = [self menuWithTitles:@[@"A", @"B", @"C"]];
	[[menu itemAtIndex:1] setState:NSControlStateValueOn];

	[menu setAllMenuItemsToState:NSControlStateValueMixed];
	for (NSMenuItem *item in [menu itemArray]) {
		XCTAssertEqual([item state], NSControlStateValueMixed, @"%@", [item title]);
	}

	[menu setAllMenuItemsToState:NSControlStateValueOff];
	for (NSMenuItem *item in [menu itemArray]) {
		XCTAssertEqual([item state], NSControlStateValueOff, @"%@", [item title]);
	}
}

- (void)testSetAllMenuItemsToStateOnAnEmptyMenuIsHarmless
{
	XCTAssertNoThrow([[self menuWithTitles:@[]] setAllMenuItemsToState:NSControlStateValueOn]);
}

- (void)testFirstEnabledMenuItemSkipsDisabledItems
{
	NSMenu *menu = [self menuWithTitles:@[@"A", @"B", @"C"]];
	[[menu itemAtIndex:0] setEnabled:NO];

	XCTAssertTrue([menu firstEnabledMenuItem] == [menu itemAtIndex:1]);
}

- (void)testFirstEnabledMenuItemIsNilWhenNothingIsEnabled
{
	NSMenu *menu = [self menuWithTitles:@[@"A", @"B"]];
	for (NSMenuItem *item in [menu itemArray]) [item setEnabled:NO];

	XCTAssertNil([menu firstEnabledMenuItem]);
	XCTAssertNil([[self menuWithTitles:@[]] firstEnabledMenuItem]);
}

#pragma mark Swapping

- (void)testSwapMenuItemWithItselfChangesNothing
{
	NSMenu *menu = [self menuWithTitles:@[@"A", @"B"]];

	[NSMenu swapMenuItem:[menu itemAtIndex:0] with:[menu itemAtIndex:0]];
	XCTAssertEqualObjects([self titlesOf:menu], (@[@"A", @"B"]));
}

- (void)testSwapMenuItemExchangesTwoItemsOfOneMenu
{
	NSMenu *menu = [self menuWithTitles:@[@"A", @"X", @"B", @"Y"]];
	NSMenuItem *a = [menu itemAtIndex:0];
	NSMenuItem *b = [menu itemAtIndex:2];

	[NSMenu swapMenuItem:a with:b];
	XCTAssertEqualObjects([self titlesOf:menu], (@[@"B", @"X", @"A", @"Y"]));
	XCTAssertTrue([menu itemAtIndex:0] == b);
	XCTAssertTrue([menu itemAtIndex:2] == a);
}

- (void)testSwapMenuItemExchangesTwoItemsOfOneMenuGivenInTheOtherOrder
{
	NSMenu *menu = [self menuWithTitles:@[@"X", @"B", @"Y", @"A"]];
	NSMenuItem *a = [menu itemAtIndex:3];
	NSMenuItem *b = [menu itemAtIndex:1];

	@try {
		[NSMenu swapMenuItem:a with:b];
	} @catch (NSException *exception) {
		XCTFail(@"raised %@: %@", [exception name], [exception reason]);
	}
	XCTAssertEqualObjects([self titlesOf:menu], (@[@"X", @"A", @"Y", @"B"]));
}

- (void)testSwapMenuItemExchangesItemsAcrossTwoMenus
{
	NSMenu *one = [self menuWithTitles:@[@"A", @"P"]];
	NSMenu *two = [self menuWithTitles:@[@"Q", @"B"]];
	NSMenuItem *a = [one itemAtIndex:0];
	NSMenuItem *b = [two itemAtIndex:1];

	@try {
		[NSMenu swapMenuItem:a with:b];
	} @catch (NSException *exception) {
		XCTFail(@"raised %@: %@", [exception name], [exception reason]);
	}
	XCTAssertEqualObjects([self titlesOf:one], (@[@"B", @"P"]));
	XCTAssertEqualObjects([self titlesOf:two], (@[@"Q", @"A"]));
}

- (void)testUpdateAlternateMenuItemKeepsBothItemsWhereTheyWere
{
	NSMenu *menu = [self menuWithTitles:@[@"Before", @"Primary", @"Alternate", @"After"]];
	NSMenuItem *primary = [menu itemAtIndex:1];
	NSMenuItem *alternate = [menu itemAtIndex:2];
	[alternate setAlternate:YES];
	[alternate setKeyEquivalentModifierMask:NSEventModifierFlagOption];

	[NSMenu updateAlternateMenuItem:alternate];
	XCTAssertEqual([menu numberOfItems], 4);
	XCTAssertTrue([menu itemAtIndex:1] == primary);
	XCTAssertTrue([menu itemAtIndex:2] == alternate);
	XCTAssertTrue([alternate isAlternate]);
	XCTAssertEqualObjects([self titlesOf:menu], (@[@"Before", @"Primary", @"Alternate", @"After"]));
}

@end
