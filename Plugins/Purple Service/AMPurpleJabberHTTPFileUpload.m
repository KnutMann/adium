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

#import "AMPurpleJabberHTTPFileUpload.h"
#import "ESPurpleJabberAccount.h"

#import <Adium/AIChat.h>
#import <Adium/AIChatControllerProtocol.h>
#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIContentMessage.h>
#import <Adium/AIListContact.h>
#import <Adium/ESFileTransfer.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <CommonCrypto/CommonDigest.h>
#import <libpurple/jabber.h>

#define NS_HTTP_UPLOAD_0		"urn:xmpp:http:upload:0"
#define NS_HTTP_UPLOAD_LEGACY	"urn:xmpp:http:upload"
#define NS_DISCO_ITEMS			"http://jabber.org/protocol/disco#items"
#define NS_DISCO_INFO			"http://jabber.org/protocol/disco#info"
#define IQ_ID_PREFIX			@"adium-httpup-"
#define SLOT_TIMEOUT_SECONDS	30.0

@interface AMPurpleJabberHTTPFileUpload ()
- (void)discover;
- (void)sendIq:(xmlnode *)iq;
- (void)sendDiscoOfType:(const char *)ns to:(NSString *)jid;
- (void)handleResult:(xmlnode *)packet;
- (void)failSlotRequestWithId:(NSString *)iqid;
- (void)fallBackForFileTransfer:(ESFileTransfer *)fileTransfer;
@end

@implementation AMPurpleJabberHTTPFileUpload

/* Every stanza of the stream passes here; only IQ answers to ids this class minted are taken,
 * and taken whole, so nothing else ever sees them. */
static void AMPurpleJabberHTTPFileUpload_received_cb(PurpleConnection *gc, xmlnode **packet, gpointer this)
{
	if (!packet || !*packet)
		return;

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	AMPurpleJabberHTTPFileUpload *self = this;

	if (purple_account_get_connection([self->account purpleAccount]) == gc &&
		!strcmp((*packet)->name, "iq")) {
		const char *idattr = xmlnode_get_attrib(*packet, "id");

		if (idattr && [[NSString stringWithUTF8String:idattr] hasPrefix:IQ_ID_PREFIX]) {
			[self handleResult:*packet];
			xmlnode_free(*packet);
			*packet = NULL;
		}
	}

	[pool release];
}

- (id)initWithAccount:(ESPurpleJabberAccount *)inAccount
{
	if ((self = [super init])) {
		account = inAccount;
		queriedJids = [[NSMutableSet alloc] init];
		pendingSlots = [[NSMutableDictionary alloc] init];

		NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
		configuration.timeoutIntervalForRequest = 60;
		urlSession = [[NSURLSession sessionWithConfiguration:configuration] retain];

		PurplePlugin *jabber = purple_find_prpl("prpl-jabber");
		if (!jabber) {
			[self release];
			return nil;
		}

		purple_signal_connect(jabber, "jabber-receiving-xmlnode", self,
							  PURPLE_CALLBACK(AMPurpleJabberHTTPFileUpload_received_cb), self);

		[self discover];
	}

	return self;
}

- (void)dealloc
{
	purple_signals_disconnect_by_handle(self);
	[urlSession invalidateAndCancel];
	[urlSession release];
	[serviceJid release];
	[serviceNamespace release];
	[queriedJids release];
	[pendingSlots release];
	[super dealloc];
}

//Discovery --------------------------------------------------------------------------------------
#pragma mark Discovery

- (NSString *)nextIqId
{
	return [NSString stringWithFormat:@"%@%lu", IQ_ID_PREFIX, (unsigned long)sequence++];
}

- (void)sendIq:(xmlnode *)iq
{
	PurpleConnection *gc = purple_account_get_connection([account purpleAccount]);

	if (gc && PURPLE_PLUGIN_PROTOCOL_INFO(gc->prpl)->send_raw) {
		int length = 0;
		char *text = xmlnode_to_str(iq, &length);
		PURPLE_PLUGIN_PROTOCOL_INFO(gc->prpl)->send_raw(gc, text, length);
		g_free(text);
	}

	xmlnode_free(iq);
}

- (void)sendDiscoOfType:(const char *)ns to:(NSString *)jid
{
	[queriedJids addObject:jid];

	xmlnode *iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "get");
	xmlnode_set_attrib(iq, "to", [jid UTF8String]);
	xmlnode_set_attrib(iq, "id", [[self nextIqId] UTF8String]);

	xmlnode *query = xmlnode_new_child(iq, "query");
	xmlnode_set_namespace(query, ns);

	[self sendIq:iq];
}

