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

#import "adiumPurpleBookmarks.h"
#import "CBPurpleAccount.h"
#import <Adium/AIListBookmark.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <Adium/AIService.h>

/*
 * PEP Native Bookmarks (XEP-0402) for the jabber protocol.
 *
 * Adium's group chat bookmarks were purely local. For jabber accounts they now live on
 * the server too, in the urn:xmpp:bookmarks:1 PEP node, so every device on the account
 * sees the same rooms with the same autojoin flags, live.
 *
 * On sign-on the node is fetched and merged: rooms the server knows appear as Adium
 * bookmarks, rooms only Adium knows are published up. From then on the two directions
 * stay live - PEP notifications (the +notify caps feature is registered with the
 * protocol) apply other devices' changes as they happen, and Adium's own bookmark
 * additions, removals and autojoin flips are published as they are made. Only rooms on
 * the jabber account itself take part; a Telegram bookmark is nobody's conference.
 *
 * The stanzas travel the same road as carbons and CSI: injected and observed through
 * the jabber xmlnode signals.
 */

#define NS_BOOKMARKS		"urn:xmpp:bookmarks:1"
#define NS_PUBSUB			"http://jabber.org/protocol/pubsub"
#define NS_PUBSUB_EVENT		"http://jabber.org/protocol/pubsub#event"
#define NS_DATA_FORMS		"jabber:x:data"
#define FETCH_IQ_ID			"adium-bookmarks-fetch"
#define PUBLISH_IQ_ID		"adium-bookmarks-publish"
#define RETRACT_IQ_ID		"adium-bookmarks-retract"

//Internal to the jabber protocol, but compiled into the same libpurple we ship
typedef gboolean (AdiumJabberFeatureEnabled)(void *js, const gchar *namespace);
extern void jabber_add_feature(const gchar *namespace, AdiumJabberFeatureEnabled *cb);

static int adium_purple_bookmarks_handle;

/* YES while server data is being turned into Adium bookmarks, so the resulting
 * added/removed notifications are not published straight back. */
static BOOL applyingServerBookmarks = NO;

static PurplePlugin *bookmarks_jabber_prpl(void)
{
	return purple_find_prpl("prpl-jabber");
}

static void bookmarks_send_stanza(PurpleConnection *gc, xmlnode *stanza)
{
	PurplePlugin *jabber = bookmarks_jabber_prpl();
	if (jabber)
		purple_signal_emit(jabber, "jabber-sending-xmlnode", gc, &stanza);
	if (stanza)
		xmlnode_free(stanza);
}

static char *bookmarks_own_bare_jid(PurpleAccount *account)
{
	const char *username = purple_account_get_username(account);
	if (!username) return NULL;

	const char *slash = strchr(username, '/');
	return (slash ? g_strndup(username, (gsize)(slash - username)) : g_strdup(username));
}

#pragma mark Bookmark facts

/*!
 * @brief The room JID a bookmark stands for, or nil if it is not a jabber room
 */
static NSString *bookmarks_room_jid(AIListBookmark *bookmark)
{
	if (![bookmark.account isKindOfClass:[CBPurpleAccount class]])
		return nil;

	PurpleAccount *purpleAccount = [(CBPurpleAccount *)bookmark.account purpleAccount];
	if (!purpleAccount || !purple_strequal(purple_account_get_protocol_id(purpleAccount), "prpl-jabber"))
		return nil;

	NSString *room = [bookmark.chatCreationDictionary objectForKey:@"room"];
	NSString *server = [bookmark.chatCreationDictionary objectForKey:@"server"];
	if (![room length] || ![server length])
		return nil;

	return [[NSString stringWithFormat:@"%@@%@", room, server] lowercaseString];
}

static AIListBookmark *bookmarks_find(CBPurpleAccount *account, NSString *roomJid)
{
	for (AIListBookmark *bookmark in adium.contactController.allBookmarks) {
		if (bookmark.account == account && [bookmarks_room_jid(bookmark) isEqualToString:roomJid])
			return bookmark;
	}
	return nil;
}

