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

#import "adiumPurpleWhatsApp.h"
#import "adiumPurpleSignals.h"
#import <Adium/AIChatControllerProtocol.h>
#import <Adium/AIChat.h>
#import <Adium/AIListContact.h>

/*
 * Receipts, reactions and message ids for WhatsApp (prpl-hehoe-whatsmeow).
 *
 * The protocol plug-in registers three purple signals and emits each with the
 * connection and a hash table of borrowed strings (see gowhatsapp.h upstream):
 *
 * - "gowhatsapp-message-id" fires right before a message is written into a
 *   conversation. For incoming messages the id is stashed here and taken out
 *   by the conversation write callback a moment later, the same synchronous
 *   hand-off the jabber patches use, so the shown message carries the id a
 *   later reaction refers to.
 * - "gowhatsapp-receipt" carries a message through its life: "sent" names the
 *   id the server assigned to our own message (the view attaches it to the
 *   just-shown message), "delivered" and "read" become the same notifications
 *   the jabber receipts post, so the ticks work identically for both protocols.
 * - "gowhatsapp-reaction" becomes the same reactions-changed notification the
 *   jabber reactions post; WhatsApp reactions are one emoji per sender with an
 *   empty emoji meaning removal, which is exactly the replace-per-sender
 *   semantics the message view already implements.
 *
 * Everything arrives on the main thread: the plug-in marshals its events
 * through purple_timeout_add before emitting.
 */

static int adium_purple_whatsapp_handle;

#define WHATSAPP_PRPL_ID "prpl-hehoe-whatsmeow"

static const char *whatsapp_detail(GHashTable *details, const char *key)
{
	return details ? (const char *)g_hash_table_lookup(details, key) : NULL;
}

/*!
 * @brief The Adium chat a signal's details refer to, if it is open
 */
static AIChat *whatsapp_chat_for_details(PurpleConnection *pc, GHashTable *details)
{
	PurpleAccount	*purpleAccount = purple_connection_get_account(pc);
	const char		*chatJid = whatsapp_detail(details, "chat");
	const char		*isGroup = whatsapp_detail(details, "isGroup");

	if (!chatJid) return nil;

	if (isGroup && strcmp(isGroup, "1") == 0) {
		PurpleConversation *conv = purple_find_conversation_with_account(PURPLE_CONV_TYPE_CHAT, chatJid, purpleAccount);
		return conv ? groupChatLookupFromConv(conv) : nil;
	}

	PurpleBuddy		*buddy = purple_find_buddy(purpleAccount, chatJid);
	AIListContact	*contact = buddy ? contactLookupFromBuddy(buddy) : nil;
	return contact ? [adium.chatController existingChatWithContact:contact] : nil;
}

/*!
 * @brief An incoming message is about to be shown; stash its id for the write callback
 */
static void whatsapp_message_id_cb(PurpleConnection *pc, GHashTable *details, gpointer data)
{
	const char *isOutgoing = whatsapp_detail(details, "isOutgoing");
	const char *isGroup = whatsapp_detail(details, "isGroup");
	const char *chat = whatsapp_detail(details, "chat");
	const char *messageId = whatsapp_detail(details, "id");

	/* Our own echo is dropped by the write callback (Adium displays sent messages
	 * itself); its id arrives through the "sent" receipt instead. */
	if (isOutgoing && strcmp(isOutgoing, "1") == 0) return;

	PurpleAccount *account = purple_connection_get_account(pc);
	if (isGroup && strcmp(isGroup, "1") == 0) {
		adiumStashPendingIncomingGroupchatMessageId(account, messageId);
	} else {
		adiumStashPendingIncomingMessageId(account, chat, messageId);
	}

	/* An own message arriving from another device has, by arriving here, proven it
	 * reached the server: it earns the first tick. No receipt will ever say so, the
	 * "sent" receipt went to the device that sent it. Posted on the next runloop
	 * pass so the message is on the page before the tick looks for it. */
	const char *sender = whatsapp_detail(details, "sender");
	if (sender && messageId &&
		purple_strequal(purple_account_get_username(account), sender)) {
		AIChat *ownChat = whatsapp_chat_for_details(pc, details);
		NSString *mid = [NSString stringWithUTF8String:messageId];
		if (ownChat) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[[NSNotificationCenter defaultCenter] postNotificationName:@"AIChatMessageWasSent"
																   object:ownChat
																 userInfo:@{ @"MessageId": mid }];
			});
		}
	}
}

