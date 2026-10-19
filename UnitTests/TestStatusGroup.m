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
#import <Adium/AIStatus.h>
#import <Adium/AIStatusGroup.h>

static AIStatus *TSGStatus(NSString *title, AIStatusType type, AIStatusMutabilityType mutability)
{
	AIStatus *status = [AIStatus status];
	[status setTitle:title];
	[status setStatusType:type];
	[status setMutabilityType:mutability];
	return status;
}

/* The sort reads the original order from its context, so it must be a copy taken before sorting. */
static NSArray *TSGTitlesAfterSorting(NSArray *statuses)
{
	NSMutableArray *array = [statuses mutableCopy];
	NSArray *original = [statuses copy];
	[AIStatusGroup sortArrayOfStatusItems:array context:(__bridge void *)original];
	return [array valueForKey:@"title"];
}

@interface TestStatusGroup : XCTestCase
@end

@implementation TestStatusGroup

#pragma mark Contents

- (void)testNewGroupIsEmpty
{
	AIStatusGroup *group = [AIStatusGroup statusGroup];
	XCTAssertEqualObjects(group.containedStatusItems, @[]);
	XCTAssertEqualObjects(group.flatStatusSet, [NSSet set]);
}

- (void)testAddingAtTheEndAppends
{
	AIStatusGroup *group = [AIStatusGroup statusGroup];
	AIStatus *first = TSGStatus(@"first", AIAwayStatusType, AIEditableStatusState);
	AIStatus *second = TSGStatus(@"second", AIAwayStatusType, AIEditableStatusState);
	AIStatus *third = TSGStatus(@"third", AIAwayStatusType, AIEditableStatusState);

	[group addStatusItem:first atIndex:NSNotFound];
	[group addStatusItem:second atIndex:NSNotFound];
	[group addStatusItem:third atIndex:99];

	NSArray *expected = @[first, second, third];
	XCTAssertEqualObjects(group.containedStatusItems, expected);
}

- (void)testAddingAtAnIndexInserts
{
	AIStatusGroup *group = [AIStatusGroup statusGroup];
	AIStatus *first = TSGStatus(@"first", AIAwayStatusType, AIEditableStatusState);
	AIStatus *second = TSGStatus(@"second", AIAwayStatusType, AIEditableStatusState);
	AIStatus *between = TSGStatus(@"between", AIAwayStatusType, AIEditableStatusState);

	[group addStatusItem:first atIndex:NSNotFound];
	[group addStatusItem:second atIndex:NSNotFound];
	[group addStatusItem:between atIndex:1];

	NSArray *expected = @[first, between, second];
	XCTAssertEqualObjects(group.containedStatusItems, expected);
}

- (void)testAddingSetsTheContainingGroup
{
	AIStatusGroup *group = [AIStatusGroup statusGroup];
	AIStatus *status = TSGStatus(@"status", AIAwayStatusType, AIEditableStatusState);
	[group addStatusItem:status atIndex:NSNotFound];
	XCTAssertTrue(status.containingStatusGroup == group);
}

- (void)testGroupWithContainedItemsAdoptsThem
{
	AIStatus *first = TSGStatus(@"first", AIAwayStatusType, AIEditableStatusState);
	AIStatus *second = TSGStatus(@"second", AIAwayStatusType, AIEditableStatusState);
	AIStatusGroup *group = [AIStatusGroup statusGroupWithContainedStatusItems:@[first, second]];

	NSArray *expected = @[first, second];
	XCTAssertEqualObjects(group.containedStatusItems, expected);
	XCTAssertTrue(first.containingStatusGroup == group);
	XCTAssertTrue(second.containingStatusGroup == group);
}

- (void)testSettingContainedItemsReplacesThem
{
	AIStatus *old = TSGStatus(@"old", AIAwayStatusType, AIEditableStatusState);
	AIStatus *new = TSGStatus(@"new", AIAwayStatusType, AIEditableStatusState);
	AIStatusGroup *group = [AIStatusGroup statusGroupWithContainedStatusItems:@[old]];
	XCTAssertEqualObjects(group.flatStatusSet, [NSSet setWithObject:old]);

	[group setContainedStatusItems:@[new]];
	XCTAssertEqualObjects(group.containedStatusItems, @[new]);
	XCTAssertEqualObjects(group.flatStatusSet, [NSSet setWithObject:new]);
}

