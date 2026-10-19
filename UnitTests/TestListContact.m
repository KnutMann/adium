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
#import <Adium/AIListContact.h>
#import <Adium/AIAccount.h>
#import <Adium/AIAbstractAccount.h>
#import <Adium/AIService.h>

@interface TLCService : AIService
@end

@implementation TLCService
- (NSString *)serviceID { return @"ContactTest"; }
- (NSString *)serviceClass { return @"ContactTestClass"; }
@end

static TLCService *TLCSharedService(void)
{
	static TLCService *service = nil;
	if (!service) service = [[TLCService alloc] init];
	return service;
}

/* An account is constructible here because every controller it reports to is nil; a contact only
 * needs one for the places where the account is the owner of something. */
static AIAccount *TLCAccount(void)
{
	return [[AIAccount alloc] initWithUID:@"me" internalObjectID:@"ContactTest.me" service:TLCSharedService()];
}

static AIListContact *TLCContact(NSString *UID, AIAccount *account)
{
	return [[AIListContact alloc] initWithUID:UID account:account service:TLCSharedService()];
}

@interface TestListContact : XCTestCase
@end

@implementation TestListContact

#pragma mark Identity

- (void)testContactKeepsItsAccount
{
	XCTAssertNil(TLCContact(@"bob", nil).account);
	AIAccount *account = TLCAccount();
	XCTAssertTrue(TLCContact(@"bob", account).account == account);
}

- (void)testUniqueObjectIDJoinsServiceClassAccountAndUID
{
	AIAccount *account = TLCAccount();
	XCTAssertEqualObjects([AIListContact internalUniqueObjectIDForService:TLCSharedService() account:account UID:@"bob"], @"ContactTestClass.me.bob");
	XCTAssertEqualObjects(TLCContact(@"bob", account).internalUniqueObjectID, @"ContactTestClass.me.bob");
	XCTAssertEqualObjects(TLCContact(@"bob", account).internalObjectID, @"ContactTest.bob", @"the plain ID knows nothing of the account");
}

- (void)testChangingTheUIDResetsTheIdentifiers
{
	AIListContact *contact = TLCContact(@"bob", TLCAccount());
	XCTAssertEqualObjects(contact.internalUniqueObjectID, @"ContactTestClass.me.bob");

	[contact setUID:@"robert"];
	XCTAssertEqualObjects(contact.UID, @"robert");
	XCTAssertEqualObjects(contact.internalObjectID, @"ContactTest.robert");
	XCTAssertEqualObjects(contact.internalUniqueObjectID, @"ContactTestClass.me.robert");
}

- (void)testAContactWithoutAMetaContactIsItsOwnParent
{
	AIListContact *contact = TLCContact(@"bob", nil);
	XCTAssertNil(contact.metaContact);
	XCTAssertTrue(contact.parentContact == contact);
}

- (void)testAContactExistsServersideAndMayJoinMetaContacts
{
	AIListContact *contact = TLCContact(@"bob", nil);
	XCTAssertTrue(contact.existsServerside);
	XCTAssertTrue(contact.canJoinMetaContacts);
}

- (void)testAContactInNoRemoteGroupIsAStranger
{
	AIListContact *contact = TLCContact(@"bob", nil);
	XCTAssertTrue(contact.isStranger);
	XCTAssertEqual(contact.countOfRemoteGroupNames, (NSUInteger)0);
	XCTAssertEqualObjects(contact.remoteGroupNames, [NSSet set]);
}

#pragma mark Status

- (void)testOnlineCanBeSetSilently
{
	AIListContact *contact = TLCContact(@"bob", nil);
	[contact setOnline:YES notify:NotifyNow silently:YES];
	XCTAssertTrue(contact.online);
	XCTAssertEqual(contact.statusSummary, AIAvailableStatus);

	[contact setOnline:NO notify:NotifyNow silently:YES];
	XCTAssertFalse(contact.online);
	XCTAssertEqual(contact.statusSummary, AIUnknownStatus, @"nothing is known about an offline stranger, not even that it is offline");
}