#pragma mark Publishing

/*!
 * @brief Publish one bookmark to the account's PEP node
 */
static void bookmarks_publish(AIListBookmark *bookmark)
{
	NSString *roomJid = bookmarks_room_jid(bookmark);
	if (!roomJid)
		return;

	CBPurpleAccount *account = (CBPurpleAccount *)bookmark.account;
	PurpleConnection *gc = purple_account_get_connection([account purpleAccount]);
	if (!gc || purple_connection_get_state(gc) != PURPLE_CONNECTED)
		return;

	BOOL autojoin = [[bookmark preferenceForKey:KEY_AUTO_JOIN group:GROUP_LIST_BOOKMARK] boolValue];
	NSString *nick = [bookmark.chatCreationDictionary objectForKey:@"handle"];

	xmlnode *iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "set");
	xmlnode_set_attrib(iq, "id", PUBLISH_IQ_ID);

	xmlnode *pubsub = xmlnode_new_child(iq, "pubsub");
	xmlnode_set_namespace(pubsub, NS_PUBSUB);

	xmlnode *publish = xmlnode_new_child(pubsub, "publish");
	xmlnode_set_attrib(publish, "node", NS_BOOKMARKS);

	xmlnode *item = xmlnode_new_child(publish, "item");
	xmlnode_set_attrib(item, "id", [roomJid UTF8String]);

	xmlnode *conference = xmlnode_new_child(item, "conference");
	xmlnode_set_namespace(conference, NS_BOOKMARKS);
	xmlnode_set_attrib(conference, "autojoin", autojoin ? "true" : "false");
	if ([bookmark.displayName length] && ![bookmark.displayName isEqualToString:bookmark.name])
		xmlnode_set_attrib(conference, "name", [bookmark.displayName UTF8String]);

	if ([nick length]) {
		xmlnode *nickNode = xmlnode_new_child(conference, "nick");
		xmlnode_insert_data(nickNode, [nick UTF8String], -1);
	}
	if ([bookmark.password length]) {
		xmlnode *passwordNode = xmlnode_new_child(conference, "password");
		xmlnode_insert_data(passwordNode, [bookmark.password UTF8String], -1);
	}

	/* The publish options XEP-0402 requires: the node persists its items, keeps as many
	 * as the server allows, and shows them to nobody but the account itself. */
	xmlnode *options = xmlnode_new_child(pubsub, "publish-options");
	xmlnode *form = xmlnode_new_child(options, "x");
	xmlnode_set_namespace(form, NS_DATA_FORMS);
	xmlnode_set_attrib(form, "type", "submit");

	struct { const char *var; const char *value; } fields[] = {
		{ "FORM_TYPE", "http://jabber.org/protocol/pubsub#publish-options" },
		{ "pubsub#persist_items", "true" },
		{ "pubsub#max_items", "max" },
		{ "pubsub#access_model", "whitelist" },
	};
	for (size_t i = 0; i < sizeof(fields) / sizeof(fields[0]); i++) {
		xmlnode *field = xmlnode_new_child(form, "field");
		xmlnode_set_attrib(field, "var", fields[i].var);
		if (i == 0)
			xmlnode_set_attrib(field, "type", "hidden");
		xmlnode *value = xmlnode_new_child(field, "value");
		xmlnode_insert_data(value, fields[i].value, -1);
	}

	AILog(@"adiumPurpleBookmarks: publishing %@ (autojoin %d)", roomJid, autojoin);
	bookmarks_send_stanza(gc, iq);
}

static void bookmarks_retract(CBPurpleAccount *account, NSString *roomJid)
{
	PurpleConnection *gc = purple_account_get_connection([account purpleAccount]);
	if (!gc || purple_connection_get_state(gc) != PURPLE_CONNECTED)
		return;

	xmlnode *iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "set");
	xmlnode_set_attrib(iq, "id", RETRACT_IQ_ID);

	xmlnode *pubsub = xmlnode_new_child(iq, "pubsub");
	xmlnode_set_namespace(pubsub, NS_PUBSUB);

	xmlnode *retract = xmlnode_new_child(pubsub, "retract");
	xmlnode_set_attrib(retract, "node", NS_BOOKMARKS);
	xmlnode_set_attrib(retract, "notify", "true");

	xmlnode *item = xmlnode_new_child(retract, "item");
	xmlnode_set_attrib(item, "id", [roomJid UTF8String]);

	AILog(@"adiumPurpleBookmarks: retracting %@", roomJid);
	bookmarks_send_stanza(gc, iq);
}

