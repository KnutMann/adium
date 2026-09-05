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

#import "AIInlineImageLinkPlugin.h"

#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIFileTransferControllerProtocol.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <Adium/AIContentMessage.h>
#import <Adium/AIContentContext.h>
#import <Adium/AIChat.h>
#import <Adium/AIAccount.h>
#import <Adium/AIService.h>
#import <Adium/AIListContact.h>
#import <CommonCrypto/CommonDigest.h>

//Announced to the message view once a picture is on disk; also reapplied on page rebuilds
NSString *const AIChatMessageImageResolved = @"AIChatMessageImageResolved";

/* Past this the picture stays a link. The cap is checked against what actually
 * arrived: upload services rarely answer HEAD requests usefully, so the size is
 * not known before fetching. The policy below keeps strangers from making us
 * fetch anything at all. */
#define INLINE_IMAGE_MAX_BYTES		(10 * 1024 * 1024)

@implementation AIInlineImageLinkPlugin

- (void)installPlugin
{
	NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];

	configuration.timeoutIntervalForRequest = 30;
	session = [NSURLSession sessionWithConfiguration:configuration];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(contentObjectAdded:)
												 name:Content_ContentObjectAdded
											   object:nil];
}

- (void)uninstallPlugin
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[session invalidateAndCancel];
}

/*!
 * @brief The image address a message consists of, or nil
 *
 * A picture sent by a modern XMPP client (XEP-0363 upload, announced per XEP-0066)
 * arrives as a message whose whole content is one https address ending in the
 * file's name. Anything with more words than that is a sentence containing a link
 * and stays one.
 */
static NSString *AIImageAddressInMessage(AIContentMessage *message)
{
	NSString *text = [[[message message] string] stringByTrimmingCharactersInSet:
					  [NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if (![text hasPrefix:@"https://"])
		return nil;

	if ([text rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound)
		return nil;

	NSURL *url = [NSURL URLWithString:text];
	static NSSet *imageExtensions = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		imageExtensions = [NSSet setWithObjects:@"jpg", @"jpeg", @"png", @"gif", @"webp", nil];
	});

	if (![imageExtensions containsObject:[[url pathExtension] lowercaseString]])
		return nil;

	return text;
}

- (void)contentObjectAdded:(NSNotification *)notification
{
	AIContentObject *object = [[notification userInfo] objectForKey:@"AIContentObject"];

	/* Live incoming messages only: isMemberOfClass excludes AIContentContext, so
	 * scrolled-in history does not fetch anything, and our own messages stay as
	 * they were written. */
	if (![object isMemberOfClass:[AIContentMessage class]] || [object isOutgoing])
		return;

	AIContentMessage *message = (AIContentMessage *)object;
	AIChat *chat = [[notification userInfo] objectForKey:@"AIChat"];

	if (![chat.account.service.serviceClass isEqualToString:@"Jabber"])
		return;

	//Without an id the picture could not find its message on the page again
	if (![message.messageId length] || [message.inlineImagePath length])
		return;

	NSString *address = AIImageAddressInMessage(message);
	if (!address)
		return;

	/* The say the person already has over file transfers governs whose pictures
	 * load themselves: never, from anyone, or only from contacts of their list. */
	AIFileTransferAutoAcceptType autoAccept =
		[[adium.preferenceController preferenceForKey:KEY_FT_AUTO_ACCEPT
												group:PREF_GROUP_FILE_TRANSFER] intValue];

	if (autoAccept == AutoAccept_None)
		return;

	if (autoAccept == AutoAccept_FromContactList) {
		AIListObject *source = [message source];

		if (![source isKindOfClass:[AIListContact class]] ||
			![(AIListContact *)source isIntentionallyNotAStranger])
			return;
	}

	[self fetchImageAtAddress:address forMessage:message inChat:chat];
}

/*!
 * @brief Where a fetched address is kept, the same place for the same address
 */
static NSString *AIInlineImageCachePath(NSString *address)
{
	const char *bytes = [address UTF8String];
	unsigned char digest[CC_SHA256_DIGEST_LENGTH];

	CC_SHA256(bytes, (CC_LONG)strlen(bytes), digest);

	NSMutableString *name = [NSMutableString stringWithCapacity:(CC_SHA256_DIGEST_LENGTH * 2)];
	for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++)
		[name appendFormat:@"%02x", digest[index]];

	[name appendFormat:@".%@", [[[NSURL URLWithString:address] pathExtension] lowercaseString]];

	return [[[adium cachesPath] stringByAppendingPathComponent:@"Inline Images"]
			stringByAppendingPathComponent:name];
}

- (void)fetchImageAtAddress:(NSString *)address forMessage:(AIContentMessage *)message inChat:(AIChat *)chat
{
	NSString *destination = AIInlineImageCachePath(address);

	if ([[NSFileManager defaultManager] fileExistsAtPath:destination]) {
		[self announceImageAtPath:destination forMessage:message inChat:chat];
		return;
	}

	__weak AIInlineImageLinkPlugin *weakSelf = self;

	[[session dataTaskWithURL:[NSURL URLWithString:address]
			completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		if (error || ![response isKindOfClass:[NSHTTPURLResponse class]])
			return;
		if ([(NSHTTPURLResponse *)response statusCode] != 200)
			return;
		if (![[response MIMEType] hasPrefix:@"image/"])
			return;
		if (![data length] || [data length] > INLINE_IMAGE_MAX_BYTES)
			return;

		[[NSFileManager defaultManager] createDirectoryAtPath:[destination stringByDeletingLastPathComponent]
								  withIntermediateDirectories:YES
												   attributes:nil
														error:NULL];
		if (![data writeToFile:destination atomically:YES])
			return;

		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf announceImageAtPath:destination forMessage:message inChat:chat];
		});
	}] resume];
}

- (void)announceImageAtPath:(NSString *)path forMessage:(AIContentMessage *)message inChat:(AIChat *)chat
{
	/* On the message first, so a page rebuilt later re-embeds from there; the
	 * notification only reaches the view that is showing the chat right now. */
	message.inlineImagePath = path;

	[[NSNotificationCenter defaultCenter] postNotificationName:AIChatMessageImageResolved
														object:chat
													  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
																message.messageId, @"MessageId",
																path, @"Path", nil]];
}

@end
