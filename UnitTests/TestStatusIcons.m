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

#import <Adium/AIStatusIcons.h>
#import <Adium/AIStatusControllerProtocol.h>
#import <Adium/AIListObject.h>

/* Every image in the Dots fixture has a pixel size of its own, so the size of an icon says which file
 * it came from: available 10, tab-available 12, away 14, offline 16, unknown 18, idle 20. The pack
 * names no Invisible, Blocked or Mobile icon, and its Busy entry names a file that is not there. */

@interface TestStatusIcons : XCTestCase {
	NSString	*scratchDirectory;
}
@end

@implementation TestStatusIcons

- (NSString *)dotsPackPath
{
	return [[[NSBundle bundleForClass:[self class]] resourcePath]
			stringByAppendingPathComponent:@"Fixtures/Dots.AdiumStatusIcons"];
}

/* The active pack is process-wide state, so every test starts from the fixture */
- (void)setUp
{
	[super setUp];
	scratchDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
						[@"TestStatusIcons-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
	[[NSFileManager defaultManager] createDirectoryAtPath:scratchDirectory
							  withIntermediateDirectories:YES
											   attributes:nil
													error:NULL];
	XCTAssertTrue([AIStatusIcons setActiveStatusIconsFromPath:[self dotsPackPath]]);
}

- (void)tearDown
{
	[[NSFileManager defaultManager] removeItemAtPath:scratchDirectory error:NULL];
	[super tearDown];
}

- (CGFloat)edgeOfIconNamed:(NSString *)statusName type:(AIStatusType)statusType icon:(AIStatusIconType)iconType
{
	return [[AIStatusIcons statusIconForStatusName:statusName statusType:statusType iconType:iconType direction:AIIconNormal] size].width;
}

- (NSString *)makePackWithIcons:(NSDictionary *)icons version:(int)version
{
	NSString *packPath = [scratchDirectory stringByAppendingPathComponent:
						  [[[NSUUID UUID] UUIDString] stringByAppendingPathComponent:@"Made.AdiumStatusIcons"]];
	NSDictionary *plist = [NSDictionary dictionaryWithObjectsAndKeys:
						   [NSNumber numberWithInt:version], @"AdiumSetVersion",
						   icons, @"List",
						   icons, @"Tabs",
						   nil];

	[[NSFileManager defaultManager] createDirectoryAtPath:packPath withIntermediateDirectories:YES attributes:nil error:NULL];
	XCTAssertTrue([plist writeToFile:[packPath stringByAppendingPathComponent:@"Icons.plist"] atomically:YES]);
	for (NSString *fileName in [NSSet setWithArray:[icons allValues]]) {
		[[NSFileManager defaultManager] copyItemAtPath:[[self dotsPackPath] stringByAppendingPathComponent:fileName]
												toPath:[packPath stringByAppendingPathComponent:fileName]
												 error:NULL];
	}
	return packPath;
}

#pragma mark Choosing a pack

- (void)testPackWithoutAnIconsListIsRejected
{
	XCTAssertFalse([AIStatusIcons setActiveStatusIconsFromPath:[scratchDirectory stringByAppendingPathComponent:@"None.AdiumStatusIcons"]]);
}

- (void)testPackOfAVersionNobodyKnowsIsRejected
{
	NSString *packPath = [self makePackWithIcons:[NSDictionary dictionaryWithObject:@"away.png" forKey:STATUS_NAME_AVAILABLE] version:2];

	XCTAssertFalse([AIStatusIcons setActiveStatusIconsFromPath:packPath]);
}

- (void)testChangingThePackIsAnnounced
{
	__block NSUInteger announcements = 0;
	id observer = [[NSNotificationCenter defaultCenter] addObserverForName:AIStatusIconSetDidChangeNotification
																	object:nil
																	 queue:nil
																usingBlock:^(NSNotification *note) { announcements++; }];

	[AIStatusIcons setActiveStatusIconsFromPath:[self dotsPackPath]];
	[[NSNotificationCenter defaultCenter] removeObserver:observer];

	XCTAssertEqual(announcements, (NSUInteger)1);
}

- (void)testSwitchingPacksDropsTheIconsOfTheOldOne
{
	XCTAssertEqual([self edgeOfIconNamed:STATUS_NAME_AVAILABLE type:AIAvailableStatusType icon:AIStatusIconList], 10);

	NSString *otherPack = [self makePackWithIcons:[NSDictionary dictionaryWithObjectsAndKeys:
												   @"away.png", STATUS_NAME_AVAILABLE,
												   @"away.png", STATUS_NAME_AWAY,
												   @"offline.png", STATUS_NAME_OFFLINE,
												   nil]
										  version:1];
	XCTAssertTrue([AIStatusIcons setActiveStatusIconsFromPath:otherPack]);

	XCTAssertEqual([self edgeOfIconNamed:STATUS_NAME_AVAILABLE type:AIAvailableStatusType icon:AIStatusIconList], 14);
}

#pragma mark Where each kind of icon comes from

- (void)testListIconsComeFromTheListEntries
{
	XCTAssertEqual([self edgeOfIconNamed:STATUS_NAME_AVAILABLE type:AIAvailableStatusType icon:AIStatusIconList], 10);
}

- (void)testTabIconsComeFromTheTabsEntries
{
	XCTAssertEqual([self edgeOfIconNamed:STATUS_NAME_AVAILABLE type:AIAvailableStatusType icon:AIStatusIconTab], 12);
}

- (void)testMenuIconsAreTheTabIcons
{
	XCTAssertEqual([self edgeOfIconNamed:STATUS_NAME_AVAILABLE type:AIAvailableStatusType icon:AIStatusIconMenu], 12);
}

- (void)testBothDirectionsShowTheSameArtwork
{
	NSImage *normal = [AIStatusIcons statusIconForStatusName:STATUS_NAME_AWAY statusType:AIAwayStatusType iconType:AIStatusIconList direction:AIIconNormal];
	NSImage *flipped = [AIStatusIcons statusIconForStatusName:STATUS_NAME_AWAY statusType:AIAwayStatusType iconType:AIStatusIconList direction:AIIconFlipped];

	XCTAssertEqualObjects([normal TIFFRepresentation], [flipped TIFFRepresentation]);
}

#pragma mark Names the pack has no icon for

- (void)testNoStatusNameMeansTheDefaultOfItsType
{
	XCTAssertEqual([self edgeOfIconNamed:nil type:AIAvailableStatusType icon:AIStatusIconList], 10);
	XCTAssertEqual([self edgeOfIconNamed:nil type:AIAwayStatusType icon:AIStatusIconList], 14);
	XCTAssertEqual([self edgeOfIconNamed:nil type:AIOfflineStatusType icon:AIStatusIconList], 16);
}

- (void)testStatusNameThePackLacksFallsBackToTheDefaultOfItsType
{
	XCTAssertEqual([self edgeOfIconNamed:@"Mobile" type:AIAvailableStatusType icon:AIStatusIconList], 10);
	XCTAssertEqual([self edgeOfIconNamed:@"Idle And Away" type:AIAwayStatusType icon:AIStatusIconList], 14);
}

- (void)testStatusNameThePackHasIsNotReplacedByTheDefault
{
	XCTAssertEqual([self edgeOfIconNamed:@"Idle" type:AIAvailableStatusType icon:AIStatusIconList], 20);
}

- (void)testInvisibleFallsBackToAwayWhenThePackHasNone
{
	XCTAssertEqual([self edgeOfIconNamed:STATUS_NAME_INVISIBLE type:AIInvisibleStatusType icon:AIStatusIconList], 14);
}

- (void)testBlockedFallsBackToTheBuiltInIcon
{
	NSImage *blocked = [AIStatusIcons statusIconForStatusName:@"Blocked" statusType:AIAvailableStatusType iconType:AIStatusIconList direction:AIIconNormal];

	XCTAssertTrue([blocked isValid]);
	XCTAssertNotEqual([blocked size].width, 10, @"Not the available icon the type would fall back to");
}

- (void)testUnknownStatusHasAnIconOfItsOwn
{
	XCTAssertEqual([[AIStatusIcons statusIconForUnknownStatusWithIconType:AIStatusIconList direction:AIIconNormal] size].width, 18);
}

- (void)testEntryWhoseFileIsMissingStillYieldsAnImage
{
	XCTAssertNotNil([AIStatusIcons statusIconForStatusName:@"Busy" statusType:AIAwayStatusType iconType:AIStatusIconList direction:AIIconNormal]);
}

#pragma mark The name a list object is looked up under

/* A plain AIListObject, which no account owns: never mobile, never blocked, never a stranger */
- (AIListObject *)objectOnline:(BOOL)online idle:(BOOL)idle status:(NSString *)statusName ofType:(AIStatusType)statusType
{
	AIListObject *object = [[AIListObject alloc] initWithUID:@"someone" service:nil];

	[object setValue:[NSNumber numberWithBool:online] forProperty:@"isOnline" notify:NotifyNever];
	[object setValue:[NSNumber numberWithBool:idle] forProperty:@"isIdle" notify:NotifyNever];
	[object setStatusWithName:statusName statusType:statusType notify:NotifyNever];

	return object;
}

- (void)testOfflineObjectIsLookedUpAsOfflineWhateverItsStatusSays
{
	AIListObject *object = [self objectOnline:NO idle:NO status:@"Busy" ofType:AIAwayStatusType];

	XCTAssertEqualObjects([AIStatusIcons statusNameForListObject:object], STATUS_NAME_OFFLINE);
}

- (void)testAvailableObjectWithoutAStatusNameLeavesTheChoiceToItsType
{
	AIListObject *object = [self objectOnline:YES idle:NO status:nil ofType:AIAvailableStatusType];

	XCTAssertNil([AIStatusIcons statusNameForListObject:object]);
}

- (void)testIdleObjectIsLookedUpAsIdle
{
	AIListObject *object = [self objectOnline:YES idle:YES status:nil ofType:AIAvailableStatusType];

	XCTAssertEqualObjects([AIStatusIcons statusNameForListObject:object], @"Idle");
}

- (void)testIdleAndAwayObjectIsLookedUpAsIdleAndAway
{
	AIListObject *object = [self objectOnline:YES idle:YES status:@"Busy" ofType:AIAwayStatusType];

	XCTAssertEqualObjects([AIStatusIcons statusNameForListObject:object], @"Idle And Away");
}

- (void)testObjectsOwnStatusNameIsUsedWhenItIsNeitherOfflineNorIdle
{
	AIListObject *object = [self objectOnline:YES idle:NO status:@"Busy" ofType:AIAwayStatusType];

	XCTAssertEqualObjects([AIStatusIcons statusNameForListObject:object], @"Busy");
}

- (void)testIconForAnObjectFollowsItsNameAndType
{
	AIListObject *offline = [self objectOnline:NO idle:NO status:nil ofType:AIAvailableStatusType];
	AIListObject *idleAndAway = [self objectOnline:YES idle:YES status:nil ofType:AIAwayStatusType];

	XCTAssertEqual([[AIStatusIcons statusIconForListObject:offline type:AIStatusIconList direction:AIIconNormal] size].width, 16);
	//The pack has no Idle And Away icon, so the away default of the object's type stands in
	XCTAssertEqual([[AIStatusIcons statusIconForListObject:idleAndAway type:AIStatusIconList direction:AIIconNormal] size].width, 14);
}

@end