#pragma mark Applying server items

/*!
 * @brief Turn one conference item into an Adium bookmark, or update the one it has
 */
static void bookmarks_apply_item(CBPurpleAccount *account, const char *itemId, xmlnode *conference)
{
	NSString *roomJid = [[NSString stringWithUTF8String:itemId] lowercaseString];
	NSRange at = [roomJid rangeOfString:@"@"];
	if (at.location == NSNotFound || at.location == 0)
		return;

	NSString	*room = [roomJid substringToIndex:at.location];
	NSString	*server = [roomJid substringFromIndex:(at.location + 1)];
	const char	*autojoinAttrib = xmlnode_get_attrib(conference, "autojoin");
	BOOL		 autojoin = (autojoinAttrib &&
							 (purple_strequal(autojoinAttrib, "true") || purple_strequal(autojoinAttrib, "1")));

	xmlnode	*nickNode = xmlnode_get_child(conference, "nick");
	char	*nick = (nickNode ? xmlnode_get_data(nickNode) : NULL);
	xmlnode	*passwordNode = xmlnode_get_child(conference, "password");
	char	*password = (passwordNode ? xmlnode_get_data(passwordNode) : NULL);

	NSMutableDictionary *creationInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
										 room, @"room", server, @"server", nil];
	if (nick && *nick)
		[creationInfo setObject:[NSString stringWithUTF8String:nick] forKey:@"handle"];
	if (password && *password)
		[creationInfo setObject:[NSString stringWithUTF8String:password] forKey:@"password"];

	applyingServerBookmarks = YES;
	@try {
		AIListBookmark *bookmark = bookmarks_find(account, roomJid);
		if (!bookmark) {
			AILog(@"adiumPurpleBookmarks: creating bookmark for %@ from the server", roomJid);
			bookmark = [adium.contactController bookmarkForChatName:roomJid
														  onAccount:account
												   chatCreationInfo:creationInfo
															inGroup:nil];
		}

		if (password && *password)
			[bookmark setPassword:[NSString stringWithUTF8String:password]];

		BOOL wasAutojoin = [[bookmark preferenceForKey:KEY_AUTO_JOIN group:GROUP_LIST_BOOKMARK] boolValue];
		if (wasAutojoin != autojoin) {
			[bookmark setPreference:[NSNumber numberWithBool:autojoin]
							 forKey:KEY_AUTO_JOIN
							  group:GROUP_LIST_BOOKMARK];
		}

		/* A bookmark created or switched to autojoin after sign-on missed its own
		 * account-online moment; join it now, quietly. */
		if (autojoin && !wasAutojoin && account.online)
			[bookmark openChatWithoutActivating];

	} @finally {
		applyingServerBookmarks = NO;
	}

	g_free(nick);
	g_free(password);
}

static void bookmarks_remove_room(CBPurpleAccount *account, NSString *roomJid)
{
	AIListBookmark *bookmark = bookmarks_find(account, roomJid);
	if (!bookmark)
		return;

	AILog(@"adiumPurpleBookmarks: removing bookmark for %@, retracted on the server", roomJid);
	applyingServerBookmarks = YES;
	@try {
		[adium.contactController removeBookmark:bookmark];
	} @finally {
		applyingServerBookmarks = NO;
	}
}

/*!
 * @brief Merge a full fetch: the server's rooms come down, rooms only Adium knows go up
 */
