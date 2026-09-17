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

#import "AIInlineMediaLinkPlugin.h"

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
#import <AdiumLibpurple/AIOMEMOMedia.h>

//Announced to the message view once the file is on disk; also reapplied on page rebuilds
NSString *const AIChatMessageImageResolved = @"AIChatMessageImageResolved";

/*!
 * @brief What a message's address turned out to point at
 *
 * Kept together because the three travel as one: where it is, what unlocks it if anything, and
 * what sort of thing it is once opened.
 */
@interface AIMediaLink : NSObject
@property (readwrite, nonatomic, copy) NSString *address;		//always https, ready to fetch
@property (readwrite, nonatomic, copy) NSString *original;		//as written, for the cache name
@property (readwrite, nonatomic, strong) NSData *ivAndKey;		//nil when it is not encrypted
@property (readwrite, nonatomic, copy) NSString *extension;
@end

@implementation AIMediaLink
@end

/* Past this it stays a link. The cap is checked against what actually arrived:
 * upload services rarely answer HEAD requests usefully, so the size is not known
 * before fetching. The policy below keeps strangers from making us fetch anything
 * at all. Generous enough for a voice note of any sensible length. */
#define INLINE_MEDIA_MAX_BYTES		(25 * 1024 * 1024)

@implementation AIInlineMediaLinkPlugin

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
 * @brief Everything we are willing to fetch, by the end of the file's name
 *
 * A list rather than a guess, and a short one. What is not on it stays a link, which is the
 * safe way round: a thing we do not fetch is a link the person can still click.
 */
static NSString *AIKindOfFile(NSString *extension)
{
	static NSDictionary *kinds = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		kinds = @{
			@"jpg": @"image", @"jpeg": @"image", @"png": @"image", @"gif": @"image", @"webp": @"image",
			//Voice notes, in the forms the clients that send them actually use
			@"m4a": @"audio", @"mp3": @"audio", @"oga": @"audio", @"ogg": @"audio",
			@"opus": @"audio", @"wav": @"audio", @"aac": @"audio", @"amr": @"audio",
			@"mp4": @"video", @"mov": @"video", @"webm": @"video", @"m4v": @"video"
		};
	});
	return kinds[[extension lowercaseString]];
}

