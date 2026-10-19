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
#import <AIUtilities/AIMutableOwnerArray.h>

@interface AIOwnerArrayRecordingDelegate : NSObject
{
	@public
	NSMutableArray *calls;
}
@end

@implementation AIOwnerArrayRecordingDelegate
- (id)init
{
	if ((self = [super init])) calls = [NSMutableArray array];
	return self;
}
- (void)mutableOwnerArray:(AIMutableOwnerArray *)inArray didSetObject:(id)anObject withOwner:(id)inOwner priorityLevel:(float)priority
{
	[calls addObject:@[anObject ?: [NSNull null], inOwner, @(priority)]];
}
@end

@interface TestMutableOwnerArray : XCTestCase
{
	AIMutableOwnerArray *array;
}
@end

@implementation TestMutableOwnerArray

- (void)setUp
{
	[super setUp];
	array = [[AIMutableOwnerArray alloc] init];
}

- (void)tearDown
{
	array = nil;
	[super tearDown];
}

#define AIAssertPriority(actual, expected) XCTAssertEqualWithAccuracy((double)(actual), (double)(expected), AIFloatComparisonAccuracy)

#pragma mark Empty

- (void)testNewArrayIsEmpty
{
	XCTAssertEqual([array count], (NSUInteger)0);
	XCTAssertNil([array objectValue]);
	XCTAssertEqual([[array allValues] count], (NSUInteger)0);
	XCTAssertEqual([[[array objectEnumerator] allObjects] count], (NSUInteger)0);
}

- (void)testEmptyArrayHasNoNumberDateOrOwner
{
	XCTAssertNil([array numberValue]);
	XCTAssertEqual([array intValue], (NSInteger)0);
	XCTAssertEqualWithAccuracy([array doubleValue], 0.0, AIFloatComparisonAccuracy);
	XCTAssertNil([array date]);
	XCTAssertNil([array objectWithOwner:@"nobody"]);
	XCTAssertNil([array ownerWithObject:@"nothing"]);
}

- (void)testRemovingFromAnEmptyArrayIsHarmless
{
	[array setObject:nil withOwner:@"nobody"];
	XCTAssertEqual([array count], (NSUInteger)0);
}

#pragma mark Storing

- (void)testSetObjectStoresItUnderItsOwner
{
	[array setObject:@"value" withOwner:@"owner"];
	XCTAssertEqual([array count], (NSUInteger)1);
	XCTAssertEqualObjects([array objectWithOwner:@"owner"], @"value");
	XCTAssertEqualObjects([array ownerWithObject:@"value"], @"owner");
	XCTAssertEqualObjects([array objectValue], @"value");
}

- (void)testDefaultPriorityIsMedium
{
	[array setObject:@"value" withOwner:@"owner"];
	AIAssertPriority([array priorityOfObjectWithOwner:@"owner"], Medium_Priority);
	AIAssertPriority([array priorityOfObject:@"value"], Medium_Priority);
}

- (void)testPriorityIsKeptPerOwner
{
	[array setObject:@"low" withOwner:@"a" priorityLevel:Low_Priority];
	[array setObject:@"high" withOwner:@"b" priorityLevel:High_Priority];
	AIAssertPriority([array priorityOfObjectWithOwner:@"a"], Low_Priority);
	AIAssertPriority([array priorityOfObjectWithOwner:@"b"], High_Priority);
	AIAssertPriority([array priorityOfObject:@"high"], High_Priority);
}

- (void)testPriorityOutsideZeroToOneFallsBackToMedium
{
	[array setObject:@"too high" withOwner:@"a" priorityLevel:-0.5f];
	[array setObject:@"too low" withOwner:@"b" priorityLevel:2.0f];
	AIAssertPriority([array priorityOfObjectWithOwner:@"a"], Medium_Priority);
	AIAssertPriority([array priorityOfObjectWithOwner:@"b"], Medium_Priority);
}

- (void)testPriorityOfUnknownOwnerOrObjectIsZero
{
	[array setObject:@"value" withOwner:@"owner" priorityLevel:Low_Priority];
	AIAssertPriority([array priorityOfObjectWithOwner:@"stranger"], 0.0f);
	AIAssertPriority([array priorityOfObject:@"other"], 0.0f);
}