- (void)discover
{
	NSRange at = [account.UID rangeOfString:@"@"];
	if (at.location == NSNotFound)
		return;

	NSString *domain = [account.UID substringFromIndex:(at.location + 1)];

	//The service may live on the domain itself or on an item of it
	[self sendDiscoOfType:NS_DISCO_INFO to:domain];
	[self sendDiscoOfType:NS_DISCO_ITEMS to:domain];
}

- (void)handleDiscoItems:(xmlnode *)query
{
	for (xmlnode *item = xmlnode_get_child(query, "item"); item; item = xmlnode_get_next_twin(item)) {
		const char *jid = xmlnode_get_attrib(item, "jid");

		if (jid)
			[self sendDiscoOfType:NS_DISCO_INFO to:[NSString stringWithUTF8String:jid]];
	}
}

- (void)handleDiscoInfo:(xmlnode *)query from:(NSString *)from
{
	BOOL current = NO, legacy = NO;

	for (xmlnode *feature = xmlnode_get_child(query, "feature"); feature; feature = xmlnode_get_next_twin(feature)) {
		const char *var = xmlnode_get_attrib(feature, "var");

		if (!var)
			continue;
		if (!strcmp(var, NS_HTTP_UPLOAD_0))
			current = YES;
		else if (!strcmp(var, NS_HTTP_UPLOAD_LEGACY))
			legacy = YES;
	}

	if (!current && !legacy)
		return;

	//The versioned protocol wins; a legacy answer never displaces one already found
	if ([serviceNamespace isEqualToString:@NS_HTTP_UPLOAD_0] && !current)
		return;

	[serviceJid release];
	serviceJid = [from copy];
	[serviceNamespace release];
	serviceNamespace = [(current ? @NS_HTTP_UPLOAD_0 : @NS_HTTP_UPLOAD_LEGACY) copy];
	maxSize = 0;

	//The size limit is announced as a form field of the info answer
	for (xmlnode *form = xmlnode_get_child_with_namespace(query, "x", "jabber:x:data"); form;
		 form = xmlnode_get_next_twin(form)) {
		for (xmlnode *field = xmlnode_get_child(form, "field"); field; field = xmlnode_get_next_twin(field)) {
			const char *var = xmlnode_get_attrib(field, "var");

			if (var && !strcmp(var, "max-file-size")) {
				xmlnode *value = xmlnode_get_child(field, "value");
				char *text = value ? xmlnode_get_data(value) : NULL;

				if (text) {
					maxSize = strtoull(text, NULL, 10);
					g_free(text);
				}
			}
		}
	}

	AILog(@"%@: HTTP upload service %@ (%@, limit %llu)", account, serviceJid, serviceNamespace, maxSize);
}

//The slot ---------------------------------------------------------------------------------------
#pragma mark The slot

- (void)requestSlotForFilename:(NSString *)filename
						  size:(unsigned long long)size
				   contentType:(NSString *)contentType
					completion:(void (^)(NSURL *putURL, NSDictionary *headers, NSURL *getURL))completion
{
	NSString *iqid = [self nextIqId];

	[pendingSlots setObject:[[completion copy] autorelease] forKey:iqid];

	xmlnode *iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "get");
	xmlnode_set_attrib(iq, "to", [serviceJid UTF8String]);
	xmlnode_set_attrib(iq, "id", [iqid UTF8String]);

	xmlnode *request = xmlnode_new_child(iq, "request");
	char sizeText[32];
	snprintf(sizeText, sizeof(sizeText), "%llu", size);

	if ([serviceNamespace isEqualToString:@NS_HTTP_UPLOAD_0]) {
		xmlnode_set_namespace(request, NS_HTTP_UPLOAD_0);
		xmlnode_set_attrib(request, "filename", [filename UTF8String]);
		xmlnode_set_attrib(request, "size", sizeText);
		xmlnode_set_attrib(request, "content-type", [contentType UTF8String]);
	} else {
		//The unversioned form says the same things as children
		xmlnode_set_namespace(request, NS_HTTP_UPLOAD_LEGACY);
		xmlnode_insert_data(xmlnode_new_child(request, "filename"), [filename UTF8String], -1);
		xmlnode_insert_data(xmlnode_new_child(request, "size"), sizeText, -1);
		xmlnode_insert_data(xmlnode_new_child(request, "content-type"), [contentType UTF8String], -1);
	}

	[self sendIq:iq];

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SLOT_TIMEOUT_SECONDS * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		[self failSlotRequestWithId:iqid];
	});
}