static void bookmarks_apply_fetch(PurpleConnection *gc, xmlnode *items)
{
	CBPurpleAccount *account = accountLookup(purple_connection_get_account(gc));
	if (!account)
		return;

	NSMutableSet *serverRooms = [NSMutableSet set];

	for (xmlnode *item = xmlnode_get_child(items, "item"); item; item = xmlnode_get_next_twin(item)) {
		const char	*itemId = xmlnode_get_attrib(item, "id");
		xmlnode		*conference = xmlnode_get_child_with_namespace(item, "conference", NS_BOOKMARKS);
		if (!itemId || !conference)
			continue;

		[serverRooms addObject:[[NSString stringWithUTF8String:itemId] lowercaseString]];
		bookmarks_apply_item(account, itemId, conference);
	}

	/* Rooms only this side knows have never been published - an old local bookmark, or
	 * one made while offline. Up they go. A room deleted on another device while Adium
	 * was offline comes back this way; live retractions are handled as they happen, but
	 * absence in a fetch cannot be told apart from never-published. */
	for (AIListBookmark *bookmark in adium.contactController.allBookmarks) {
		if (bookmark.account != account)
			continue;
		NSString *roomJid = bookmarks_room_jid(bookmark);
		if (roomJid && ![serverRooms containsObject:roomJid])
			bookmarks_publish(bookmark);
	}
}

#pragma mark Receiving

static void bookmarks_receiving_xmlnode_cb(PurpleConnection *gc, xmlnode **packet, gpointer data)
{
	xmlnode *node = (packet ? *packet : NULL);
	if (!node)
		return;

	//The reply to our fetch: apply and swallow. Publish and retract results just vanish.
	if (purple_strequal(node->name, "iq")) {
		const char *iqId = xmlnode_get_attrib(node, "id");
		if (!iqId)
			return;

		if (purple_strequal(iqId, FETCH_IQ_ID)) {
			const char *type = xmlnode_get_attrib(node, "type");
			if (purple_strequal(type, "result")) {
				xmlnode *pubsub = xmlnode_get_child_with_namespace(node, "pubsub", NS_PUBSUB);
				xmlnode *items = (pubsub ? xmlnode_get_child(pubsub, "items") : NULL);
				if (items)
					bookmarks_apply_fetch(gc, items);
			}
			//An error just means the server keeps no bookmarks; nothing to merge
			xmlnode_free(node);
			*packet = NULL;

		} else if (purple_strequal(iqId, PUBLISH_IQ_ID) || purple_strequal(iqId, RETRACT_IQ_ID)) {
			xmlnode_free(node);
			*packet = NULL;
		}
		return;
	}

	//PEP notification: another device changed the node
	if (!purple_strequal(node->name, "message"))
		return;

	xmlnode *event = xmlnode_get_child_with_namespace(node, "event", NS_PUBSUB_EVENT);
	xmlnode *items = (event ? xmlnode_get_child(event, "items") : NULL);
	if (!items || !purple_strequal(xmlnode_get_attrib(items, "node"), NS_BOOKMARKS))
		return;

	//Only our own account may rearrange our bookmarks
	PurpleAccount	*purpleAccount = purple_connection_get_account(gc);
	const char		*from = xmlnode_get_attrib(node, "from");
	char			*ownJid = bookmarks_own_bare_jid(purpleAccount);
	gboolean		 genuine = (from && ownJid && !g_ascii_strcasecmp(from, ownJid));
	g_free(ownJid);
	if (!genuine)
		return;

	CBPurpleAccount *account = accountLookup(purpleAccount);
	if (account) {
		for (xmlnode *item = xmlnode_get_child(items, "item"); item; item = xmlnode_get_next_twin(item)) {
			const char	*itemId = xmlnode_get_attrib(item, "id");
			xmlnode		*conference = xmlnode_get_child_with_namespace(item, "conference", NS_BOOKMARKS);
			if (itemId && conference)
				bookmarks_apply_item(account, itemId, conference);
		}
		for (xmlnode *retract = xmlnode_get_child(items, "retract"); retract; retract = xmlnode_get_next_twin(retract)) {
			const char *itemId = xmlnode_get_attrib(retract, "id");
			if (itemId)
				bookmarks_remove_room(account, [[NSString stringWithUTF8String:itemId] lowercaseString]);
		}
	}

	xmlnode_free(node);
	*packet = NULL;
}