- (void)testAnOwnerHoldsOnlyItsLatestObject
{
	[array setObject:@"first" withOwner:@"owner"];
	[array setObject:@"second" withOwner:@"owner" priorityLevel:Low_Priority];
	XCTAssertEqual([array count], (NSUInteger)1);
	XCTAssertEqualObjects([array objectWithOwner:@"owner"], @"second");
	XCTAssertNil([array ownerWithObject:@"first"]);
	AIAssertPriority([array priorityOfObjectWithOwner:@"owner"], Low_Priority);
}

- (void)testDifferentOwnersMayHoldEqualObjects
{
	[array setObject:@"same" withOwner:@"a"];
	[array setObject:@"same" withOwner:@"b"];
	XCTAssertEqual([array count], (NSUInteger)2);
}

- (void)testOwnersAreMatchedByEquality
{
	[array setObject:@"value" withOwner:[NSMutableString stringWithString:@"owner"]];
	XCTAssertEqualObjects([array objectWithOwner:@"owner"], @"value");
}

#pragma mark Removing

- (void)testNilObjectRemovesTheOwnersEntry
{
	[array setObject:@"a" withOwner:@"x"];
	[array setObject:@"b" withOwner:@"y"];
	[array setObject:nil withOwner:@"x"];
	XCTAssertEqual([array count], (NSUInteger)1);
	XCTAssertNil([array objectWithOwner:@"x"]);
	XCTAssertEqualObjects([array objectValue], @"b");
}

- (void)testRemovingTheLastEntryEmptiesTheArray
{
	[array setObject:@"a" withOwner:@"x"];
	[array setObject:nil withOwner:@"x"];
	XCTAssertEqual([array count], (NSUInteger)0);
	XCTAssertNil([array objectValue]);
}

- (void)testRemovingAnUnknownOwnerChangesNothing
{
	[array setObject:@"a" withOwner:@"x"];
	[array setObject:nil withOwner:@"stranger"];
	XCTAssertEqual([array count], (NSUInteger)1);
	XCTAssertEqualObjects([array objectValue], @"a");
}

#pragma mark Object value by priority

- (void)testObjectValueIsTheHighestPriorityObject
{
	[array setObject:@"low" withOwner:@"a" priorityLevel:Low_Priority];
	[array setObject:@"high" withOwner:@"b" priorityLevel:High_Priority];
	[array setObject:@"medium" withOwner:@"c" priorityLevel:Medium_Priority];
	XCTAssertEqualObjects([array objectValue], @"high");
}

- (void)testObjectValueDoesNotDependOnInsertionOrder
{
	[array setObject:@"highest" withOwner:@"a" priorityLevel:Highest_Priority];
	[array setObject:@"lowest" withOwner:@"b" priorityLevel:Lowest_Priority];
	XCTAssertEqualObjects([array objectValue], @"highest");
}

- (void)testObjectValueFollowsAChangeOfPriority
{
	[array setObject:@"a" withOwner:@"x" priorityLevel:High_Priority];
	[array setObject:@"b" withOwner:@"y" priorityLevel:Low_Priority];
	XCTAssertEqualObjects([array objectValue], @"a");
	[array setObject:@"b2" withOwner:@"y" priorityLevel:Highest_Priority];
	XCTAssertEqualObjects([array objectValue], @"b2");
}

- (void)testObjectValueFollowsRemovalOfTheWinner
{
	[array setObject:@"a" withOwner:@"x" priorityLevel:High_Priority];
	[array setObject:@"b" withOwner:@"y" priorityLevel:Low_Priority];
	XCTAssertEqualObjects([array objectValue], @"a");
	[array setObject:nil withOwner:@"x"];
	XCTAssertEqualObjects([array objectValue], @"b");
}

#pragma mark Greatest number

- (void)testNumberValueIsTheGreatest
{
	[array setObject:@3 withOwner:@"a"];
	[array setObject:@7 withOwner:@"b"];
	[array setObject:@5 withOwner:@"c"];
	XCTAssertEqualObjects([array numberValue], @7);
}

