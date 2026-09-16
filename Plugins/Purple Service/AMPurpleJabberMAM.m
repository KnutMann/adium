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

#import "AMPurpleJabberMAM.h"
#import "ESPurpleJabberAccount.h"
#import "AMPurpleJabberSend.h"

#import <Adium/AIChat.h>
#import <Adium/AIListContact.h>
#import <Adium/AIContentMessage.h>
#import <Adium/AIContentContext.h>
#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <AIUtilities/AIAttributedStringAdditions.h>

#import <libpurple/libpurple.h>
#import <libpurple/si.h>
#import <libpurple/chat.h>

#define NS_MAM			"urn:xmpp:mam:2"
#define NS_FORWARD		"urn:xmpp:forward:0"
#define NS_DELAY		"urn:xmpp:delay"
#define NS_RSM			"http://jabber.org/protocol/rsm"
#define NS_DISCO_INFO	"http://jabber.org/protocol/disco#info"

/* How far back a window reaches when it opens. Enough to pick up a conversation, few enough
   that a server is not asked for a year of chatter every time somebody clicks a name. */
#define HOW_MANY_MESSAGES 25

/* Older than this and the line is drawn faded, as a conversation that ended rather than one
   being resumed. The same five minutes the local log has always used. */
#define LONG_ENOUGH_AGO 300.0

static int am_purple_jabber_mam_handle;

@interface AMPurpleJabberMAM ()
- (void)discover;
- (void)chatDidOpen:(NSNotification *)notification;
- (void)askAbout:(AIChat *)chat;
- (BOOL)handleIncoming:(xmlnode *)packet;
- (void)showWhatArrivedFor:(NSString *)queryID;
@end

static void mam_receiving_xmlnode_cb(PurpleConnection *gc, xmlnode **packet, gpointer data)
{
	AMPurpleJabberMAM *self = (__bridge AMPurpleJabberMAM *)data;

	if (!packet || !*packet)
		return;

	if ([self handleIncoming:*packet]) {
		/* Ours and nobody else's. On the receiving signal the stanza belongs to us once we
		 * take it, unlike the sending signal where the caller keeps its own pointer. */
		xmlnode_free(*packet);
		*packet = NULL;
	}
}

@implementation AMPurpleJabberMAM

- (id)initWithAccount:(ESPurpleJabberAccount *)inAccount
{
	if ((self = [super init])) {
		account = inAccount;
		available = NO;
		counter = 0;
		gathering = [[NSMutableDictionary alloc] init];
		chats = [[NSMutableDictionary alloc] init];
		asked = [[NSMutableSet alloc] init];

		void *jabber = purple_plugins_find_with_id("prpl-jabber");
		if (jabber) {
			purple_signal_connect(jabber, "jabber-receiving-xmlnode", &am_purple_jabber_mam_handle,
								  PURPLE_CALLBACK(mam_receiving_xmlnode_cb), (__bridge void *)self);
		}

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(chatDidOpen:)
													 name:Chat_DidOpen
												   object:nil];

		[self discover];
	}

	return self;
}

- (void)dealloc
{
	purple_signals_disconnect_by_handle(&am_purple_jabber_mam_handle);
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isAvailable
{
	return available;
}

#pragma mark Asking

- (NSString *)nextID
{
	return [NSString stringWithFormat:@"adium-mam-%lu", (unsigned long)counter++];
}

/*! @brief Does this server keep an archive at all?
 *
 * Asked of our own bare address rather than of the host, because the archive belongs to the
 * account: a server may run one and not offer it to everybody.
 */
- (void)discover
{
	PurpleConnection *gc = purple_account_get_connection([account purpleAccount]);
	xmlnode *iq, *query;

	if (!gc)
		return;

	iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "get");
	xmlnode_set_attrib(iq, "to", [[account UID] UTF8String]);
	xmlnode_set_attrib(iq, "id", [[self nextID] UTF8String]);
	query = xmlnode_new_child(iq, "query");
	xmlnode_set_namespace(query, NS_DISCO_INFO);

	AMPurpleJabberSend(gc, iq);
	xmlnode_free(iq);
}