- (void)testRemovingAnItemTakesItOut
{
	AIStatus *keep = TSGStatus(@"keep", AIAwayStatusType, AIEditableStatusState);
	AIStatus *drop = TSGStatus(@"drop", AIAwayStatusType, AIEditableStatusState);
	AIStatus *stranger = TSGStatus(@"stranger", AIAwayStatusType, AIEditableStatusState);
	AIStatusGroup *group = [AIStatusGroup statusGroupWithContainedStatusItems:@[keep, drop]];

	[group removeStatusItem:drop];
	[group removeStatusItem:stranger];
	XCTAssertEqualObjects(group.containedStatusItems, @[keep]);
}

- (void)testRemovingAnItemClearsItsContainingGroup
{
	AIStatus *drop = TSGStatus(@"drop", AIAwayStatusType, AIEditableStatusState);
	AIStatusGroup *group = [AIStatusGroup statusGroupWithContainedStatusItems:@[drop]];

	[group removeStatusItem:drop];
	XCTAssertNil(drop.containingStatusGroup);
}

- (void)testReplacingAStatusKeepsItsPosition
{
	AIStatus *first = TSGStatus(@"first", AIAwayStatusType, AIEditableStatusState);
	AIStatus *old = TSGStatus(@"old", AIAwayStatusType, AIEditableStatusState);
	AIStatus *last = TSGStatus(@"last", AIAwayStatusType, AIEditableStatusState);
	AIStatus *new = TSGStatus(@"new", AIAwayStatusType, AIEditableStatusState);
	AIStatusGroup *group = [AIStatusGroup statusGroupWithContainedStatusItems:@[first, old, last]];

	[group replaceExistingStatusState:old withStatusState:new];

	NSArray *expected = @[first, new, last];
	XCTAssertEqualObjects(group.containedStatusItems, expected);
	XCTAssertTrue(new.containingStatusGroup == group);
}

- (void)testReplacingAStatusWithItselfChangesNothing
{
	AIStatus *only = TSGStatus(@"only", AIAwayStatusType, AIEditableStatusState);
	AIStatusGroup *group = [AIStatusGroup statusGroupWithContainedStatusItems:@[only]];
	[group replaceExistingStatusState:only withStatusState:only];
	XCTAssertEqualObjects(group.containedStatusItems, @[only]);
}

- (void)testReplacingAStatusThatIsNotContainedAddsNothing
{
	AIStatus *only = TSGStatus(@"only", AIAwayStatusType, AIEditableStatusState);
	AIStatus *stranger = TSGStatus(@"stranger", AIAwayStatusType, AIEditableStatusState);
	AIStatus *new = TSGStatus(@"new", AIAwayStatusType, AIEditableStatusState);
	AIStatusGroup *group = [AIStatusGroup statusGroupWithContainedStatusItems:@[only]];

	[group replaceExistingStatusState:stranger withStatusState:new];
	XCTAssertEqualObjects(group.containedStatusItems, @[only]);
}

#pragma mark Flat status set

- (void)testFlatStatusSetHoldsOnlyStatuses
{
	AIStatus *status = TSGStatus(@"status", AIAwayStatusType, AIEditableStatusState);
	AIStatusGroup *nested = [AIStatusGroup statusGroup];
	AIStatusGroup *group = [AIStatusGroup statusGroupWithContainedStatusItems:@[status, nested]];

	XCTAssertEqualObjects(group.flatStatusSet, [NSSet setWithObject:status]);
}

- (void)testFlatStatusSetFollowsAddRemoveAndReplace
{
	AIStatus *first = TSGStatus(@"first", AIAwayStatusType, AIEditableStatusState);
	AIStatus *second = TSGStatus(@"second", AIAwayStatusType, AIEditableStatusState);
	AIStatus *replacement = TSGStatus(@"replacement", AIAwayStatusType, AIEditableStatusState);
	AIStatusGroup *group = [AIStatusGroup statusGroupWithContainedStatusItems:@[first]];
	XCTAssertEqualObjects(group.flatStatusSet, [NSSet setWithObject:first]);

	[group addStatusItem:second atIndex:NSNotFound];
	XCTAssertEqualObjects(group.flatStatusSet, ([NSSet setWithObjects:first, second, nil]));

	[group removeStatusItem:first];
	XCTAssertEqualObjects(group.flatStatusSet, [NSSet setWithObject:second]);

	[group replaceExistingStatusState:second withStatusState:replacement];
	XCTAssertEqualObjects(group.flatStatusSet, [NSSet setWithObject:replacement]);
}

