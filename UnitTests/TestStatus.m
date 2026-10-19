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
#import <Adium/AIStatusItem.h>
#import <Adium/AIStatus.h>
#import <Adium/AIStatusGroup.h>

/* Through a keyed archive and back, the way the status controller stores saved statuses. The unique
 * ID is set first so that encoding never has to ask the (absent) preference controller for one. */
static id TStatusRoundTrip(AIStatusItem *item)
{
	NSError *error = nil;
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:item requiringSecureCoding:NO error:&error];
	NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
	unarchiver.requiresSecureCoding = NO;
	return [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
}

@interface TestStatus : XCTestCase
@end

@implementation TestStatus

#pragma mark AIStatusItem

- (void)testStatusItemTitleIsNilUntilSet
{
	AIStatusItem *item = [[AIStatusItem alloc] init];
	XCTAssertNil(item.title);
	[item setTitle:@"Lunch"];
	XCTAssertEqualObjects(item.title, @"Lunch");
}

- (void)testStatusItemEmptyTitleReadsAsNil
{
	AIStatusItem *item = [[AIStatusItem alloc] init];
	[item setTitle:@""];
	XCTAssertNil(item.title);
	[item setTitle:@"Lunch"];
	[item setTitle:nil];
	XCTAssertNil(item.title);
}

- (void)testStatusItemStatusTypeRoundTrips
{
	AIStatusItem *item = [[AIStatusItem alloc] init];
	[item setStatusType:AIInvisibleStatusType];
	XCTAssertEqual(item.statusType, AIInvisibleStatusType);
	[item setStatusType:AIAvailableStatusType];
	XCTAssertEqual(item.statusType, AIAvailableStatusType);
}

- (void)testStatusItemIsEditable
{
	AIStatusItem *item = [[AIStatusItem alloc] init];
	XCTAssertEqual(item.mutabilityType, AIEditableStatusState);
}

- (void)testStatusItemHasNoUniqueIDUntilOneIsSet
{
	AIStatusItem *item = [[AIStatusItem alloc] init];
	XCTAssertEqual([item preexistingUniqueStatusID], -1);

	[item setUniqueStatusID:@42];
	XCTAssertEqual([item preexistingUniqueStatusID], 42);
	XCTAssertEqualObjects([item uniqueStatusID], @42);

	[item setUniqueStatusID:nil];
	XCTAssertEqual([item preexistingUniqueStatusID], -1);
}

- (void)testStatusItemContainingGroupIsSettable
{
	AIStatusItem *item = [[AIStatusItem alloc] init];
	AIStatusGroup *group = [AIStatusGroup statusGroup];
	XCTAssertNil(item.containingStatusGroup);
	[item setContainingStatusGroup:group];
	XCTAssertTrue(item.containingStatusGroup == group);
	[item setContainingStatusGroup:nil];
	XCTAssertNil(item.containingStatusGroup);
}

- (void)testStatusItemAppleScriptTypeMapsEachStatusType
{
	AIStatusItem *item = [[AIStatusItem alloc] init];
	AIStatusType types[] = { AIAvailableStatusType, AIAwayStatusType, AIInvisibleStatusType, AIOfflineStatusType };
	AIStatusTypeApplescript scriptTypes[] = { AIAvailableStatusTypeAS, AIAwayStatusTypeAS, AIInvisibleStatusTypeAS, AIOfflineStatusTypeAS };

	for (unsigned i = 0; i < 4; i++) {
		[item setStatusType:types[i]];
		XCTAssertEqual(item.statusTypeApplescript, scriptTypes[i]);

		[item setStatusType:AIAwayStatusType];
		[item setStatusTypeApplescript:scriptTypes[i]];
		XCTAssertEqual(item.statusType, types[i]);
	}
}

- (void)testStatusItemSurvivesKeyedArchiving
{
	AIStatusItem *item = [[AIStatusItem alloc] init];
	[item setTitle:@"Lunch"];
	[item setStatusType:AIInvisibleStatusType];
	[item setUniqueStatusID:@7];

	AIStatusItem *copy = TStatusRoundTrip(item);
	XCTAssertTrue([copy isMemberOfClass:[AIStatusItem class]]);
	XCTAssertEqualObjects(copy.title, @"Lunch");
	XCTAssertEqual(copy.statusType, AIInvisibleStatusType);
	XCTAssertEqual([copy preexistingUniqueStatusID], 7);
}

