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
#import <Adium/AIContentObject.h>
#import <Adium/AIContentMessage.h>
#import <Adium/AIContentContext.h>
#import <Adium/AIContentStatus.h>
#import <Adium/AIContentEvent.h>
#import <Adium/AIContentTyping.h>
#import <Adium/AIContentNotification.h>
#import <Adium/AIListObject.h>
#import <Adium/AIService.h>
#import <Adium/AIAccount.h>
#import <Adium/AIAbstractAccount.h>

//2020-01-15 12:00:00 UTC: noon, so that the same-day tests read the same in every time zone
static const NSTimeInterval TCONoon = 1579089600;

static NSDate *TCODate(NSTimeInterval secondsAfterNoon)
{
	return [NSDate dateWithTimeIntervalSince1970:TCONoon + secondsAfterNoon];
}

static NSAttributedString *TCOText(NSString *string)
{
	return [[NSAttributedString alloc] initWithString:string];
}

static AIContentMessage *TCOMessage(AIListObject *source, NSTimeInterval secondsAfterNoon)
{
	return [AIContentMessage messageInChat:nil withSource:source destination:nil date:TCODate(secondsAfterNoon) message:TCOText(@"hello") autoreply:NO];
}

/* An account is what makes content outgoing. One is constructible here because every controller
 * it would report to is nil, and its service exists only to name it. */
static AIAccount *TCOAccount(void)
{
	AIService *service = [[AIService alloc] init];
	return [[AIAccount alloc] initWithUID:@"me" internalObjectID:@"ContentTest.me" service:service];
}

static AIListObject *TCOContact(NSString *UID)
{
	return [[AIListObject alloc] initWithUID:UID service:nil];
}

@interface TestContentObject : XCTestCase
@end

@implementation TestContentObject

#pragma mark Construction

- (void)testContentKeepsWhatItWasCreatedWith
{
	AIListObject *source = TCOContact(@"alice");
	AIListObject *destination = TCOContact(@"bob");
	NSAttributedString *text = TCOText(@"hello");
	AIContentObject *content = [[AIContentObject alloc] initWithChat:nil source:source destination:destination date:TCODate(0) message:text];

	XCTAssertTrue(content.source == source);
	XCTAssertTrue(content.destination == destination);
	XCTAssertEqualObjects(content.date, TCODate(0));
	XCTAssertEqualObjects(content.message, text);
	XCTAssertNil(content.chat);
	XCTAssertNil(content.userInfo);
}

- (void)testContentWithoutAMessageHasNone
{
	AIContentObject *content = [[AIContentObject alloc] initWithChat:nil source:nil destination:nil date:TCODate(0)];
	XCTAssertNil(content.message);
}

- (void)testBehaviourFlagsDefaultToYes
{
	AIContentObject *content = [[AIContentObject alloc] initWithChat:nil source:nil destination:nil date:TCODate(0)];
	XCTAssertTrue(content.filterContent);
	XCTAssertTrue(content.trackContent);
	XCTAssertTrue(content.displayContent);
	XCTAssertTrue(content.displayContentImmediately);
	XCTAssertTrue(content.sendContent);
	XCTAssertTrue(content.postProcessContent);
}

- (void)testBehaviourFlagsCanBeTurnedOff
{
	AIContentObject *content = [[AIContentObject alloc] initWithChat:nil source:nil destination:nil date:TCODate(0)];
	content.filterContent = NO;
	content.trackContent = NO;
	content.displayContent = NO;
	content.displayContentImmediately = NO;
	content.sendContent = NO;
	content.postProcessContent = NO;
	XCTAssertFalse(content.filterContent);
	XCTAssertFalse(content.trackContent);
	XCTAssertFalse(content.displayContent);
	XCTAssertFalse(content.displayContentImmediately);
	XCTAssertFalse(content.sendContent);
	XCTAssertFalse(content.postProcessContent);
}