#pragma mark Sorting

- (void)testSortPutsAvailableBeforeAwayBeforeOffline
{
	NSArray *statuses = @[TSGStatus(@"offline", AIOfflineStatusType, AIEditableStatusState),
						  TSGStatus(@"away", AIAwayStatusType, AIEditableStatusState),
						  TSGStatus(@"available", AIAvailableStatusType, AIEditableStatusState)];
	NSArray *expected = @[@"available", @"away", @"offline"];
	XCTAssertEqualObjects(TSGTitlesAfterSorting(statuses), expected);
}

- (void)testSortTreatsInvisibleLikeAway
{
	NSArray *statuses = @[TSGStatus(@"offline", AIOfflineStatusType, AIEditableStatusState),
						  TSGStatus(@"invisible", AIInvisibleStatusType, AIEditableStatusState),
						  TSGStatus(@"away", AIAwayStatusType, AIEditableStatusState),
						  TSGStatus(@"available", AIAvailableStatusType, AIEditableStatusState)];
	NSArray *expected = @[@"available", @"invisible", @"away", @"offline"];
	XCTAssertEqualObjects(TSGTitlesAfterSorting(statuses), expected, @"invisible and away keep their original order relative to each other");
}

- (void)testSortPutsLockedFirstThenTemporaryThenEditableThenSecondaryLocked
{
	NSArray *statuses = @[TSGStatus(@"secondary", AIAwayStatusType, AISecondaryLockedStatusState),
						  TSGStatus(@"editable", AIAwayStatusType, AIEditableStatusState),
						  TSGStatus(@"temporary", AIAwayStatusType, AITemporaryEditableStatusState),
						  TSGStatus(@"locked", AIAwayStatusType, AILockedStatusState)];
	NSArray *expected = @[@"locked", @"temporary", @"editable", @"secondary"];
	XCTAssertEqualObjects(TSGTitlesAfterSorting(statuses), expected);
}

- (void)testSortRanksTypeBeforeMutability
{
	NSArray *statuses = @[TSGStatus(@"locked away", AIAwayStatusType, AILockedStatusState),
						  TSGStatus(@"editable available", AIAvailableStatusType, AIEditableStatusState)];
	NSArray *expected = @[@"editable available", @"locked away"];
	XCTAssertEqualObjects(TSGTitlesAfterSorting(statuses), expected);
}

- (void)testSortKeepsTheOriginalOrderOfEqualItems
{
	NSArray *statuses = @[TSGStatus(@"c", AIAwayStatusType, AIEditableStatusState),
						  TSGStatus(@"a", AIAwayStatusType, AIEditableStatusState),
						  TSGStatus(@"b", AIAwayStatusType, AIEditableStatusState)];
	NSArray *expected = @[@"c", @"a", @"b"];
	XCTAssertEqualObjects(TSGTitlesAfterSorting(statuses), expected);
}

#pragma mark Archiving

- (void)testGroupSurvivesKeyedArchiving
{
	AIStatus *first = TSGStatus(@"first", AIAwayStatusType, AIEditableStatusState);
	AIStatus *second = TSGStatus(@"second", AIAvailableStatusType, AILockedStatusState);
	[first setUniqueStatusID:@1];
	[second setUniqueStatusID:@2];
	AIStatusGroup *group = [AIStatusGroup statusGroupWithContainedStatusItems:@[first, second]];
	[group setUniqueStatusID:@3];

	NSError *error = nil;
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:group requiringSecureCoding:NO error:&error];
	NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
	unarchiver.requiresSecureCoding = NO;
	AIStatusGroup *copy = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];

	XCTAssertTrue([copy isMemberOfClass:[AIStatusGroup class]]);
	XCTAssertEqualObjects([copy.containedStatusItems valueForKey:@"title"], (@[@"first", @"second"]));
	XCTAssertEqual([copy.containedStatusItems[1] statusType], AIAvailableStatusType);
	XCTAssertEqual([copy.containedStatusItems[1] mutabilityType], AILockedStatusState);
	XCTAssertEqual([copy.containedStatusItems[0] preexistingUniqueStatusID], 1);
	XCTAssertTrue([copy.containedStatusItems[0] containingStatusGroup] == copy, @"decoded statuses know their group again");
	XCTAssertEqual(copy.flatStatusSet.count, (NSUInteger)2);
}

@end