#pragma mark Connection lifecycle

static void bookmarks_signing_on_cb(PurpleConnection *gc, gpointer data)
{
	PurpleAccount *account = purple_connection_get_account(gc);
	if (!purple_strequal(purple_account_get_protocol_id(account), "prpl-jabber"))
		return;

	PurplePlugin *jabber = bookmarks_jabber_prpl();
	if (!jabber)
		return;

	static gboolean hooked = FALSE;
	if (!hooked) {
		hooked = TRUE;
		purple_signal_connect(jabber, "jabber-receiving-xmlnode", &adium_purple_bookmarks_handle,
							  PURPLE_CALLBACK(bookmarks_receiving_xmlnode_cb), NULL);
	}
}

static void bookmarks_signed_on_cb(PurpleConnection *gc, gpointer data)
{
	PurpleAccount *account = purple_connection_get_account(gc);
	if (!purple_strequal(purple_account_get_protocol_id(account), "prpl-jabber"))
		return;

	xmlnode *iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "get");
	xmlnode_set_attrib(iq, "id", FETCH_IQ_ID);

	xmlnode *pubsub = xmlnode_new_child(iq, "pubsub");
	xmlnode_set_namespace(pubsub, NS_PUBSUB);

	xmlnode *items = xmlnode_new_child(pubsub, "items");
	xmlnode_set_attrib(items, "node", NS_BOOKMARKS);

	bookmarks_send_stanza(gc, iq);
}

#pragma mark Local changes

static void bookmarks_local_added(AIListBookmark *bookmark)
{
	if (applyingServerBookmarks)
		return;
	bookmarks_publish(bookmark);
}

static void bookmarks_local_removed(AIListBookmark *bookmark)
{
	if (applyingServerBookmarks)
		return;

	NSString *roomJid = bookmarks_room_jid(bookmark);
	if (roomJid)
		bookmarks_retract((CBPurpleAccount *)bookmark.account, roomJid);
}

/*!
 * @brief Watches the bookmarks' own preference group for autojoin flips
 */
@interface AIPurpleBookmarksPreferenceObserver : NSObject
@end

@implementation AIPurpleBookmarksPreferenceObserver
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key
							object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	if (applyingServerBookmarks)
		return;
	if (![key isEqualToString:KEY_AUTO_JOIN] || ![object isKindOfClass:[AIListBookmark class]])
		return;

	bookmarks_publish((AIListBookmark *)object);
}
@end

void configureAdiumPurpleBookmarks(void)
{
	/* The +notify flavour in our entity caps is what makes the server send PEP
	 * notifications for the node. Registered before any account connects, so the first
	 * presence already carries it. */
	jabber_add_feature(NS_BOOKMARKS "+notify", NULL);

	void *connections = purple_connections_get_handle();
	purple_signal_connect(connections, "signing-on", &adium_purple_bookmarks_handle,
						  PURPLE_CALLBACK(bookmarks_signing_on_cb), NULL);
	purple_signal_connect(connections, "signed-on", &adium_purple_bookmarks_handle,
						  PURPLE_CALLBACK(bookmarks_signed_on_cb), NULL);

	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserverForName:AIListBookmarkAddedNotification
						object:nil
						 queue:[NSOperationQueue mainQueue]
					usingBlock:^(NSNotification *notification) {
						bookmarks_local_added(notification.object);
					}];
	[center addObserverForName:AIListBookmarkRemovedNotification
						object:nil
						 queue:[NSOperationQueue mainQueue]
					usingBlock:^(NSNotification *notification) {
						bookmarks_local_removed(notification.object);
					}];

	static AIPurpleBookmarksPreferenceObserver *observer = nil;
	observer = [[AIPurpleBookmarksPreferenceObserver alloc] init];
	[adium.preferenceController registerPreferenceObserver:observer forGroup:GROUP_LIST_BOOKMARK];
}
