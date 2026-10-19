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
#import <Adium/AIListObject.h>
#import <Adium/AIService.h>
#import <AIUtilities/AIMutableOwnerArray.h>

@interface TLOService : AIService
@end

@implementation TLOService
- (NSString *)serviceID { return @"ListTest"; }
@end

static AIListObject *TLOObject(NSString *UID)
{
	static TLOService *service = nil;
	if (!service) service = [[TLOService alloc] init];
	return [[AIListObject alloc] initWithUID:UID service:service];
}

static NSAttributedString *TLOText(NSString *string)
{
	return [[NSAttributedString alloc] initWithString:string];
}

@interface TestListObject : XCTestCase
@end

@implementation TestListObject

#pragma mark Identity

- (void)testListObjectKeepsItsUIDAndService
{
	AIListObject *object = TLOObject(@"alice");
	XCTAssertEqualObjects(object.UID, @"alice");
	XCTAssertEqualObjects(object.service.serviceID, @"ListTest");
}

- (void)testInternalObjectIDJoinsServiceIDAndUID
{
	XCTAssertEqualObjects([AIListObject internalObjectIDForServiceID:@"Jabber" UID:@"alice@example.org"], @"Jabber.alice@example.org");
	XCTAssertEqualObjects(TLOObject(@"alice").internalObjectID, @"ListTest.alice");
}

- (void)testCompareOrdersByInternalObjectIDIgnoringCase
{
	AIListObject *alice = TLOObject(@"alice");
	AIListObject *bob = TLOObject(@"bob");
	XCTAssertEqual([alice compare:bob], NSOrderedAscending);
	XCTAssertEqual([bob compare:alice], NSOrderedDescending);
	XCTAssertEqual([alice compare:TLOObject(@"alice")], NSOrderedSame);
	XCTAssertEqual([alice compare:TLOObject(@"ALICE")], NSOrderedSame);
}

#pragma mark Names

- (void)testFormattedUIDFallsBackToTheUID
{
	AIListObject *object = TLOObject(@"alice");
	XCTAssertEqualObjects(object.formattedUID, @"alice");
	[object setFormattedUID:@"Alice" notify:NotifyNever];
	XCTAssertEqualObjects(object.formattedUID, @"Alice");
	XCTAssertEqualObjects(object.UID, @"alice", @"the UID itself is untouched");
}

- (void)testDisplayNameFallsBackToTheFormattedUID
{
	AIListObject *object = TLOObject(@"alice");
	XCTAssertEqualObjects(object.displayName, @"alice");

	[object setFormattedUID:@"Alice" notify:NotifyNever];
	XCTAssertEqualObjects(object.displayName, @"Alice");

	[[object displayArrayForKey:@"Display Name"] setObject:@"Alice Liddell" withOwner:self];
	XCTAssertEqualObjects(object.displayName, @"Alice Liddell");
}

- (void)testLongDisplayNameFallsBackToTheDisplayName
{
	AIListObject *object = TLOObject(@"alice");
	XCTAssertEqualObjects(object.longDisplayName, @"alice");

	[[object displayArrayForKey:@"Display Name"] setObject:@"Alice" withOwner:self];
	XCTAssertEqualObjects(object.longDisplayName, @"Alice");

	[[object displayArrayForKey:@"Long Display Name"] setObject:@"Alice (alice)" withOwner:self];
	XCTAssertEqualObjects(object.longDisplayName, @"Alice (alice)");
}

- (void)testPhoneticNameFallsBackToTheDisplayName
{
	AIListObject *object = TLOObject(@"alice");
	[[object displayArrayForKey:@"Display Name"] setObject:@"Alice" withOwner:self];
	XCTAssertEqualObjects(object.phoneticName, @"Alice");

	[[object displayArrayForKey:@"Phonetic Name"] setObject:@"Al-iss" withOwner:self];
	XCTAssertEqualObjects(object.phoneticName, @"Al-iss");
}

#pragma mark Grouping

- (void)testAFreshObjectBelongsToNoGroup
{
	AIListObject *object = TLOObject(@"alice");
	XCTAssertEqualObjects(object.groups, [NSSet set]);
	XCTAssertEqualObjects(object.containingObjects, [NSSet set]);
}

#pragma mark Status

- (void)testAnObjectIsOfflineUntilToldOtherwise
{
	AIListObject *object = TLOObject(@"alice");
	XCTAssertFalse(object.online);
	XCTAssertEqual(object.statusType, AIOfflineStatusType);
	XCTAssertEqual(object.statusSummary, AIOfflineStatus);
	XCTAssertNil(object.statusName);
	XCTAssertNil(object.statusMessage);
}