- (void)testStatusItemMutableCopyIsASeparateItemWithoutTheUniqueID
{
	AIStatusItem *item = [[AIStatusItem alloc] init];
	[item setTitle:@"Lunch"];
	[item setStatusType:AIAwayStatusType];
	[item setUniqueStatusID:@7];

	AIStatusItem *copy = [item mutableCopy];
	XCTAssertFalse(copy == item);
	XCTAssertEqualObjects(copy.title, @"Lunch");
	XCTAssertEqual(copy.statusType, AIAwayStatusType);
	XCTAssertEqual([copy preexistingUniqueStatusID], -1);

	[copy setTitle:@"Dinner"];
	XCTAssertEqualObjects(item.title, @"Lunch", @"the copy has its own dictionary");
}

#pragma mark AIStatus flags

- (void)testStatusDefaultsToEditableWithNothingMutedOrSpecial
{
	AIStatus *status = [AIStatus status];
	XCTAssertEqual(status.mutabilityType, AIEditableStatusState);
	XCTAssertFalse(status.mutesSound);
	XCTAssertFalse(status.silencesNotifications);
	XCTAssertEqual(status.specialStatusType, AINoSpecialStatusType);
	XCTAssertNil(status.statusName);
	XCTAssertNil(status.statusMessage);
}

- (void)testStatusMutabilityRoundTrips
{
	AIStatus *status = [AIStatus status];
	[status setMutabilityType:AILockedStatusState];
	XCTAssertEqual(status.mutabilityType, AILockedStatusState);
	[status setMutabilityType:AISecondaryLockedStatusState];
	XCTAssertEqual(status.mutabilityType, AISecondaryLockedStatusState);
}

- (void)testStatusMuteAndSilenceFlagsRoundTrip
{
	AIStatus *status = [AIStatus status];
	status.mutesSound = YES;
	status.silencesNotifications = YES;
	XCTAssertTrue(status.mutesSound);
	XCTAssertTrue(status.silencesNotifications);
	status.mutesSound = NO;
	XCTAssertFalse(status.mutesSound);
	XCTAssertTrue(status.silencesNotifications, @"the two flags are independent");
}

- (void)testStatusSpecialTypeRoundTrips
{
	AIStatus *status = [AIStatus status];
	status.specialStatusType = AINowPlayingSpecialStatusType;
	XCTAssertEqual(status.specialStatusType, AINowPlayingSpecialStatusType);
}

- (void)testStatusNameRoundTripsAndNilClears
{
	AIStatus *status = [AIStatus status];
	status.statusName = @"Do Not Disturb";
	XCTAssertEqualObjects(status.statusName, @"Do Not Disturb");
	status.statusName = nil;
	XCTAssertNil(status.statusName);
}

#pragma mark AIStatus message

- (void)testStatusMessageIsNilWhenEmpty
{
	AIStatus *status = [AIStatus status];
	status.statusMessage = [[NSAttributedString alloc] initWithString:@""];
	XCTAssertNil(status.statusMessage);
	XCTAssertNil(status.statusMessageString);

	status.statusMessage = [[NSAttributedString alloc] initWithString:@"Out to lunch"];
	XCTAssertEqualObjects(status.statusMessageString, @"Out to lunch");

	status.statusMessage = nil;
	XCTAssertNil(status.statusMessage);
}

- (void)testStatusMessageStringDecodesHTML
{
	AIStatus *status = [AIStatus status];
	status.statusMessageString = @"<b>Busy</b> until 5";
	XCTAssertEqualObjects(status.statusMessageString, @"Busy until 5");
}

- (void)testFilteredMessageIsUsedForTheTooltipUntilTheMessageChanges
{
	AIStatus *status = [AIStatus status];
	status.statusMessageString = @"Listening to %_track";
	XCTAssertEqualObjects([status statusMessageTooltipString], @"Listening to %_track");

	[status setFilteredStatusMessage:@"Listening to Blue Train"];
	XCTAssertEqualObjects([status statusMessageTooltipString], @"Listening to Blue Train");

	status.statusMessageString = @"Away";
	XCTAssertEqualObjects([status statusMessageTooltipString], @"Away", @"a new message discards the old filtered form");
}