- (void)failSlotRequestWithId:(NSString *)iqid
{
	void (^completion)(NSURL *, NSDictionary *, NSURL *) = [[[pendingSlots objectForKey:iqid] retain] autorelease];

	if (!completion)
		return;

	[pendingSlots removeObjectForKey:iqid];
	completion(nil, nil, nil);
}

- (void)handleSlot:(xmlnode *)slot iqid:(NSString *)iqid
{
	void (^completion)(NSURL *, NSDictionary *, NSURL *) = [[[pendingSlots objectForKey:iqid] retain] autorelease];

	if (!completion)
		return;
	[pendingSlots removeObjectForKey:iqid];

	NSURL *putURL = nil, *getURL = nil;
	NSMutableDictionary *headers = [NSMutableDictionary dictionary];
	xmlnode *put = xmlnode_get_child(slot, "put");
	xmlnode *get = xmlnode_get_child(slot, "get");

	if (put && get) {
		const char *putAttr = xmlnode_get_attrib(put, "url");
		const char *getAttr = xmlnode_get_attrib(get, "url");

		if (putAttr && getAttr) {
			putURL = [NSURL URLWithString:[NSString stringWithUTF8String:putAttr]];
			getURL = [NSURL URLWithString:[NSString stringWithUTF8String:getAttr]];
		} else {
			//The unversioned form carries the addresses as text
			char *putText = xmlnode_get_data(put);
			char *getText = xmlnode_get_data(get);

			if (putText && getText) {
				putURL = [NSURL URLWithString:[NSString stringWithUTF8String:putText]];
				getURL = [NSURL URLWithString:[NSString stringWithUTF8String:getText]];
			}
			g_free(putText);
			g_free(getText);
		}

		/* The service may require these on the PUT; anything else it names is not ours to send.
		 * XEP-0363 permits exactly these three. */
		for (xmlnode *header = xmlnode_get_child(put, "header"); header; header = xmlnode_get_next_twin(header)) {
			const char *name = xmlnode_get_attrib(header, "name");
			char *value = name ? xmlnode_get_data(header) : NULL;

			if (value && (!g_ascii_strcasecmp(name, "Authorization") ||
						  !g_ascii_strcasecmp(name, "Cookie") ||
						  !g_ascii_strcasecmp(name, "Expires")))
				[headers setObject:[NSString stringWithUTF8String:value]
							forKey:[NSString stringWithUTF8String:name]];
			g_free(value);
		}
	}

	if (putURL && getURL &&
		[[putURL scheme] isEqualToString:@"https"] && [[getURL scheme] isEqualToString:@"https"])
		completion(putURL, headers, getURL);
	else
		completion(nil, nil, nil);
}

- (void)handleResult:(xmlnode *)packet
{
	const char *idattr = xmlnode_get_attrib(packet, "id");
	const char *type = xmlnode_get_attrib(packet, "type");
	const char *from = xmlnode_get_attrib(packet, "from");
	NSString *iqid = [NSString stringWithUTF8String:idattr];

	if (type && !strcmp(type, "error")) {
		[self failSlotRequestWithId:iqid];
		return;
	}

	if (!type || strcmp(type, "result"))
		return;

	xmlnode *slot = xmlnode_get_child_with_namespace(packet, "slot", NS_HTTP_UPLOAD_0);
	if (!slot)
		slot = xmlnode_get_child_with_namespace(packet, "slot", NS_HTTP_UPLOAD_LEGACY);
	if (slot) {
		[self handleSlot:slot iqid:iqid];
		return;
	}

	//Discovery answers only count when they come from somebody this class asked
	NSString *sender = (from ? [NSString stringWithUTF8String:from] : nil);
	if (!sender || ![queriedJids containsObject:sender])
		return;

	xmlnode *items = xmlnode_get_child_with_namespace(packet, "query", NS_DISCO_ITEMS);
	if (items) {
		[self handleDiscoItems:items];
		return;
	}

	xmlnode *info = xmlnode_get_child_with_namespace(packet, "query", NS_DISCO_INFO);
	if (info)
		[self handleDiscoInfo:info from:sender];
}

//The whole way ----------------------------------------------------------------------------------
#pragma mark The whole way

static NSDictionary *AMImageContentTypes(void)
{
	static NSDictionary *types = nil;

	if (!types)
		types = [[NSDictionary alloc] initWithObjectsAndKeys:
				 @"image/jpeg", @"jpg", @"image/jpeg", @"jpeg",
				 @"image/png", @"png", @"image/gif", @"gif",
				 @"image/webp", @"webp", nil];

	return types;
}