- (void)testSignonDateRoundTrips
{
	AIListContact *contact = TLCContact(@"bob", nil);
	XCTAssertNil(contact.signonDate);
	NSDate *date = [NSDate dateWithTimeIntervalSince1970:1579089600];
	[contact setSignonDate:date notify:NotifyNow];
	XCTAssertEqualObjects(contact.signonDate, date);
}

- (void)testIdleWithoutADateIsIdleForAnUnknownTime
{
	AIListContact *contact = TLCContact(@"bob", nil);
	[contact setOnline:YES notify:NotifyNow silently:YES];

	[contact setIdle:YES sinceDate:nil notify:NotifyNow];
	XCTAssertTrue([contact boolValueForProperty:@"isIdle"]);
	XCTAssertEqual(contact.idleTime, (NSInteger)-1);
	XCTAssertEqual(contact.statusSummary, AIIdleStatus);

	[contact setIdle:NO sinceDate:nil notify:NotifyNow];
	XCTAssertFalse([contact boolValueForProperty:@"isIdle"]);
	XCTAssertEqual(contact.idleTime, (NSInteger)0);
	XCTAssertEqual(contact.statusSummary, AIAvailableStatus);
}

- (void)testIdleWithADateRemembersWhenItBegan
{
	AIListContact *contact = TLCContact(@"bob", nil);
	NSDate *since = [NSDate dateWithTimeIntervalSince1970:1579089600];
	[contact setIdle:YES sinceDate:since notify:NotifyNow];
	XCTAssertEqualObjects([contact valueForProperty:@"idleSince"], since);
	XCTAssertTrue([contact boolValueForProperty:@"isIdle"]);

	[contact setIdle:NO sinceDate:nil notify:NotifyNow];
	XCTAssertNil([contact valueForProperty:@"idleSince"]);
}

- (void)testMobileFlagRoundTrips
{
	AIListContact *contact = TLCContact(@"bob", nil);
	XCTAssertFalse(contact.isMobile);
	[contact setIsMobile:YES notify:NotifyNow];
	XCTAssertTrue(contact.isMobile);
	[contact setIsMobile:NO notify:NotifyNow];
	XCTAssertFalse(contact.isMobile);
}

- (void)testBlockedFlagCanBeSetWithoutTouchingTheServer
{
	AIListContact *contact = TLCContact(@"bob", nil);
	XCTAssertFalse(contact.isBlocked);
	[contact setIsBlocked:YES updateList:NO];
	XCTAssertTrue(contact.isBlocked);
	[contact setIsBlocked:NO updateList:NO];
	XCTAssertFalse(contact.isBlocked);
}

#pragma mark Profile and names

- (void)testProfileRoundTrips
{
	AIListContact *contact = TLCContact(@"bob", nil);
	XCTAssertNil(contact.profile);
	XCTAssertNil(contact.profileArray);

	NSAttributedString *profile = [[NSAttributedString alloc] initWithString:@"About me"];
	NSArray *profileArray = @[@{ @"key": @"Location", @"value": @"Wonderland" }];
	[contact setProfile:profile notify:NotifyNow];
	[contact setProfileArray:profileArray notify:NotifyNow];
	XCTAssertEqualObjects(contact.profile, profile);
	XCTAssertEqualObjects(contact.profileArray, profileArray);
}

- (void)testServersideAliasBecomesTheDisplayName
{
	AIListContact *contact = TLCContact(@"bob", TLCAccount());
	XCTAssertNil(contact.serversideDisplayName);
	XCTAssertEqualObjects(contact.displayName, @"bob");

	[contact setServersideAlias:@"Robert" silently:YES];
	XCTAssertEqualObjects(contact.serversideDisplayName, @"Robert");
	XCTAssertEqualObjects(contact.displayName, @"Robert");
	XCTAssertEqualObjects(contact.ownDisplayName, @"Robert");
}

- (void)testServersideAliasLosesItsLineBreaks
{
	AIListContact *contact = TLCContact(@"bob", TLCAccount());
	[contact setServersideAlias:@"Robert\nthe Bruce" silently:YES];
	XCTAssertFalse([contact.displayName containsString:@"\n"]);
	XCTAssertTrue([contact.displayName hasPrefix:@"Robert"]);
}

@end