- (void)testSettingAFilteredMessagePostsANotificationOnlyWhenItChanges
{
	AIStatus *status = [AIStatus status];
	__block NSUInteger posts = 0;
	id token = [[NSNotificationCenter defaultCenter] addObserverForName:@"AIStatusFilteredStatusMessageChanged"
																  object:status
																   queue:nil
															  usingBlock:^(NSNotification *note) { posts++; }];

	[status setFilteredStatusMessage:@"Blue Train"];
	[status setFilteredStatusMessage:@"Blue Train"];
	[status setFilteredStatusMessage:@"Giant Steps"];

	[[NSNotificationCenter defaultCenter] removeObserver:token];
	XCTAssertEqual(posts, (NSUInteger)2);
}

#pragma mark AIStatus title

- (void)testTitlePrefersTheExplicitTitle
{
	AIStatus *status = [AIStatus status];
	[status setTitle:@"Lunch"];
	status.statusMessageString = @"Out to lunch";
	XCTAssertEqualObjects(status.title, @"Lunch");
}

- (void)testTitleFallsBackToTheStatusMessage
{
	AIStatus *status = [AIStatus status];
	status.statusMessageString = @"Out to lunch";
	XCTAssertEqualObjects(status.title, @"Out to lunch");

	[status setTitle:@""];
	XCTAssertEqualObjects(status.title, @"Out to lunch", @"an empty title is no title");
}

- (void)testTitleFromMessageIsTrimmed
{
	AIStatus *status = [AIStatus status];
	status.statusMessage = [[NSAttributedString alloc] initWithString:@"  Out to lunch \n"];
	XCTAssertEqualObjects(status.title, @"Out to lunch");
}

- (void)testTitleFromMessageIsItsFirstLineOnly
{
	AIStatus *status = [AIStatus status];
	status.statusMessage = [[NSAttributedString alloc] initWithString:@"Out to lunch\nback at two"];
	XCTAssertEqualObjects(status.title, @"Out to lunch");
}

#pragma mark AIStatus construction

- (void)testStatusOfTypeSetsTheStatusType
{
	XCTAssertEqual([AIStatus statusOfType:AIInvisibleStatusType].statusType, AIInvisibleStatusType);
	XCTAssertEqual([AIStatus statusOfType:AIAvailableStatusType].statusType, AIAvailableStatusType);
}

- (void)testStatusWithDictionarySeedsTheStatus
{
	NSDictionary *dictionary = @{ STATUS_TITLE: @"Lunch",
								  STATUS_STATUS_TYPE: @(AIAwayStatusType),
								  STATUS_STATUS_NAME: @"Lunch",
								  STATUS_MUTE_SOUNDS: @YES,
								  STATUS_MUTABILITY_TYPE: @(AILockedStatusState) };
	AIStatus *status = [AIStatus statusWithDictionary:dictionary];
	XCTAssertEqualObjects(status.title, @"Lunch");
	XCTAssertEqual(status.statusType, AIAwayStatusType);
	XCTAssertEqualObjects(status.statusName, @"Lunch");
	XCTAssertTrue(status.mutesSound);
	XCTAssertEqual(status.mutabilityType, AILockedStatusState);
}

- (void)testStatusSurvivesKeyedArchiving
{
	AIStatus *status = [AIStatus status];
	[status setTitle:@"Lunch"];
	[status setStatusType:AIAwayStatusType];
	status.statusName = @"Lunch";
	status.statusMessageString = @"Out to lunch";
	status.mutesSound = YES;
	status.silencesNotifications = YES;
	status.specialStatusType = AINowPlayingSpecialStatusType;
	[status setMutabilityType:AITemporaryEditableStatusState];
	[status setUniqueStatusID:@9];

	AIStatus *copy = TStatusRoundTrip(status);
	XCTAssertTrue([copy isMemberOfClass:[AIStatus class]]);
	XCTAssertEqualObjects(copy.title, @"Lunch");
	XCTAssertEqual(copy.statusType, AIAwayStatusType);
	XCTAssertEqualObjects(copy.statusName, @"Lunch");
	XCTAssertEqualObjects(copy.statusMessageString, @"Out to lunch");
	XCTAssertTrue(copy.mutesSound);
	XCTAssertTrue(copy.silencesNotifications);
	XCTAssertEqual(copy.specialStatusType, AINowPlayingSpecialStatusType);
	XCTAssertEqual(copy.mutabilityType, AITemporaryEditableStatusState);
	XCTAssertEqual([copy preexistingUniqueStatusID], 9);
}

@end
