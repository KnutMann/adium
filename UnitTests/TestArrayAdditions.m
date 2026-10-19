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
#import <AIUtilities/AIArrayAdditions.h>

@interface TestArrayAdditions : XCTestCase
@end

@implementation TestArrayAdditions

#pragma mark containsObjectIdenticalTo:

- (void)testContainsObjectIdenticalToFindsTheSameInstance
{
	NSMutableString *member = [NSMutableString stringWithString:@"a"];
	NSArray *array = @[member, @"b"];
	XCTAssertTrue([array containsObjectIdenticalTo:member]);
}

- (void)testContainsObjectIdenticalToRejectsAnEqualButDistinctInstance
{
	NSArray *array = @[[NSMutableString stringWithString:@"a"]];
	XCTAssertTrue([array containsObject:@"a"], @"The two strings are equal, so containsObject: finds it");
	XCTAssertFalse([array containsObjectIdenticalTo:[NSMutableString stringWithString:@"a"]]);
}

- (void)testEmptyArrayContainsNothingIdentical
{
	XCTAssertFalse([@[] containsObjectIdenticalTo:@"a"]);
}

#pragma mark arrayNamed:forClass:

- (void)testArrayNamedWithoutSuchResourceIsNil
{
	XCTAssertNil([NSArray arrayNamed:@"NoSuchArrayResource" forClass:[self class]]);
}

#pragma mark compare:

- (void)testEqualArraysCompareTheSame
{
	XCTAssertEqual(([@[@"a", @"b"] compare:@[@"a", @"b"]]), NSOrderedSame);
}

- (void)testTwoEmptyArraysCompareTheSame
{
	XCTAssertEqual(([@[] compare:@[]]), NSOrderedSame);
}

- (void)testFirstDifferingElementDecides
{
	XCTAssertEqual(([@[@"a", @"b"] compare:@[@"a", @"c"]]), NSOrderedAscending);
	XCTAssertEqual(([@[@"a", @"c"] compare:@[@"a", @"b"]]), NSOrderedDescending);
	XCTAssertEqual(([@[@"b", @"a"] compare:@[@"a", @"z"]]), NSOrderedDescending, @"Later elements do not matter once an earlier one differs");
}

- (void)testAPrefixSortsBeforeTheLongerArray
{
	XCTAssertEqual(([@[@"a"] compare:@[@"a", @"b"]]), NSOrderedAscending);
	XCTAssertEqual(([@[@"a", @"b"] compare:@[@"a"]]), NSOrderedDescending);
}

- (void)testEmptyArraySortsBeforeAnyOther
{
	XCTAssertEqual(([@[] compare:@[@"a"]]), NSOrderedAscending);
	XCTAssertEqual(([@[@"a"] compare:@[]]), NSOrderedDescending);
}

- (void)testCompareUsesTheElementsOwnOrdering
{
	XCTAssertEqual(([@[@2] compare:@[@10]]), NSOrderedAscending, @"Numbers compare numerically, not as text");
}

#pragma mark validateAsPropertyList

- (void)testArrayOfPropertyListTypesValidates
{
	NSArray *array = @[@"s", @1, [NSDate dateWithTimeIntervalSinceReferenceDate:0], [NSData data], @[@"nested"], @{@"k": @"v"}];
	XCTAssertTrue([array validateAsPropertyList]);
}

- (void)testEmptyArrayValidates
{
	XCTAssertTrue([@[] validateAsPropertyList]);
}

- (void)testArrayWithNullFailsValidation
{
	XCTAssertFalse(([@[@"s", [NSNull null]] validateAsPropertyList]));
}

- (void)testArrayWithInvalidNestedDictionaryFailsValidation
{
	XCTAssertFalse([@[@{@"k": [NSNull null]}] validateAsPropertyList]);
}

- (void)testArrayWithInvalidNestedArrayFailsValidation
{
	XCTAssertFalse([@[@[@[[NSNull null]]]] validateAsPropertyList]);
}

#pragma mark addObjectsFromArrayIgnoringDuplicates:

- (void)testAddingIgnoringDuplicatesSkipsObjectsAlreadyPresent
{
	NSMutableArray *array = [@[@"a", @"b"] mutableCopy];
	[array addObjectsFromArrayIgnoringDuplicates:@[@"b", @"c"]];
	XCTAssertEqualObjects(array, (@[@"a", @"b", @"c"]));
}

- (void)testAddingIgnoringDuplicatesSkipsRepeatsWithinTheInput
{
	NSMutableArray *array = [NSMutableArray array];
	[array addObjectsFromArrayIgnoringDuplicates:@[@"a", @"a", @"b", @"a"]];
	XCTAssertEqualObjects(array, (@[@"a", @"b"]));
}

- (void)testAddingIgnoringDuplicatesPreservesInputOrder
{
	NSMutableArray *array = [NSMutableArray array];
	[array addObjectsFromArrayIgnoringDuplicates:@[@"c", @"a", @"b"]];
	XCTAssertEqualObjects(array, (@[@"c", @"a", @"b"]));
}

- (void)testAddingNothingIgnoringDuplicatesChangesNothing
{
	NSMutableArray *array = [@[@"a"] mutableCopy];
	[array addObjectsFromArrayIgnoringDuplicates:@[]];
	[array addObjectsFromArrayIgnoringDuplicates:nil];
	XCTAssertEqualObjects(array, @[@"a"]);
}

#pragma mark moveObject:toIndex:

/* The index names a slot in the array as it is before the move, the way a drop index does: every
 * caller feeds it one (a sort controller's indexForInserting:, a tab or account drop row). So a
 * move backwards lands at the index, and a move forwards lands just before the object that was at
 * the index, which is one less. */
- (void)testMovingBackwardsLandsAtTheIndex
{
	NSMutableArray *array = [@[@"a", @"b", @"c", @"d"] mutableCopy];
	[array moveObject:@"d" toIndex:1];
	XCTAssertEqualObjects(array, (@[@"a", @"d", @"b", @"c"]));
}

- (void)testMovingForwardsLandsBeforeTheObjectThatWasAtTheIndex
{
	NSMutableArray *array = [@[@"a", @"b", @"c", @"d"] mutableCopy];
	[array moveObject:@"a" toIndex:2];
	XCTAssertEqualObjects(array, (@[@"b", @"a", @"c", @"d"]));
}

- (void)testMovingToTheCountAppends
{
	NSMutableArray *array = [@[@"a", @"b", @"c", @"d"] mutableCopy];
	[array moveObject:@"b" toIndex:4];
	XCTAssertEqualObjects(array, (@[@"a", @"c", @"d", @"b"]));
}

- (void)testMovingToTheFrontPrepends
{
	NSMutableArray *array = [@[@"a", @"b", @"c", @"d"] mutableCopy];
	[array moveObject:@"c" toIndex:0];
	XCTAssertEqualObjects(array, (@[@"c", @"a", @"b", @"d"]));
}

- (void)testMovingToItsOwnIndexChangesNothing
{
	NSMutableArray *array = [@[@"a", @"b", @"c", @"d"] mutableCopy];
	[array moveObject:@"c" toIndex:2];
	XCTAssertEqualObjects(array, (@[@"a", @"b", @"c", @"d"]));
}

- (void)testMovingKeepsTheCount
{
	NSMutableArray *array = [@[@"a", @"b", @"c", @"d"] mutableCopy];
	[array moveObject:@"a" toIndex:3];
	XCTAssertEqual([array count], (NSUInteger)4);
}

@end