- (void)testDateIsNeverLeftEmpty
{
	AIContentObject *content = [[AIContentObject alloc] initWithChat:nil source:nil destination:nil date:nil];
	XCTAssertNotNil(content.date);
}

- (void)testUserInfoIsKeptAndCanBeCleared
{
	AIContentObject *content = [[AIContentObject alloc] initWithChat:nil source:nil destination:nil date:TCODate(0)];
	NSMutableArray *info = [NSMutableArray array];
	content.userInfo = info;
	XCTAssertTrue(content.userInfo == info, @"kept, not copied");
	content.userInfo = nil;
	XCTAssertNil(content.userInfo);
}

- (void)testMessageCanBeReplaced
{
	AIContentObject *content = [[AIContentObject alloc] initWithChat:nil source:nil destination:nil date:TCODate(0) message:TCOText(@"first")];
	content.message = TCOText(@"second");
	XCTAssertEqualObjects(content.message.string, @"second");
}

- (void)testMessageStringIsThePlainTextOfTheMessage
{
	AIContentObject *content = [[AIContentObject alloc] initWithChat:nil source:nil destination:nil date:TCODate(0) message:TCOText(@"hello")];
	XCTAssertEqualObjects(content.messageString, @"hello");
}

#pragma mark Direction

- (void)testContentFromNoSourceIsIncoming
{
	AIContentMessage *message = TCOMessage(nil, 0);
	XCTAssertFalse(message.isOutgoing);
	XCTAssertTrue([message.displayClasses containsObject:@"incoming"]);
	XCTAssertFalse([message.displayClasses containsObject:@"outgoing"]);
}

- (void)testContentFromAContactIsIncoming
{
	AIContentMessage *message = TCOMessage(TCOContact(@"alice"), 0);
	XCTAssertFalse(message.isOutgoing);
	XCTAssertTrue([message.displayClasses containsObject:@"incoming"]);
}

- (void)testContentFromAnAccountIsOutgoing
{
	AIContentMessage *message = TCOMessage(TCOAccount(), 0);
	XCTAssertTrue(message.isOutgoing);
	XCTAssertTrue([message.displayClasses containsObject:@"outgoing"]);
	XCTAssertFalse([message.displayClasses containsObject:@"incoming"]);
}

- (void)testCustomDisplayClassesComeFirst
{
	AIContentMessage *message = TCOMessage(nil, 0);
	[message addDisplayClass:@"mention"];
	[message addDisplayClass:@"highlight"];
	NSArray *classes = message.displayClasses;
	XCTAssertEqualObjects([classes subarrayWithRange:NSMakeRange(0, 2)], (@[@"mention", @"highlight"]));
	XCTAssertTrue([classes containsObject:@"incoming"]);
}

#pragma mark Comparing

- (void)testContentIsSimilarWhenSourceAndTypeMatchWithinFiveMinutes
{
	AIListObject *alice = TCOContact(@"alice");
	AIContentMessage *first = TCOMessage(alice, 0);
	AIContentMessage *second = TCOMessage(alice, 4 * 60);
	XCTAssertTrue([first isSimilarToContent:second]);
	XCTAssertTrue([second isSimilarToContent:first], @"similarity is symmetric");
	XCTAssertTrue([first isSimilarToContent:first]);
}

- (void)testContentMoreThanFiveMinutesApartIsNotSimilar
{
	AIListObject *alice = TCOContact(@"alice");
	AIContentMessage *first = TCOMessage(alice, 0);
	AIContentMessage *later = TCOMessage(alice, 6 * 60);
	XCTAssertFalse([first isSimilarToContent:later]);
	XCTAssertFalse([later isSimilarToContent:first]);
}

- (void)testContentOfDifferentTypesIsNotSimilar
{
	AIContentMessage *message = TCOMessage(nil, 0);
	AIContentContext *context = [AIContentContext messageInChat:nil withSource:nil destination:nil date:TCODate(0) message:TCOText(@"hello") autoreply:NO];
	XCTAssertFalse([message isSimilarToContent:context]);
	XCTAssertFalse([context isSimilarToContent:message]);
}

