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

#import "AIMessageStateStore.h"
#import <Adium/AILoginControllerProtocol.h>
#import <Adium/AIChat.h>
#import <Adium/AIContentMessage.h>
#import <Adium/AIListObject.h>

#define MESSAGE_STATE_FILE_NAME		@"MessageState.plist"

/* Keys inside one message's record. Short because there is one record per
 * message and the file is read and written whole. */
#define KEY_CONFIRMATION			@"c"
#define KEY_REACTIONS				@"r"
#define KEY_TOUCHED					@"t"

/* What the file is allowed to grow to. A conversation's excerpt reaches a few
 * dozen messages back, so remembering the last few tens of thousands covers
 * every conversation a person is likely to reopen, and the oldest records are
 * dropped rather than the file growing for the life of the installation. */
#define MESSAGE_STATE_LIMIT			20000
#define MESSAGE_STATE_MAX_AGE		(60.0 * 60.0 * 24.0 * 90.0)

/* Writes are collected rather than made one at a time: a message being read
 * marks every message before it, which arrives here as a burst. */
#define MESSAGE_STATE_SAVE_DELAY	5.0

/* The two halves of the file: what is known about a message, and which line of
 * a transcript stands for which message. */
#define KEY_STATES					@"states"
#define KEY_IDENTITIES				@"identities"

@interface AIMessageStateStore ()
- (NSString *)keyForMessageId:(NSString *)messageId inChat:(AIChat *)chat;
- (NSMutableDictionary *)recordForKey:(NSString *)key creating:(BOOL)creating;
- (NSString *)identityForChat:(AIChat *)chat date:(NSDate *)date sender:(NSString *)senderUID;
- (NSString *)storePath;
- (void)scheduleSave;
- (void)save;
@end

@implementation AIMessageStateStore

+ (AIMessageStateStore *)sharedStore
{
	static AIMessageStateStore *sharedStore = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedStore = [[AIMessageStateStore alloc] init];
	});
	return sharedStore;
}

- (id)init
{
	if ((self = [super init])) {
		NSDictionary *file = [NSDictionary dictionaryWithContentsOfFile:[self storePath]];
		NSDictionary *stored = [file objectForKey:KEY_STATES];
		if (![stored isKindOfClass:[NSDictionary class]]) stored = nil;

		NSDictionary *storedIdentities = [file objectForKey:KEY_IDENTITIES];
		identities = [storedIdentities isKindOfClass:[NSDictionary class]] ?
					 [storedIdentities mutableCopy] : [[NSMutableDictionary alloc] init];

		states = [[NSMutableDictionary alloc] initWithCapacity:[stored count] + 64];

		/* The file holds immutable containers; the reaction buckets are written
		 * into, so they come back mutable. */
		for (NSString *messageId in stored) {
			NSDictionary *record = [stored objectForKey:messageId];
			if (![record isKindOfClass:[NSDictionary class]]) continue;

			NSMutableDictionary *mutableRecord = [record mutableCopy];
			NSDictionary *reactions = [record objectForKey:KEY_REACTIONS];
			if ([reactions isKindOfClass:[NSDictionary class]])
				[mutableRecord setObject:[reactions mutableCopy] forKey:KEY_REACTIONS];
			[states setObject:mutableRecord forKey:messageId];
		}

		/* Writes are collected for a few seconds, and quitting is exactly the
		 * moment that would otherwise throw the collection away. */
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(applicationWillTerminate:)
													 name:NSApplicationWillTerminateNotification
												   object:nil];
	}

	return self;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	if (saveScheduled) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(save) object:nil];
		[self save];
	}
}

- (void)dealloc
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

/* A file written by a later version, or damaged, must not be able to send a
 * selector to something that cannot answer it. */
static NSTimeInterval AITouchedValue(NSDictionary *record)
{
	NSNumber *touched = [record objectForKey:KEY_TOUCHED];
	return [touched isKindOfClass:[NSNumber class]] ? [touched doubleValue] : 0.0;
}

- (NSString *)storePath
{
	return [[adium.loginController userDirectory] stringByAppendingPathComponent:MESSAGE_STATE_FILE_NAME];
}

/*!
 * @brief A message id names a message only within its own conversation
 *
 * Two protocols, or two rooms, are free to hand out the same id, and one
 * conversation's ticks turning up on another's message is the kind of thing
 * nobody would think to look for.
 */
- (NSString *)keyForMessageId:(NSString *)messageId inChat:(AIChat *)chat
{
	if (![messageId length] || !chat) return nil;

	return [NSString stringWithFormat:@"%@\x1f%@", chat.uniqueChatID, messageId];
}

- (NSMutableDictionary *)recordForKey:(NSString *)key creating:(BOOL)creating
{
	if (![key length]) return nil;

	NSMutableDictionary *record = [states objectForKey:key];
	if (!record && creating) {
		record = [NSMutableDictionary dictionary];
		[states setObject:record forKey:key];
	}
	if (record && creating)
		[record setObject:[NSNumber numberWithDouble:[NSDate timeIntervalSinceReferenceDate]] forKey:KEY_TOUCHED];

	return record;
}

- (void)setConfirmation:(NSInteger)confirmation forMessageId:(NSString *)messageId inChat:(AIChat *)chat
{
	if (confirmation <= 0) return;

	NSMutableDictionary *record = [self recordForKey:[self keyForMessageId:messageId inChat:chat] creating:YES];
	if (!record) return;

	/* A message only ever travels forwards, and the confirmations for one
	 * message can arrive out of order when several land at once. */
	NSNumber *known = [record objectForKey:KEY_CONFIRMATION];
	if ([known isKindOfClass:[NSNumber class]] && [known integerValue] >= confirmation) return;

	[record setObject:[NSNumber numberWithInteger:confirmation] forKey:KEY_CONFIRMATION];
	[self scheduleSave];
}