- (void)testNumberValueIgnoresPriority
{
	[array setObject:@3 withOwner:@"a" priorityLevel:Highest_Priority];
	[array setObject:@7 withOwner:@"b" priorityLevel:Lowest_Priority];
	XCTAssertEqualObjects([array numberValue], @7);
}

- (void)testIntValueIsTheGreatest
{
	[array setObject:@3 withOwner:@"a"];
	[array setObject:@7 withOwner:@"b"];
	XCTAssertEqual([array intValue], (NSInteger)7);
}

- (void)testDoubleValueIsTheGreatest
{
	[array setObject:@0.25 withOwner:@"a"];
	[array setObject:@0.75 withOwner:@"b"];
	XCTAssertEqualWithAccuracy([array doubleValue], 0.75, AIFloatComparisonAccuracy);
}

- (void)testSingleNegativeNumberIsReturnedAsIs
{
	[array setObject:@(-5) withOwner:@"a"];
	XCTAssertEqualObjects([array numberValue], @(-5));
	XCTAssertEqual([array intValue], (NSInteger)-5);
	XCTAssertEqualWithAccuracy([array doubleValue], -5.0, AIFloatComparisonAccuracy);
}

- (void)testNumberValueOfSeveralNegativesIsTheGreatest
{
	XCTExpectFailure(@"AIMutableOwnerArray.m:132 starts the search at 0 and only accepts larger values, so several negative numbers yield an NSNumber 0 that is not even in the array");
	[array setObject:@(-5) withOwner:@"a"];
	[array setObject:@(-3) withOwner:@"b"];
	XCTAssertEqualObjects([array numberValue], @(-3));
}

- (void)testIntValueOfSeveralNegativesIsTheGreatest
{
	XCTExpectFailure(@"AIMutableOwnerArray.m:164 starts the search at 0, so several negative numbers yield 0");
	[array setObject:@(-5) withOwner:@"a"];
	[array setObject:@(-3) withOwner:@"b"];
	XCTAssertEqual([array intValue], (NSInteger)-3);
}

- (void)testDoubleValueOfSeveralNegativesIsTheGreatest
{
	XCTExpectFailure(@"AIMutableOwnerArray.m:197 starts the search at 0, so several negative numbers yield 0");
	[array setObject:@(-5.5) withOwner:@"a"];
	[array setObject:@(-3.5) withOwner:@"b"];
	XCTAssertEqualWithAccuracy([array doubleValue], -3.5, AIFloatComparisonAccuracy);
}

#pragma mark Earliest date

- (void)testDateIsTheEarliest
{
	NSDate *early = [NSDate dateWithTimeIntervalSinceReferenceDate:50];
	[array setObject:[NSDate dateWithTimeIntervalSinceReferenceDate:100] withOwner:@"a"];
	[array setObject:early withOwner:@"b"];
	[array setObject:[NSDate dateWithTimeIntervalSinceReferenceDate:200] withOwner:@"c"];
	XCTAssertEqualObjects([array date], early);
}

- (void)testSingleDateIsReturned
{
	NSDate *only = [NSDate dateWithTimeIntervalSinceReferenceDate:100];
	[array setObject:only withOwner:@"a"];
	XCTAssertEqualObjects([array date], only);
}

#pragma mark One criterion must not disturb another

- (void)testNumberValueAfterObjectValueIsStillTheGreatest
{
	XCTExpectFailure(@"AIMutableOwnerArray.m:289 shares one valueIsSortedToFront flag between the priority search and the number searches, so whichever ran first decides what the other returns");
	[array setObject:@1 withOwner:@"a" priorityLevel:Highest_Priority];
	[array setObject:@9 withOwner:@"b" priorityLevel:Low_Priority];
	XCTAssertEqualObjects([array objectValue], @1);
	XCTAssertEqualObjects([array numberValue], @9);
}

- (void)testObjectValueAfterNumberValueIsStillTheHighestPriority
{
	XCTExpectFailure(@"AIMutableOwnerArray.m:289 shares one valueIsSortedToFront flag between the priority search and the number searches, so whichever ran first decides what the other returns");
	[array setObject:@1 withOwner:@"a" priorityLevel:Highest_Priority];
	[array setObject:@9 withOwner:@"b" priorityLevel:Low_Priority];
	XCTAssertEqualObjects([array numberValue], @9);
	XCTAssertEqualObjects([array objectValue], @1);
}