/*!
 * @brief Where the inline image plugin would cache a fetched address; put ours there too
 *
 * The same naming as AIInlineImageLinkPlugin uses, so the picture just sent is
 * already "fetched" for every view that looks its address up later.
 */
static NSString *AMInlineImageCachePath(NSString *address)
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

- (BOOL)takeOverFileTransfer:(ESFileTransfer *)fileTransfer
{
	if (![serviceJid length])
		return NO;

	NSString *path = [fileTransfer localFilename];
	NSString *contentType = [AMImageContentTypes() objectForKey:[[path pathExtension] lowercaseString]];

	if (!contentType)
		return NO;

	unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:path
																				error:NULL] fileSize];
	if (!size || (maxSize && size > maxSize))
		return NO;

	[fileTransfer setStatus:In_Progress_FileTransfer];

	[self requestSlotForFilename:[path lastPathComponent]
							size:size
					 contentType:contentType
					  completion:^(NSURL *putURL, NSDictionary *headers, NSURL *getURL) {
		if (!putURL || !getURL) {
			[self fallBackForFileTransfer:fileTransfer];
			return;
		}
		[self uploadFileAtPath:path contentType:contentType toURL:putURL headers:headers
				  announcingURL:getURL forFileTransfer:fileTransfer];
	}];

	return YES;
}

- (void)fallBackForFileTransfer:(ESFileTransfer *)fileTransfer
{
	AILog(@"%@: HTTP upload failed, falling back to the classic transfer", account);
	[account httpUploadFellBackForFileTransfer:fileTransfer];
}

- (void)uploadFileAtPath:(NSString *)path
			 contentType:(NSString *)contentType
				   toURL:(NSURL *)putURL
				 headers:(NSDictionary *)headers
		   announcingURL:(NSURL *)getURL
		 forFileTransfer:(ESFileTransfer *)fileTransfer
{
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:putURL];

	[request setHTTPMethod:@"PUT"];
	[request setValue:contentType forHTTPHeaderField:@"Content-Type"];
	for (NSString *name in headers)
		[request setValue:[headers objectForKey:name] forHTTPHeaderField:name];

	NSURLSessionUploadTask *task =
		[urlSession uploadTaskWithRequest:request
								 fromFile:[NSURL fileURLWithPath:path]
						completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		BOOL uploaded = (!error &&
						 [response isKindOfClass:[NSHTTPURLResponse class]] &&
						 ([(NSHTTPURLResponse *)response statusCode] / 100) == 2);

		dispatch_async(dispatch_get_main_queue(), ^{
			if (uploaded)
				[self announceFileAtPath:path address:[getURL absoluteString] forFileTransfer:fileTransfer];
			else
				[self fallBackForFileTransfer:fileTransfer];
		});
	}];

	[task resume];
}

/*!
 * @brief The upload is done; say so where everyone looks
 *
 * The address goes to the contact as an ordinary message, which is the whole trick
 * of XEP-0363: any client can show it, modern ones show the picture. Our own side
 * of the conversation gets the picture too, from the local file, through the same
 * road an incoming image link takes.
 */
- (void)announceFileAtPath:(NSString *)path address:(NSString *)address forFileTransfer:(ESFileTransfer *)fileTransfer
{
	[fileTransfer setPercentDone:1.0 bytesSent:[fileTransfer size]];
	[fileTransfer setStatus:Complete_FileTransfer];

	AIChat *chat = [adium.chatController chatWithContact:[fileTransfer contact]];
	if (!chat)
		return;

	AIContentMessage *message = [AIContentMessage messageInChat:chat
													 withSource:account
													destination:[fileTransfer contact]
														   date:nil
														message:[NSAttributedString stringWithString:address]
													  autoreply:NO];
	[adium.contentController sendContentObject:message];

	NSString *cachePath = AMInlineImageCachePath(address);
	NSFileManager *fileManager = [NSFileManager defaultManager];

	if (![fileManager fileExistsAtPath:cachePath]) {
		[fileManager createDirectoryAtPath:[cachePath stringByDeletingLastPathComponent]
			   withIntermediateDirectories:YES
								attributes:nil
									 error:NULL];
		[fileManager copyItemAtPath:path toPath:cachePath error:NULL];
	}

	if ([message.messageId length] && [fileManager fileExistsAtPath:cachePath]) {
		message.inlineImagePath = cachePath;
		[[NSNotificationCenter defaultCenter] postNotificationName:@"AIChatMessageImageResolved"
															object:chat
														  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
																	message.messageId, @"MessageId",
																	cachePath, @"Path", nil]];
	}
}

@end