- (void)setReactions:(NSArray *)reactions forSender:(NSString *)sender messageId:(NSString *)messageId inChat:(AIChat *)chat
{
	if (![sender length]) return;

	NSMutableDictionary *record = [self recordForKey:[self keyForMessageId:messageId inChat:chat] creating:YES];
	if (!record) return;

	NSMutableDictionary *buckets = [record objectForKey:KEY_REACTIONS];
	if (![buckets isKindOfClass:[NSMutableDictionary class]]) {
		buckets = [NSMutableDictionary dictionary];
		[record setObject:buckets forKey:KEY_REACTIONS];
	}

	NSArray *known = [buckets objectForKey:sender];
	if ((![reactions count] && !known) || (known && [known isEqualToArray:reactions])) return;

	if ([reactions count])
		[buckets setObject:reactions forKey:sender];
	else
		[buckets removeObjectForKey:sender];

	[self scheduleSave];
}

/*!
 * @brief One conversation, one second, one sender
 *
 * Coarse on purpose: it has to be worked out twice, once from a message and
 * once from a line of a transcript, and the second is all the two have in
 * common. Two messages from the same sender inside one second would be told
 * apart by nothing here, which costs one message the other one's ticks.
 */
- (NSString *)identityForChat:(AIChat *)chat date:(NSDate *)date sender:(NSString *)senderUID
{
	if (!chat || !date || ![senderUID length]) return nil;

	return [NSString stringWithFormat:@"%@\x1f%.0f\x1f%@",
			chat.uniqueChatID, floor([date timeIntervalSince1970]), senderUID];
}

- (void)rememberMessage:(AIContentMessage *)message inChat:(AIChat *)chat
{
	if (![message.messageId length]) return;

	NSString *identity = [self identityForChat:chat date:message.date sender:[[message source] UID]];
	NSString *key = [self keyForMessageId:message.messageId inChat:chat];
	if (!identity || !key) return;

	if ([[identities objectForKey:identity] isEqualToString:key]) return;

	/* The scoped key rather than the bare id, so that an identity can be dropped
	 * along with the record it names. */
	[identities setObject:key forKey:identity];
	[self scheduleSave];
}

- (NSString *)messageIdInChat:(AIChat *)chat date:(NSDate *)date sender:(NSString *)senderUID
{
	NSString *key = [identities objectForKey:[self identityForChat:chat date:date sender:senderUID]];
	NSRange separator = [key rangeOfString:@"\x1f"];

	return (separator.location == NSNotFound) ? nil : [key substringFromIndex:NSMaxRange(separator)];
}

- (NSInteger)confirmationForMessageId:(NSString *)messageId inChat:(AIChat *)chat
{
	NSNumber *confirmation = [[self recordForKey:[self keyForMessageId:messageId inChat:chat] creating:NO] objectForKey:KEY_CONFIRMATION];
	return [confirmation isKindOfClass:[NSNumber class]] ? [confirmation integerValue] : 0;
}

- (NSDictionary *)reactionsForMessageId:(NSString *)messageId inChat:(AIChat *)chat
{
	NSDictionary *buckets = [[self recordForKey:[self keyForMessageId:messageId inChat:chat] creating:NO] objectForKey:KEY_REACTIONS];
	if (![buckets isKindOfClass:[NSDictionary class]]) return nil;
	return [buckets count] ? buckets : nil;
}

- (void)scheduleSave
{
	if (saveScheduled) return;

	saveScheduled = YES;
	[self performSelector:@selector(save) withObject:nil afterDelay:MESSAGE_STATE_SAVE_DELAY];
}

- (void)save
{
	saveScheduled = NO;

	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	NSMutableArray *expired = [NSMutableArray array];
	for (NSString *messageId in states) {
		if (now - AITouchedValue([states objectForKey:messageId]) > MESSAGE_STATE_MAX_AGE)
			[expired addObject:messageId];
	}
	[states removeObjectsForKeys:expired];

	if ([states count] > MESSAGE_STATE_LIMIT) {
		NSArray *oldestFirst = [[states allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
			double ta = AITouchedValue([states objectForKey:a]);
			double tb = AITouchedValue([states objectForKey:b]);
			if (ta < tb) return NSOrderedAscending;
			if (ta > tb) return NSOrderedDescending;
			return NSOrderedSame;
		}];
		[states removeObjectsForKeys:[oldestFirst subarrayWithRange:NSMakeRange(0, [states count] - MESSAGE_STATE_LIMIT)]];
	}

	/* An identity is only worth keeping while the message it names still is. */
	NSMutableArray *orphaned = [NSMutableArray array];
	for (NSString *identity in identities) {
		if (![states objectForKey:[identities objectForKey:identity]]) [orphaned addObject:identity];
	}
	[identities removeObjectsForKeys:orphaned];

	NSDictionary *file = [NSDictionary dictionaryWithObjectsAndKeys:
						  states, KEY_STATES,
						  identities, KEY_IDENTITIES,
						  nil];
	if (![file writeToFile:[self storePath] atomically:YES]) {
		AILogWithSignature(@"could not write %@", [self storePath]);
		[self scheduleSave];
	}
}

@end