- (void)testContentFromDifferentSourcesIsNotSimilar
{
	AIContentMessage *fromAlice = TCOMessage(TCOContact(@"alice"), 0);
	AIContentMessage *fromBob = TCOMessage(TCOContact(@"bob"), 0);
	XCTAssertFalse([fromAlice isSimilarToContent:fromBob]);
}

- (void)testAnAutoreplyIsNotSimilarToAPlainMessage
{
	AIContentMessage *plain = TCOMessage(nil, 0);
	AIContentMessage *autoreply = [AIContentMessage messageInChat:nil withSource:nil destination:nil date:TCODate(0) message:TCOText(@"away") autoreply:YES];
	XCTAssertFalse([plain isSimilarToContent:autoreply]);
	XCTAssertFalse([autoreply isSimilarToContent:plain]);
}

- (void)testAMentionIsNotSimilarToAPlainMessage
{
	AIContentMessage *plain = TCOMessage(nil, 0);
	AIContentMessage *mention = TCOMessage(nil, 0);
	[mention addDisplayClass:@"mention"];
	XCTAssertFalse([plain isSimilarToContent:mention]);
	XCTAssertFalse([mention isSimilarToContent:plain]);
}

- (void)testSameDayIsJudgedByCalendarDay
{
	AIContentMessage *noon = TCOMessage(nil, 0);
	AIContentMessage *halfPastNoon = TCOMessage(nil, 30 * 60);
	AIContentMessage *twoDaysOn = TCOMessage(nil, 48 * 60 * 60);
	XCTAssertTrue([noon isFromSameDayAsContent:halfPastNoon]);
	XCTAssertTrue([halfPastNoon isFromSameDayAsContent:noon]);
	XCTAssertFalse([noon isFromSameDayAsContent:twoDaysOn]);
	XCTAssertFalse([twoDaysOn isFromSameDayAsContent:noon]);
}

#pragma mark AIContentStatus

- (void)testStatusContentCarriesItsStatusType
{
	AIContentStatus *status = [AIContentStatus statusInChat:nil withSource:nil destination:nil date:TCODate(0) message:TCOText(@"went away") withType:@"away"];
	XCTAssertEqualObjects(status.type, CONTENT_STATUS_TYPE);
	XCTAssertEqualObjects(status.status, @"away");
	XCTAssertEqualObjects(status.message.string, @"went away");
	XCTAssertTrue(status.filterContent, @"filtered, so triggers in the text are resolved");
	XCTAssertFalse(status.trackContent, @"but a status change raises no events");
}

- (void)testStatusContentHasNoDirectionClass
{
	AIContentStatus *incoming = [AIContentStatus statusInChat:nil withSource:TCOContact(@"alice") destination:nil date:TCODate(0) message:nil withType:@"away"];
	AIContentStatus *outgoing = [AIContentStatus statusInChat:nil withSource:TCOAccount() destination:nil date:TCODate(0) message:nil withType:@"away"];
	XCTAssertEqualObjects(incoming.displayClasses, (@[@"status", @"away"]));
	XCTAssertEqualObjects(outgoing.displayClasses, (@[@"status", @"away"]));
}

- (void)testStatusContentCoalescingKeyAndLoggedMessageRoundTrip
{
	AIContentStatus *status = [AIContentStatus statusInChat:nil withSource:nil destination:nil date:TCODate(0) message:nil withType:@"away"];
	XCTAssertNil(status.coalescingKey);
	XCTAssertNil(status.loggedMessage);

	NSMutableString *key = [NSMutableString stringWithString:@"alice-away"];
	status.coalescingKey = key;
	[key appendString:@"-changed"];
	XCTAssertEqualObjects(status.coalescingKey, @"alice-away", @"the key is copied");

	status.loggedMessage = TCOText(@"Alice went away");
	XCTAssertEqualObjects(status.loggedMessage.string, @"Alice went away");
}

#pragma mark AIContentEvent

