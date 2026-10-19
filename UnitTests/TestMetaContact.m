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
#import <Adium/AIMetaContact.h>
#import <Adium/AIListContact.h>
#import <Adium/AIListGroup.h>

/* Only an empty meta contact is reachable here: adding a contact regroups through the contact
 * controller, which does not exist under the test runner. What an empty one promises is still
 * worth pinning, because the contact list asks these questions of every meta contact it draws. */
@interface TestMetaContact : XCTestCase
@end

@implementation TestMetaContact

- (void)testMetaContactIDIsDerivedFromItsObjectID
{
	XCTAssertEqualObjects([AIMetaContact internalObjectIDFromObjectID:@12], @"MetaContact-12");

	AIMetaContact *meta = [[AIMetaContact alloc] initWithObjectID:@12];
	XCTAssertEqualObjects(meta.objectID, @12);
	XCTAssertEqualObjects(meta.UID, @"12");
	XCTAssertEqualObjects(meta.internalObjectID, @"MetaContact-12");
	XCTAssertEqualObjects(meta.internalUniqueObjectID, @"MetaContact-12", @"nothing else can share a meta contact's ID");
	XCTAssertEqualObjects(meta.contentsBasedIdentifier, @"MetaContact-12");
}

- (void)testMetaContactIsItsOwnParentAndInNoMetaContact
{
	AIMetaContact *meta = [[AIMetaContact alloc] initWithObjectID:@12];
	XCTAssertNil(meta.metaContact);
	XCTAssertTrue(meta.parentContact == meta);
}

- (void)testMetaContactIsNeverAStrangerAndNotServerside
{
	AIMetaContact *meta = [[AIMetaContact alloc] initWithObjectID:@12];
	XCTAssertFalse(meta.isStranger);
	XCTAssertFalse(meta.existsServerside);
}

- (void)testMetaContactHoldsPlainContactsOnly
{
	AIMetaContact *meta = [[AIMetaContact alloc] initWithObjectID:@12];
	XCTAssertTrue([meta canContainObject:[[AIListContact alloc] initWithUID:@"alice" account:nil service:nil]]);
	XCTAssertFalse([meta canContainObject:[[AIMetaContact alloc] initWithObjectID:@13]]);
	XCTAssertFalse([meta canContainObject:[[AIListGroup alloc] initWithUID:@"Friends"]]);
}

- (void)testAnEmptyMetaContactHasNoPreferredContact
{
	AIMetaContact *meta = [[AIMetaContact alloc] initWithObjectID:@12];
	XCTAssertNil(meta.preferredContact);
	XCTAssertNil(meta.account);
	XCTAssertNil(meta.service);
	XCTAssertNil(meta.formattedUID);
	XCTAssertNil(meta.statusName);
}

- (void)testAnEmptyMetaContactContainsNothing
{
	AIMetaContact *meta = [[AIMetaContact alloc] initWithObjectID:@12];
	XCTAssertEqual(meta.countOfContainedObjects, (NSUInteger)0);
	XCTAssertEqual(meta.uniqueContainedObjectsCount, (NSUInteger)0);
	XCTAssertEqual(meta.visibleCount, (NSUInteger)0);
	XCTAssertEqualObjects(meta.containedObjects, @[]);
	XCTAssertEqualObjects(meta.uniqueContainedObjects, @[]);
	XCTAssertEqualObjects(meta.listContactsIncludingOfflineAccounts, @[]);
	XCTAssertFalse([meta containsObject:[[AIListContact alloc] initWithUID:@"alice" account:nil service:nil]]);
	XCTAssertFalse(meta.containsOnlyOneService);
}

- (void)testAMetaContactWithAtMostOneContactIsNotExpandable
{
	AIMetaContact *meta = [[AIMetaContact alloc] initWithObjectID:@12];
	XCTAssertFalse(meta.isExpandable);
}

- (void)testExpandedStateRoundTrips
{
	AIMetaContact *meta = [[AIMetaContact alloc] initWithObjectID:@12];
	meta.expanded = YES;
	XCTAssertTrue(meta.isExpanded);
	meta.expanded = NO;
	XCTAssertFalse(meta.isExpanded);
}

@end