- (void)testStatusTypeIsOfflineWhileOffline
{
	AIListObject *object = TLOObject(@"alice");
	[object setStatusWithName:@"Lunch" statusType:AIAwayStatusType notify:NotifyNow];
	XCTAssertEqual(object.statusType, AIOfflineStatusType);
	XCTAssertEqualObjects(object.statusName, @"Lunch", @"the name is kept for when the object comes online");
}

- (void)testAnOnlineObjectIsAvailableByDefault
{
	AIListObject *object = TLOObject(@"alice");
	[object setValue:@YES forProperty:@"isOnline" notify:NotifyNow];
	XCTAssertTrue(object.online);
	XCTAssertEqual(object.statusType, AIAvailableStatusType);
	XCTAssertEqual(object.statusSummary, AIAvailableStatus);
}

- (void)testStatusNameAndTypeAreStoredTogether
{
	AIListObject *object = TLOObject(@"alice");
	[object setValue:@YES forProperty:@"isOnline" notify:NotifyNow];

	[object setStatusWithName:@"Lunch" statusType:AIAwayStatusType notify:NotifyNow];
	XCTAssertEqual(object.statusType, AIAwayStatusType);
	XCTAssertEqualObjects(object.statusName, @"Lunch");

	[object setStatusWithName:nil statusType:AIInvisibleStatusType notify:NotifyNow];
	XCTAssertEqual(object.statusType, AIInvisibleStatusType);
	XCTAssertNil(object.statusName);
}

- (void)testStatusMessageRoundTrips
{
	AIListObject *object = TLOObject(@"alice");
	[object setStatusMessage:TLOText(@"Out to lunch") notify:NotifyNow];
	XCTAssertEqualObjects(object.statusMessage, TLOText(@"Out to lunch"));
	XCTAssertEqualObjects(object.statusMessageString, @"Out to lunch");

	[object setStatusMessage:nil notify:NotifyNow];
	XCTAssertNil(object.statusMessage);
	XCTAssertNil(object.statusMessageString);
}

- (void)testBaseAvailableStatusClearsNameMessageAndType
{
	AIListObject *object = TLOObject(@"alice");
	[object setValue:@YES forProperty:@"isOnline" notify:NotifyNow];
	[object setStatusWithName:@"Lunch" statusType:AIAwayStatusType notify:NotifyNow];
	[object setStatusMessage:TLOText(@"Out to lunch") notify:NotifyNow];

	[object setBaseAvailableStatusAndNotify:NotifyNow];
	XCTAssertEqual(object.statusType, AIAvailableStatusType);
	XCTAssertNil(object.statusName);
	XCTAssertNil(object.statusMessage);
}

- (void)testStatusSummaryDistinguishesIdleAndAway
{
	AIListObject *object = TLOObject(@"alice");
	[object setValue:@YES forProperty:@"isOnline" notify:NotifyNow];

	[object setValue:@YES forProperty:@"isIdle" notify:NotifyNow];
	XCTAssertEqual(object.statusSummary, AIIdleStatus);

	[object setStatusWithName:nil statusType:AIAwayStatusType notify:NotifyNow];
	XCTAssertEqual(object.statusSummary, AIAwayAndIdleStatus);

	[object setValue:nil forProperty:@"isIdle" notify:NotifyNow];
	XCTAssertEqual(object.statusSummary, AIAwayStatus);

	[object setStatusWithName:nil statusType:AIInvisibleStatusType notify:NotifyNow];
	XCTAssertEqual(object.statusSummary, AIAwayStatus, @"invisible reads as away");

	[object setValue:nil forProperty:@"isOnline" notify:NotifyNow];
	XCTAssertEqual(object.statusSummary, AIOfflineStatus);
}

#pragma mark Flags

- (void)testAPlainListObjectIsNeitherStrangerMobileNorBlocked
{
	AIListObject *object = TLOObject(@"alice");
	XCTAssertFalse(object.isStranger);
	XCTAssertFalse(object.isMobile);
	XCTAssertFalse(object.isBlocked);
	XCTAssertFalse(object.soundsAreMuted);
}

- (void)testIdleTimeIsZeroWhenUnknown
{
	XCTAssertEqual(TLOObject(@"alice").idleTime, (NSInteger)0);
}

@end
