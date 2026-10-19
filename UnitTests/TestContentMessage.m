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
#import <Adium/AIContentMessage.h>
#import <Adium/AIContentContext.h>
#import <Adium/AIContentTopic.h>
#import <Adium/AIListObject.h>

static NSDate *TCMDate(void)
{
	return [NSDate dateWithTimeIntervalSince1970:1579089600];
}

static NSAttributedString *TCMText(NSString *string)
{
	return [[NSAttributedString alloc] initWithString:string];
}

static AIContentMessage *TCMMessage(BOOL autoreply)
{
	return [AIContentMessage messageInChat:nil withSource:nil destination:nil date:TCMDate() message:TCMText(@"hello") autoreply:autoreply];
}

@interface TestContentMessage : XCTestCase
@end

@implementation TestContentMessage

#pragma mark AIContentMessage

- (void)testMessageIsBuiltFromWhatTheFactoryIsGiven
{
	AIListObject *alice = [[AIListObject alloc] initWithUID:@"alice" service:nil];
	AIListObject *bob = [[AIListObject alloc] initWithUID:@"bob" service:nil];
	NSAttributedString *text = TCMText(@"hello");
	AIContentMessage *message = [AIContentMessage messageInChat:nil withSource:alice destination:bob date:TCMDate() message:text autoreply:YES];

	XCTAssertEqualObjects(message.type, CONTENT_MESSAGE_TYPE);
	XCTAssertTrue(message.source == alice);
	XCTAssertTrue(message.destination == bob);
	XCTAssertEqualObjects(message.date, TCMDate());
	XCTAssertEqualObjects(message.message, text);
	XCTAssertTrue(message.isAutoreply);
}

- (void)testMessageDisplayClassesSayMessageAndAutoreply
{
	XCTAssertEqualObjects(TCMMessage(NO).displayClasses, (@[@"incoming", @"message"]));
	XCTAssertEqualObjects(TCMMessage(YES).displayClasses, (@[@"incoming", @"message", @"autoreply"]));
}

- (void)testAutoreplyCanBeChangedAfterwards
{
	AIContentMessage *message = TCMMessage(NO);
	message.isAutoreply = YES;
	XCTAssertTrue(message.isAutoreply);
	XCTAssertTrue([message.displayClasses containsObject:@"autoreply"]);
}

- (void)testSenderPrefixIsEmptyOutsideAGroupChat
{
	XCTAssertEqualObjects(TCMMessage(NO).senderPrefix, @"");
}

- (void)testEncodedMessageAndAccountDataStartEmptyAndAreKept
{
	AIContentMessage *message = TCMMessage(NO);
	XCTAssertNil(message.encodedMessage);
	XCTAssertNil(message.encodedMessageAccountData);

	NSMutableDictionary *accountData = [NSMutableDictionary dictionary];
	message.encodedMessage = @"<b>hello</b>";
	message.encodedMessageAccountData = accountData;
	XCTAssertEqualObjects(message.encodedMessage, @"<b>hello</b>");
	XCTAssertTrue(message.encodedMessageAccountData == accountData);
}

- (void)testMessageIdIsNilUntilTheProtocolSuppliesOneAndIsCopied
{
	AIContentMessage *message = TCMMessage(NO);
	XCTAssertNil(message.messageId);

	NSMutableString *stanzaId = [NSMutableString stringWithString:@"abc-123"];
	message.messageId = stanzaId;
	[stanzaId appendString:@"-mutated"];
	XCTAssertEqualObjects(message.messageId, @"abc-123");
}

- (void)testConfirmationStartsAtNothingConfirmed
{
	AIContentMessage *message = TCMMessage(NO);
	XCTAssertEqual(message.confirmation, (NSInteger)0);
	message.confirmation = 3;
	XCTAssertEqual(message.confirmation, (NSInteger)3);
}

- (void)testReactionsAreNilUntilSomebodyReacts
{
	AIContentMessage *message = TCMMessage(NO);
	XCTAssertNil(message.reactions);
	NSMutableDictionary *reactions = [NSMutableDictionary dictionaryWithObject:@[@"\U0001F44D"] forKey:@"alice"];
	message.reactions = reactions;
	XCTAssertTrue(message.reactions == reactions);
}

- (void)testInlineImagePathAndCorrectionIdAreCopied
{
	AIContentMessage *message = TCMMessage(NO);
	XCTAssertNil(message.inlineImagePath);
	XCTAssertNil(message.correctsMessageId);

	NSMutableString *path = [NSMutableString stringWithString:@"/tmp/picture.png"];
	NSMutableString *corrected = [NSMutableString stringWithString:@"earlier-id"];
	message.inlineImagePath = path;
	message.correctsMessageId = corrected;
	[path appendString:@".bak"];
	[corrected appendString:@"-mutated"];
	XCTAssertEqualObjects(message.inlineImagePath, @"/tmp/picture.png");
	XCTAssertEqualObjects(message.correctsMessageId, @"earlier-id");
}

#pragma mark AIContentContext

- (void)testContextIsAMessageRestoredFromHistory
{
	AIContentContext *context = [AIContentContext messageInChat:nil withSource:nil destination:nil date:TCMDate() message:TCMText(@"earlier") autoreply:NO];
	XCTAssertEqualObjects(context.type, CONTENT_CONTEXT_TYPE);
	XCTAssertEqualObjects(context.message.string, @"earlier");
	XCTAssertTrue([context.displayClasses containsObject:@"message"]);
	XCTAssertTrue([context.displayClasses containsObject:@"history"]);
	XCTAssertFalse([context isSimilarToContent:TCMMessage(NO)], @"history and live messages are not grouped together");
}

#pragma mark AIContentTopic

- (void)testTopicIsAMessageThatIsNeverAnAutoreply
{
	AIContentTopic *topic = [AIContentTopic topicInChat:nil withSource:nil destination:nil date:TCMDate() message:TCMText(@"Welcome")];
	XCTAssertEqualObjects(topic.type, CONTENT_TOPIC_TYPE);
	XCTAssertEqualObjects(topic.message.string, @"Welcome");
	XCTAssertFalse(topic.isAutoreply);
	XCTAssertFalse([topic.displayClasses containsObject:@"autoreply"]);
}

- (void)testTopicIsNotBlankUnlessSaidSo
{
	AIContentTopic *topic = [AIContentTopic topicInChat:nil withSource:nil destination:nil date:TCMDate() message:TCMText(@"")];
	XCTAssertFalse(topic.actuallyBlank);
	topic.actuallyBlank = YES;
	XCTAssertTrue(topic.actuallyBlank);
}

@end