- (void)testSettingAnObjectInvalidatesTheCachedWinner
{
	[array setObject:@1 withOwner:@"a"];
	[array setObject:@9 withOwner:@"b"];
	XCTAssertEqualObjects([array numberValue], @9);
	[array setObject:@20 withOwner:@"c"];
	XCTAssertEqualObjects([array numberValue], @20);
}

#pragma mark Owner by object

- (void)testOwnerWithObjectPrefersTheHighestPriorityOwner
{
	XCTExpectFailure(@"AIMutableOwnerArray.h promises the highest-priority owner when several own equal objects; AIMutableOwnerArray.m:316 returns whichever comes first in storage order");
	[array setObject:@"x" withOwner:@"low" priorityLevel:Low_Priority];
	[array setObject:@"x" withOwner:@"high" priorityLevel:High_Priority];
	XCTAssertEqualObjects([array ownerWithObject:@"x"], @"high");
}

#pragma mark Enumeration

- (void)testAllValuesListsEveryObject
{
	[array setObject:@"a" withOwner:@"x"];
	[array setObject:@"b" withOwner:@"y"];
	[array setObject:@"c" withOwner:@"z"];
	XCTAssertEqualObjects([NSSet setWithArray:[array allValues]], ([NSSet setWithObjects:@"a", @"b", @"c", nil]));
}

- (void)testObjectEnumeratorListsEveryObject
{
	[array setObject:@"a" withOwner:@"x"];
	[array setObject:@"b" withOwner:@"y"];
	XCTAssertEqualObjects([NSSet setWithArray:[[array objectEnumerator] allObjects]], ([NSSet setWithObjects:@"a", @"b", nil]));
}

- (void)testFastEnumerationVisitsEveryObjectOnce
{
	[array setObject:@"a" withOwner:@"x"];
	[array setObject:@"b" withOwner:@"y"];
	NSMutableArray *seen = [NSMutableArray array];
	for (id object in array) [seen addObject:object];
	XCTAssertEqual([seen count], (NSUInteger)2);
	XCTAssertEqualObjects([NSSet setWithArray:seen], ([NSSet setWithObjects:@"a", @"b", nil]));
}

- (void)testFastEnumerationOfAnEmptyArrayVisitsNothing
{
	NSUInteger visits = 0;
	for (id object in array) { (void)object; visits++; }
	XCTAssertEqual(visits, (NSUInteger)0);
}

#pragma mark Delegate

- (void)testDelegateIsToldOfEachSet
{
	AIOwnerArrayRecordingDelegate *delegate = [[AIOwnerArrayRecordingDelegate alloc] init];
	array.delegate = delegate;
	XCTAssertTrue(array.delegate == delegate);
	[array setObject:@"a" withOwner:@"x" priorityLevel:Low_Priority];
	XCTAssertEqual([delegate->calls count], (NSUInteger)1);
	NSArray *call = [delegate->calls firstObject];
	XCTAssertEqualObjects(call[0], @"a");
	XCTAssertEqualObjects(call[1], @"x");
	AIAssertPriority([call[2] floatValue], Low_Priority);
	array.delegate = nil;
}

- (void)testDelegateIsToldOfARemoval
{
	AIOwnerArrayRecordingDelegate *delegate = [[AIOwnerArrayRecordingDelegate alloc] init];
	[array setObject:@"a" withOwner:@"x"];
	array.delegate = delegate;
	[array setObject:nil withOwner:@"x"];
	XCTAssertEqual([delegate->calls count], (NSUInteger)1);
	XCTAssertEqualObjects([delegate->calls firstObject][0], [NSNull null]);
	XCTAssertEqualObjects([delegate->calls firstObject][1], @"x");
	array.delegate = nil;
}

- (void)testDelegateWithoutTheMethodIsLeftAlone
{
	NSObject *delegate = [[NSObject alloc] init];
	array.delegate = delegate;
	[array setObject:@"a" withOwner:@"x"];
	XCTAssertEqualObjects([array objectValue], @"a");
	array.delegate = nil;
}

@end