NSString *AIMediaNameForMessageText(NSString *text)
{
	NSString *trimmed = [text stringByTrimmingCharactersInSet:
						 [NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if ([trimmed rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound)
		return nil;

	NSString *lowered = [trimmed lowercaseString];
	if (![lowered hasPrefix:@"https://"] && ![lowered hasPrefix:@"aesgcm://"])
		return nil;

	NSString *kind = AIKindOfFile(AIOMEMOMediaExtensionOf(trimmed));

	/* Named through the bundle this class lives in rather than the usual shorthand, which wants
	 * a self there is none of out here. */
	NSBundle *ours = [NSBundle bundleForClass:[AIInlineMediaLinkPlugin class]];

	if ([kind isEqualToString:@"image"])
		return AILocalizedStringFromTableInBundle(@"a picture", nil, ours, "what a message that is only a picture's address is called");
	if ([kind isEqualToString:@"audio"])
		return AILocalizedStringFromTableInBundle(@"a voice message", nil, ours, "what a message that is only a voice note's address is called");
	if ([kind isEqualToString:@"video"])
		return AILocalizedStringFromTableInBundle(@"a video", nil, ours, "what a message that is only a video's address is called");

	return nil;
}

/*!
 * @brief The file a message consists of, or nil
 *
 * A picture or a voice note sent by a modern XMPP client (XEP-0363 upload, announced per
 * XEP-0066) arrives as a message whose whole content is one address ending in the file's name.
 * Anything with more words than that is a sentence containing a link and stays one.
 *
 * In an encrypted conversation the same thing arrives as an aesgcm address (XEP-0454): the same
 * file, on the same server, with the key to it written into the address itself.
 */
static AIMediaLink *AIMediaLinkInMessage(AIContentMessage *message)
{
	NSString *text = [[[message message] string] stringByTrimmingCharactersInSet:
					  [NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if ([text rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound)
		return nil;

	NSString *address = nil;
	NSData *ivAndKey = nil;

	if (!AIOMEMOMediaReadLink(text, &address, &ivAndKey)) {
		if (![text hasPrefix:@"https://"]) return nil;
		address = text;
	}

	NSString *extension = [[[NSURL URLWithString:address] pathExtension] lowercaseString];
	if (![AIKindOfFile(extension) length]) return nil;

	AIMediaLink *found = [[AIMediaLink alloc] init];
	found.address = address;
	found.original = text;
	found.ivAndKey = ivAndKey;
	found.extension = extension;
	return found;
}

- (void)contentObjectAdded:(NSNotification *)notification
{
	AIContentObject *object = [[notification userInfo] objectForKey:@"AIContentObject"];

	if (![object isKindOfClass:[AIContentMessage class]] || [object isOutgoing])
		return;

	/* History is shown, never fetched. Scrolling back through a year of conversation must not
	 * reach out to a year of servers, and what was said then is not a reason to ask anybody for
	 * anything now. But a picture already sitting in the cache costs nothing to show, and
	 * leaving it as an address there while the same message shows a picture a screen below is
	 * merely inconsistent. */
	BOOL fromTheLog = ![object isMemberOfClass:[AIContentMessage class]];

	AIContentMessage *message = (AIContentMessage *)object;
	AIChat *chat = [[notification userInfo] objectForKey:@"AIChat"];

	if (![chat.account.service.serviceClass isEqualToString:@"Jabber"])
		return;

	//Without an id the picture could not find its message on the page again
	if (![message.messageId length] || [message.inlineImagePath length])
		return;

	AIMediaLink *link = AIMediaLinkInMessage(message);
	if (!link)
		return;

	if (fromTheLog) {
		NSString *kept = AIInlineImageCachePath(link.original, link.extension);

		if ([[NSFileManager defaultManager] fileExistsAtPath:kept]) {
			AILogWithSignature(@"%@ was fetched before, showing it again from %@",
							   link.address, [kept lastPathComponent]);
			[self announceImageAtPath:kept forMessage:message inChat:chat];
		}
		return;
	}

	/* From here on it says what it does. Everything below can decline for a reason the person
	 * never sees, and a picture that silently stays an address is indistinguishable from one
	 * this code never looked at. */
	AILogWithSignature(@"%@ looks like a %@ to fetch%@", link.address,
					   AIKindOfFile(link.extension), link.ivAndKey ? @", encrypted" : @"");

	/* The say the person already has over file transfers governs whose files load
	 * themselves: never, from anyone, or only from contacts of their list. */
	AIFileTransferAutoAcceptType autoAccept =
		[[adium.preferenceController preferenceForKey:KEY_FT_AUTO_ACCEPT
												group:PREF_GROUP_FILE_TRANSFER] intValue];

	if (autoAccept == AutoAccept_None) {
		AILogWithSignature(@"leaving it as a link: files are never fetched by themselves here");
		return;
	}

	if (autoAccept == AutoAccept_FromContactList) {
		AIListObject *source = [message source];

		if (![source isKindOfClass:[AIListContact class]] ||
			![(AIListContact *)source isIntentionallyNotAStranger]) {
			AILogWithSignature(@"leaving it as a link: %@ is not on the contact list, and only "
								"contacts' files are fetched by themselves here", source);
			return;
		}
	}

	[self fetchMedia:link forMessage:message inChat:chat];
}

/*!
 * @brief Where a fetched address is kept, the same place for the same address
 *
 * Named after the address as it was WRITTEN, key and all, so that two different files that
 * happen to sit at the same place cannot be confused for one another, and so that the same
 * message scrolled past twice is only fetched once.
 */
static NSString *AIInlineImageCachePath(NSString *address, NSString *extension)
{
	const char *bytes = [address UTF8String];
	unsigned char digest[CC_SHA256_DIGEST_LENGTH];

	CC_SHA256(bytes, (CC_LONG)strlen(bytes), digest);

	NSMutableString *name = [NSMutableString stringWithCapacity:(CC_SHA256_DIGEST_LENGTH * 2)];
	for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++)
		[name appendFormat:@"%02x", digest[index]];

	/* The extension is kept, and it is not decoration: it is what the message view reads to
	 * decide whether this becomes a picture or a player. */
	[name appendFormat:@".%@", extension];

	return [[[adium cachesPath] stringByAppendingPathComponent:@"Inline Media"]
			stringByAppendingPathComponent:name];
}

- (void)fetchMedia:(AIMediaLink *)link forMessage:(AIContentMessage *)message inChat:(AIChat *)chat
{
	NSString *destination = AIInlineImageCachePath(link.original, link.extension);

	if ([[NSFileManager defaultManager] fileExistsAtPath:destination]) {
		[self announceImageAtPath:destination forMessage:message inChat:chat];
		return;
	}

	__weak AIInlineMediaLinkPlugin *weakSelf = self;

	[[session dataTaskWithURL:[NSURL URLWithString:link.address]
			completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		NSInteger code = [response isKindOfClass:[NSHTTPURLResponse class]]
			? [(NSHTTPURLResponse *)response statusCode] : 0;

		if (error || code != 200) {
			AILogWithSignature(@"could not fetch %@: %@ (status %ld)", link.address,
							   error ? [error localizedDescription] : @"no error reported", (long)code);
			return;
		}
		if (![data length] || [data length] > INLINE_MEDIA_MAX_BYTES) {
			AILogWithSignature(@"not showing %@: %lu bytes", link.address, (unsigned long)[data length]);
			return;
		}

		/* A transfer that stops early is not an error anywhere: the request completed, the
		 * status was 200, and what arrived is simply shorter than what was promised. Shown
		 * without checking, that is half a picture, and nothing says so. The encrypted case
		 * is covered further down by its authentication tag; this is the other one.
		 *
		 * A server that does not say how long the file is leaves nothing to compare, and
		 * chunked responses report minus one; neither is a reason to refuse what arrived. */
		long long promised = [response expectedContentLength];
		if (promised > 0 && (long long)[data length] != promised) {
			AILogWithSignature(@"%@ arrived short: %lu bytes of %lld, so it did not arrive",
							   link.address, (unsigned long)[data length], promised);
			return;
		}

		if (link.ivAndKey) {
			/* An encrypted file is stored as meaningless bytes, so the server's own idea of
			 * what it is says nothing. What vouches for it is the authentication tag, checked
			 * as part of decrypting: a file that fails that has either been damaged or
			 * interfered with, and either way it did not arrive. */
			data = AIOMEMOMediaDecrypt(data, link.ivAndKey);
			if (![data length]) {
				AILogWithSignature(@"%@ did not decrypt, so it did not arrive", link.address);
				return;
			}

		} else if (![[response MIMEType] hasPrefix:@"image/"] &&
				   ![[response MIMEType] hasPrefix:@"audio/"] &&
				   ![[response MIMEType] hasPrefix:@"video/"]) {
			//Sent in the clear, so the server's answer is all we have to go on
			AILogWithSignature(@"leaving %@ as a link: the server calls it %@",
							   link.address, [response MIMEType]);
			return;
		}

		[[NSFileManager defaultManager] createDirectoryAtPath:[destination stringByDeletingLastPathComponent]
								  withIntermediateDirectories:YES
												   attributes:nil
														error:NULL];
		if (![data writeToFile:destination atomically:YES]) {
			AILogWithSignature(@"could not keep %@ at %@", link.address, destination);
			return;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf announceImageAtPath:destination forMessage:message inChat:chat];
		});
	}] resume];
}

- (void)announceImageAtPath:(NSString *)path forMessage:(AIContentMessage *)message inChat:(AIChat *)chat
{
	/* On the message first, so a page rebuilt later re-embeds from there; the
	 * notification only reaches the view that is showing the chat right now. The
	 * view decides from the file's name what to make of it: a picture, a player
	 * for a voice note, or one for a video. */
	message.inlineImagePath = path;

	AILogWithSignature(@"ready at %@ for message %@ in %@", [path lastPathComponent],
					   message.messageId, chat);

	[[NSNotificationCenter defaultCenter] postNotificationName:AIChatMessageImageResolved
														object:chat
													  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
																message.messageId, @"MessageId",
																path, @"Path", nil]];
}

@end