- (void)chatDidOpen:(NSNotification *)notification
{
	AIChat *chat = [notification object];

	if (!available || chat.account != (AIAccount *)account || chat.isGroupChat)
		return;
	if (!chat.listObject || [asked containsObject:chat.uniqueChatID])
		return;

	[asked addObject:chat.uniqueChatID];
	[self askAbout:chat];
}

/*! @brief Ask for the last few messages exchanged with this contact */
- (void)askAbout:(AIChat *)chat
{
	PurpleConnection *gc = purple_account_get_connection([account purpleAccount]);
	NSString *queryID;
	xmlnode *iq, *query, *x, *field, *value, *set, *max, *before;

	if (!gc)
		return;

	queryID = [self nextID];
	[gathering setObject:[NSMutableArray array] forKey:queryID];
	[chats setObject:chat forKey:queryID];

	/* The same string names the request and the query inside it. The server answers a finished
	   query with an <iq type='result'> carrying that id, which is the only thing tying the end
	   of a query to the query it ended; asking with two different names would leave nothing to
	   match and several conversations arriving at once could not be told apart. */
	iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "set");
	xmlnode_set_attrib(iq, "id", [queryID UTF8String]);

	query = xmlnode_new_child(iq, "query");
	xmlnode_set_namespace(query, NS_MAM);
	xmlnode_set_attrib(query, "queryid", [queryID UTF8String]);

	/* Which conversation, said the way a data form says it */
	x = xmlnode_new_child(query, "x");
	xmlnode_set_namespace(x, "jabber:x:data");
	xmlnode_set_attrib(x, "type", "submit");

	field = xmlnode_new_child(x, "field");
	xmlnode_set_attrib(field, "var", "FORM_TYPE");
	xmlnode_set_attrib(field, "type", "hidden");
	value = xmlnode_new_child(field, "value");
	xmlnode_insert_data(value, NS_MAM, -1);

	field = xmlnode_new_child(x, "field");
	xmlnode_set_attrib(field, "var", "with");
	value = xmlnode_new_child(field, "value");
	xmlnode_insert_data(value, [chat.listObject.UID UTF8String], -1);

	/* The last few rather than the first few: <before/> with nothing in it means the end. */
	set = xmlnode_new_child(query, "set");
	xmlnode_set_namespace(set, NS_RSM);
	max = xmlnode_new_child(set, "max");
	xmlnode_insert_data(max, [[NSString stringWithFormat:@"%d", HOW_MANY_MESSAGES] UTF8String], -1);
	before = xmlnode_new_child(set, "before");
	(void)before;

	AILogWithSignature(@"%@: asking the archive about %@", account, chat.listObject.UID);

	AMPurpleJabberSend(gc, iq);
	xmlnode_free(iq);
}

#pragma mark Listening

