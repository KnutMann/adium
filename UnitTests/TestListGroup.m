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
#import <Adium/AIListGroup.h>
#import <Adium/AIListContact.h>
#import <Adium/AIService.h>

@interface TLGService : AIService
@end

@implementation TLGService
- (NSString *)serviceID { return @"GroupTest"; }
@end

static TLGService *TLGSharedService(void)
{
	static TLGService *service = nil;
	if (!service) service = [[TLGService alloc] init];
	return service;
}

static AIListContact *TLGContact(NSString *UID)
{
	return [[AIListContact alloc] initWithUID:UID account:nil service:TLGSharedService()];
}

@interface TestListGroup : XCTestCase
@end

@implementation TestListGroup

#pragma mark Identity

- (void)testGroupInternalObjectIDIsPrefixedWithGroup
{
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"Friends"];
	XCTAssertEqualObjects(group.UID, @"Friends");
	XCTAssertEqualObjects(group.internalObjectID, @"Group.Friends");
	XCTAssertNil(group.service);
}

- (void)testAGroupHoldsContactsButNotGroups
{
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"Friends"];
	XCTAssertTrue([group canContainObject:TLGContact(@"alice")]);
	XCTAssertFalse([group canContainObject:[[AIListGroup alloc] initWithUID:@"Other"]]);
}

#pragma mark Membership

- (void)testAddingAContactPutsItInTheGroupOnBothSides
{
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"Friends"];
	AIListContact *alice = TLGContact(@"alice");

	XCTAssertTrue([group addObject:alice]);
	XCTAssertTrue([group containsObject:alice]);
	XCTAssertEqual(group.countOfContainedObjects, (NSUInteger)1);
	XCTAssertEqualObjects(group.containedObjects, @[alice]);
	XCTAssertEqualObjects(alice.groups, [NSSet setWithObject:group]);
	XCTAssertEqualObjects(alice.containingObjects, [NSSet setWithObject:group]);
}

- (void)testAddingTheSameContactTwiceIsRefused
{
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"Friends"];
	AIListContact *alice = TLGContact(@"alice");
	[group addObject:alice];
	XCTAssertFalse([group addObject:alice]);
	XCTAssertEqual(group.countOfContainedObjects, (NSUInteger)1);
}

- (void)testRemovingAContactTakesItOutOnBothSides
{
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"Friends"];
	AIListContact *alice = TLGContact(@"alice");
	AIListContact *bob = TLGContact(@"bob");
	[group addObject:alice];
	[group addObject:bob];

	[group removeObject:alice];
	XCTAssertFalse([group containsObject:alice]);
	XCTAssertTrue([group containsObject:bob]);
	XCTAssertEqualObjects(alice.groups, [NSSet set]);
	XCTAssertEqualObjects(bob.groups, [NSSet setWithObject:group]);

	[group removeObject:alice];
	XCTAssertEqual(group.countOfContainedObjects, (NSUInteger)1, @"removing a contact that is not there changes nothing");
}

- (void)testRemovingAfterTheAccountStopsTrackingTakesItOutToo
{
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"Friends"];
	AIListContact *alice = TLGContact(@"alice");
	[group addObject:alice];

	[group removeObjectAfterAccountStopsTracking:alice];
	XCTAssertFalse([group containsObject:alice]);
	XCTAssertEqualObjects(alice.groups, [NSSet set]);
}

- (void)testContainedObjectsAreASnapshot
{
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"Friends"];
	AIListContact *alice = TLGContact(@"alice");
	AIListContact *bob = TLGContact(@"bob");
	[group addObject:alice];
	NSArray *before = group.containedObjects;
	[group addObject:bob];

	XCTAssertEqualObjects(before, @[alice]);
	XCTAssertEqualObjects([NSSet setWithArray:group.containedObjects], ([NSSet setWithObjects:alice, bob, nil]));
	XCTAssertEqualObjects(group.uniqueContainedObjects, group.containedObjects);
}

- (void)testTheGroupEnumeratesItsContacts
{
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"Friends"];
	AIListContact *alice = TLGContact(@"alice");
	AIListContact *bob = TLGContact(@"bob");
	[group addObject:alice];
	[group addObject:bob];

	NSMutableSet *seen = [NSMutableSet set];
	for (AIListObject *object in group)
		[seen addObject:object];
	XCTAssertEqualObjects(seen, ([NSSet setWithObjects:alice, bob, nil]));
}

- (void)testObjectWithServiceAndUIDFindsAContact
{
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"Friends"];
	AIListContact *alice = TLGContact(@"alice");
	[group addObject:alice];

	XCTAssertTrue([group objectWithService:TLGSharedService() UID:@"alice"] == alice);
	XCTAssertNil([group objectWithService:TLGSharedService() UID:@"bob"]);
	XCTAssertNil([group objectWithService:nil UID:@"alice"], @"the service has to match too");
}

#pragma mark Visibility

- (void)testVisibleObjectsFollowTheContainedOnes
{
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"Friends"];
	AIListContact *alice = TLGContact(@"alice");
	AIListContact *bob = TLGContact(@"bob");
	XCTAssertEqual(group.visibleCount, (NSUInteger)0);

	[group addObject:alice];
	[group addObject:bob];
	XCTAssertEqual(group.visibleCount, (NSUInteger)2);
	XCTAssertEqualObjects([NSSet setWithArray:group.visibleContainedObjects], ([NSSet setWithObjects:alice, bob, nil]));
	XCTAssertTrue([group visibleObjectAtIndex:[group visibleIndexOfObject:bob]] == bob);

	[group removeObject:alice];
	XCTAssertEqual(group.visibleCount, (NSUInteger)1);
	XCTAssertEqual([group visibleIndexOfObject:alice], (NSUInteger)NSNotFound);
}

#pragma mark Description and state

- (void)testContentsBasedIdentifierListsTheSortedUIDs
{
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"Friends"];
	XCTAssertEqualObjects(group.contentsBasedIdentifier, @"Friends", @"an empty group is known by its name");

	[group addObject:TLGContact(@"bob")];
	[group addObject:TLGContact(@"alice")];
	XCTAssertEqualObjects(group.contentsBasedIdentifier, @"alice;bob");
}

- (void)testExpandedStateRoundTrips
{
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"Friends"];
	XCTAssertTrue(group.isExpandable);
	group.expanded = YES;
	XCTAssertTrue(group.isExpanded);
	group.expanded = NO;
	XCTAssertFalse(group.isExpanded);
}

- (void)testAGroupInNoListHasNoContactList
{
	AIListGroup *group = [[AIListGroup alloc] initWithUID:@"Friends"];
	XCTAssertNil(group.contactList);
	XCTAssertEqualObjects(group.groups, [NSSet set]);
}

@end