static void whatsapp_receipt_cb(PurpleConnection *pc, GHashTable *details, gpointer data)
{
	@autoreleasepool {
		const char *type = whatsapp_detail(details, "type");
		const char *messageId = whatsapp_detail(details, "id");
		if (!type || !messageId) return;

		AIChat *chat = whatsapp_chat_for_details(pc, details);
		AILog(@"WhatsApp receipt: type=%s id=%s chat=%s isGroup=%s -> %@",
			  type, messageId,
			  whatsapp_detail(details, "chat") ?: "(null)",
			  whatsapp_detail(details, "isGroup") ?: "(null)",
			  chat ?: (id)@"KEIN AIChat gefunden");
		if (!chat) return;

		NSString *notificationName = nil;
		if (strcmp(type, "sent") == 0) {
			/* The server assigned our just-sent message its id: the view attaches the
			 * id to the message so later receipts and reactions can find it, and then
			 * draws the first tick, the way the official client shows "sent". */
			[[NSNotificationCenter defaultCenter] postNotificationName:@"AIChatMessageIdAssigned"
															    object:chat
															  userInfo:@{ @"MessageId": [NSString stringWithUTF8String:messageId] }];
			notificationName = @"AIChatMessageWasSent";
		} else if (strcmp(type, "delivered") == 0) {
			notificationName = @"AIChatMessageWasDelivered";
		} else if (strcmp(type, "read") == 0) {
			notificationName = @"AIChatMessageWasRead";
		} else {
			return; // read_self says nothing about our sent messages
		}

		[[NSNotificationCenter defaultCenter] postNotificationName:notificationName
														    object:chat
														  userInfo:@{ @"MessageId": [NSString stringWithUTF8String:messageId] }];
	}
}

static void whatsapp_reaction_cb(PurpleConnection *pc, GHashTable *details, gpointer data)
{
	@autoreleasepool {
		const char *messageId = whatsapp_detail(details, "id");
		const char *emoji = whatsapp_detail(details, "emoji");
		const char *sender = whatsapp_detail(details, "sender");
		const char *isGroup = whatsapp_detail(details, "isGroup");
		if (!messageId || !sender) return;

		AIChat *chat = whatsapp_chat_for_details(pc, details);
		if (!chat) return;

		/* Bucket per sender, as the view expects: our own reactions under "me", a
		 * room participant under their jid, the one contact of a direct chat under
		 * "them". WhatsApp reactions are whole-set-replace per sender (one emoji,
		 * empty for removal), matching the view's semantics exactly. */
		PurpleAccount	*account = purple_connection_get_account(pc);
		const char		*username = purple_account_get_username(account);
		NSString		*bucket;
		if (username && purple_strequal(username, sender)) {
			bucket = @"me";
		} else if (isGroup && strcmp(isGroup, "1") == 0) {
			bucket = [NSString stringWithUTF8String:sender];
		} else {
			bucket = @"them";
		}

		NSArray *reactions = (emoji && *emoji) ? @[[NSString stringWithUTF8String:emoji]] : @[];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"AIChatMessageReactionsChanged"
														    object:chat
														  userInfo:@{ @"MessageId": [NSString stringWithUTF8String:messageId],
																	  @"Reactions": reactions,
																	  @"Sender": bucket }];
	}
}

/*!
 * @brief Hook the plug-in's signals once the first WhatsApp account signs on
 *
 * The prpl is an external plug-in; its signals exist once libpurple has loaded
 * it, which is guaranteed by the time one of its accounts signs on.
 */
static void whatsapp_signed_on_cb(PurpleConnection *gc, gpointer data)
{
	PurpleAccount *account = purple_connection_get_account(gc);
	if (!purple_strequal(purple_account_get_protocol_id(account), WHATSAPP_PRPL_ID))
		return;

	/* Adium draws reactions as chips on the message; the plug-in's own textual
	 * rendering would say everything twice. */
	purple_account_set_string(account, "reaction-display", "none");

	static gboolean connected = FALSE;
	if (connected) return;

	PurplePlugin *whatsapp = purple_find_prpl(WHATSAPP_PRPL_ID);
	if (!whatsapp) return;
	connected = TRUE;

	purple_signal_connect(whatsapp, "gowhatsapp-message-id", &adium_purple_whatsapp_handle,
						  PURPLE_CALLBACK(whatsapp_message_id_cb), NULL);
	purple_signal_connect(whatsapp, "gowhatsapp-receipt", &adium_purple_whatsapp_handle,
						  PURPLE_CALLBACK(whatsapp_receipt_cb), NULL);
	purple_signal_connect(whatsapp, "gowhatsapp-reaction", &adium_purple_whatsapp_handle,
						  PURPLE_CALLBACK(whatsapp_reaction_cb), NULL);
}

void configureAdiumPurpleWhatsApp(void)
{
	purple_signal_connect(purple_connections_get_handle(), "signed-on", &adium_purple_whatsapp_handle,
						  PURPLE_CALLBACK(whatsapp_signed_on_cb), NULL);
}