- (void)testEventContentIsAnEventNotAStatus
{
	AIContentEvent *event = [AIContentEvent eventInChat:nil withSource:nil destination:nil date:TCODate(0) message:TCOText(@"joined") withType:@"joined"];
	XCTAssertEqualObjects(event.type, CONTENT_EVENT_TYPE);
	XCTAssertEqualObjects(event.eventType, @"joined");
	XCTAssertEqualObjects(event.displayClasses, (@[@"joined", @"event"]));
}

- (void)testEventLoggedMessageIsItsMessage
{
	AIContentEvent *event = [AIContentEvent eventInChat:nil withSource:nil destination:nil date:TCODate(0) message:TCOText(@"joined") withType:@"joined"];
	XCTAssertEqualObjects(event.loggedMessage, event.message);
}

#pragma mark AIContentTyping

- (void)testTypingContentIsNeitherFilteredTrackedNorDisplayed
{
	AIContentTyping *typing = [AIContentTyping typingContentInChat:nil withSource:nil destination:nil typingState:AITyping];
	XCTAssertEqualObjects(typing.type, CONTENT_TYPING_TYPE);
	XCTAssertEqual(typing.typingState, AITyping);
	XCTAssertFalse(typing.filterContent);
	XCTAssertFalse(typing.trackContent);
	XCTAssertFalse(typing.displayContent);
	XCTAssertTrue(typing.sendContent, @"it is still sent");
	XCTAssertNil(typing.message);
	XCTAssertNotNil(typing.date);
}

- (void)testTypingStateIsWhatWasAsked
{
	AIContentTyping *notTyping = [AIContentTyping typingContentInChat:nil withSource:nil destination:nil typingState:AINotTyping];
	AIContentTyping *enteredText = [AIContentTyping typingContentInChat:nil withSource:nil destination:nil typingState:AIEnteredText];
	XCTAssertEqual(notTyping.typingState, AINotTyping);
	XCTAssertEqual(enteredText.typingState, AIEnteredText);
}

#pragma mark AIContentNotification

- (void)testNotificationWithoutASourceHasAGenericMessage
{
	AIContentNotification *notification = [AIContentNotification notificationInChat:nil withSource:nil destination:nil date:TCODate(0) notificationType:AIDefaultNotificationType];
	XCTAssertTrue(notification.message.length > 0);
}

- (void)testNotificationFromAContactNamesTheContact
{
	AIListObject *alice = TCOContact(@"alice");
	AIContentNotification *notification = [AIContentNotification notificationInChat:nil withSource:alice destination:nil date:TCODate(0) notificationType:AIDefaultNotificationType];
	XCTAssertTrue([notification.message.string containsString:alice.displayName]);
	XCTAssertFalse(notification.isOutgoing);
}

- (void)testNotificationFromAnAccountNamesTheRecipient
{
	AIListObject *bob = TCOContact(@"bob");
	AIContentNotification *notification = [AIContentNotification notificationInChat:nil withSource:TCOAccount() destination:bob date:TCODate(0) notificationType:AIDefaultNotificationType];
	XCTAssertTrue([notification.message.string containsString:bob.displayName]);
	XCTAssertTrue(notification.isOutgoing);
}

- (void)testNotificationTypeAndClasses
{
	AIContentNotification *notification = [AIContentNotification notificationInChat:nil withSource:nil destination:nil date:TCODate(0) notificationType:AIDefaultNotificationType];
	XCTAssertEqualObjects(notification.type, CONTENT_NOTIFICATION_TYPE);
	XCTAssertEqualObjects(notification.eventType, CONTENT_NOTIFICATION_TYPE);
	XCTAssertEqualObjects(notification.status, @"notification");
	XCTAssertEqual(notification.notificationType, AIDefaultNotificationType);
	XCTAssertEqualObjects(notification.displayClasses, (@[@"notification", @"event"]));
	XCTAssertFalse(notification.trackContent);
	XCTAssertEqualObjects(notification.date, TCODate(0));
}

@end