/*! @brief Returns YES when the stanza was ours and should go no further */
- (BOOL)handleIncoming:(xmlnode *)packet
{
	const char *name = packet->name;

	if (purple_strequal(name, "message")) {
		xmlnode *result = xmlnode_get_child_with_namespace(packet, "result", NS_MAM);
		const char *queryID = result ? xmlnode_get_attrib(result, "queryid") : NULL;
		NSString *key = queryID ? [NSString stringWithUTF8String:queryID] : nil;
		NSMutableArray *arrived = key ? [gathering objectForKey:key] : nil;
		xmlnode *forwarded, *message, *body, *delay;
		char *text;

		if (!arrived)
			return NO;

		forwarded = xmlnode_get_child_with_namespace(result, "forwarded", NS_FORWARD);
		message = forwarded ? xmlnode_get_child(forwarded, "message") : NULL;
		body = message ? xmlnode_get_child(message, "body") : NULL;
		text = body ? xmlnode_get_data(body) : NULL;

		/* A message without a body is a receipt, a chat state or a correction, and none of
		 * those is worth showing again out of the archive. Consumed all the same: it was
		 * addressed to a query of ours and nothing else should see it. */
		if (text) {
			delay = forwarded ? xmlnode_get_child_with_namespace(forwarded, "delay", NS_DELAY) : NULL;
			const char *stamp = delay ? xmlnode_get_attrib(delay, "stamp") : NULL;
			const char *from = xmlnode_get_attrib(message, "from");
			time_t when = stamp ? purple_str_to_time(stamp, TRUE, NULL, NULL, NULL) : 0;

			[arrived addObject:@{
				@"text": [NSString stringWithUTF8String:text],
				@"from": from ? [NSString stringWithUTF8String:from] : @"",
				@"when": [NSDate dateWithTimeIntervalSince1970:(when ? when : time(NULL))]
			}];
			g_free(text);
		}

		return YES;
	}

	if (purple_strequal(name, "iq")) {
		xmlnode *fin = xmlnode_get_child_with_namespace(packet, "fin", NS_MAM);
		xmlnode *query = xmlnode_get_child_with_namespace(packet, "query", NS_DISCO_INFO);

		if (fin) {
			const char *iqid = xmlnode_get_attrib(packet, "id");
			NSString *key = iqid ? [NSString stringWithUTF8String:iqid] : nil;

			if (key && [gathering objectForKey:key]) {
				[self showWhatArrivedFor:key];
				return YES;
			}
			return NO;
		}

		if (query && !available) {
			xmlnode *feature;

			for (feature = xmlnode_get_child(query, "feature"); feature;
				 feature = xmlnode_get_next_twin(feature)) {
				const char *var = xmlnode_get_attrib(feature, "var");

				if (purple_strequal(var, NS_MAM)) {
					available = YES;
					AILogWithSignature(@"%@: the server keeps an archive", account);
					break;
				}
			}
			/* Not consumed: a disco answer is nobody's private business, and other parts of
			 * Adium read the same one. */
			return NO;
		}
	}

	return NO;
}

#pragma mark Showing

- (void)showWhatArrivedFor:(NSString *)queryID
{
	NSMutableArray *arrived = [gathering objectForKey:queryID];
	AIChat *chat = [chats objectForKey:queryID];
	NSString *ourUID = [account UID];

	[gathering removeObjectForKey:queryID];
	[chats removeObjectForKey:queryID];

	if (!chat || ![arrived count])
		return;

	AILogWithSignature(@"%@: the archive had %lu messages for %@",
					   account, (unsigned long)[arrived count], chat.listObject.UID);

	for (NSDictionary *one in arrived) {
		NSDate *when = [one objectForKey:@"when"];
		NSString *from = [one objectForKey:@"from"];
		/* The archive stores both sides, and the sender is a full address while ours is bare. */
		BOOL sentByUs = [[from componentsSeparatedByString:@"/"][0] isEqualToString:ourUID];
		Class kind = (-[when timeIntervalSinceNow] > LONG_ENOUGH_AGO)
			? [AIContentContext class] : [AIContentMessage class];

		AIContentMessage *line = [kind messageInChat:chat
										  withSource:(sentByUs ? (AIListObject *)account
															   : (AIListObject *)chat.listObject)
										 destination:(sentByUs ? (AIListObject *)chat.listObject
															   : (AIListObject *)account)
												date:when
											 message:[NSAttributedString stringWithString:[one objectForKey:@"text"]]
										   autoreply:NO];

		/* Neither logged nor counted: the log already has whatever this machine saw, and a
		 * conversation being re-read must not ring, badge or mark anything unread. */
		[line setPostProcessContent:NO];
		[line setTrackContent:NO];
		[line setDisplayContentImmediately:NO];

		[adium.contentController displayContentObject:line
								  usingContentFilters:YES
										  immediately:YES];
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:Content_ChatDidFinishAddingUntrackedContent
														object:chat];
}

@end
