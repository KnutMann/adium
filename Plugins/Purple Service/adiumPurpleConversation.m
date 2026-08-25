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

#import "adiumPurpleConversation.h"
#import "adiumPurpleSignals.h"
#import <AIUtilities/AIObjectAdditions.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <Adium/AIChat.h>
#import <Adium/AIContentTyping.h>
#import <Adium/AIHTMLDecoder.h>
#import <Adium/AIListContact.h>
#import <Adium/AIContentControllerProtocol.h>
#import "AINudgeBuzzHandlerPlugin.h"

#pragma mark Purple Images

#pragma mark Conversations
static void adiumPurpleConvCreate(PurpleConversation *conv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	//Pass chats along to the account
	if (purple_conversation_get_type(conv) == PURPLE_CONV_TYPE_CHAT) {
		
		AIChat *chat = groupChatLookupFromConv(conv);
		
		[accountLookup(purple_conversation_get_account(conv)) addChat:chat];
	}
    [pool drain];
}

static void adiumPurpleConvDestroy(PurpleConversation *conv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	/* Purple is telling us a conv was destroyed.  We've probably already cleaned up, but be sure in case purple calls this
	 * when we don't ask it to (for example if we are summarily kicked from a chat room and purple closes the 'window').
	 */
	AIChat *chat = (AIChat *)conv->ui_data;

	AILogWithSignature(@"%p: %@", conv, chat);

	//Chat will be nil if we've already cleaned up, at which point no further action is needed.
	if (chat) {
		[accountLookup(purple_conversation_get_account(conv)) chatWasDestroyed:chat];

		[chat setIdentifier:nil];
		[chat release];
		conv->ui_data = nil;
	}
    [pool drain];
}

static void adiumPurpleConvWriteChat(PurpleConversation *conv, const char *who,
								   const char *message, PurpleMessageFlags flags,
								   time_t mtime)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

		NSDictionary	*messageDict;
		NSString		*messageString;

		messageString = [NSString stringWithUTF8String:message];
		AILog(@"Source: %s \t Name: %s \t MyNick: %s : Message %@", 
			  who,
			  purple_conversation_get_name(conv),
			  purple_conv_chat_get_nick(PURPLE_CONV_CHAT(conv)),
			  messageString);

		NSDate				*date = [NSDate dateWithTimeIntervalSince1970:mtime];
		PurpleAccount		*purpleAccount = purple_conversation_get_account(conv);
		
		if ((flags & PURPLE_MESSAGE_SYSTEM) == PURPLE_MESSAGE_SYSTEM || !who) {
			CBPurpleAccount *account = accountLookup(purpleAccount);
			
			[account receivedEventForChat:groupChatLookupFromConv(conv)
								  message:messageString
									 date:date
									flags:[NSNumber numberWithInteger:flags]];
		} else {
			//Process any purple imgstore references into real HTML tags pointing to real images
			CBPurpleAccount *adiumAccount = accountLookup(purple_conversation_get_account(conv));
			messageString = processPurpleImages(messageString, adiumAccount);

			NSAttributedString	*attributedMessage = [AIHTMLDecoder decodeHTML:messageString];
			NSNumber			*purpleMessageFlags = [NSNumber numberWithInteger:flags];
			NSString			*normalizedUID = get_real_name_for_account_conv_buddy(purpleAccount, conv, (char *)who);

			NSMutableDictionary *mutableChatDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
												   attributedMessage, @"AttributedMessage",
												   purpleMessageFlags, @"PurpleMessageFlags",
												   date, @"Date", nil];
			if (normalizedUID.length) [mutableChatDict setObject:normalizedUID forKey:@"Source"];

			/* The room stamped this message with a stanza-id, stashed in the callback that ran just
			 * before this one; take it now so it rides on the content object and a reaction naming
			 * the message by that id can find it. */
			NSString *messageId = adiumTakePendingIncomingGroupchatMessageId(purpleAccount);
			if (messageId) [mutableChatDict setObject:messageId forKey:@"MessageId"];

			messageDict = mutableChatDict;

			[accountLookup(purple_conversation_get_account(conv)) receivedMultiChatMessage:messageDict inChat:groupChatLookupFromConv(conv)];
		}
    [pool drain];
}

static void adiumPurpleConvWriteIm(PurpleConversation *conv, const char *who,
								 const char *message, PurpleMessageFlags flags,
								 time_t mtime)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	//We only care about this if it does not have the PURPLE_MESSAGE_SEND flag, which is set if Purple is sending a sent message back to us
	if ((flags & PURPLE_MESSAGE_SEND) == 0) {
		if (flags & PURPLE_MESSAGE_NOTIFY) {
			// We received a notification (nudge or buzz). Send a notification of such.
			NSString *type, *messageString = [NSString stringWithUTF8String:message];

			// Determine what we're actually notifying about.
			if ([messageString rangeOfString:@"nudge" options:(NSCaseInsensitiveSearch | NSLiteralSearch)].location != NSNotFound) {
				type = @"Nudge";
			} else if ([messageString rangeOfString:@"buzz" options:(NSCaseInsensitiveSearch | NSLiteralSearch)].location != NSNotFound) {
				type = @"Buzz";
			} else {
				// Just call an unknown type a "notification"
				type = @"notification";
			}

			[[NSNotificationCenter defaultCenter] postNotificationName:Chat_NudgeBuzzOccured
																			   object:chatLookupFromConv(conv)
																			 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
																					   type, @"Type",
																					   nil]];
		} else {
			NSDictionary		*messageDict;
			CBPurpleAccount		*adiumAccount = accountLookup(purple_conversation_get_account(conv));
			NSString			*messageString;
			AIChat				*chat;
			
			messageString = [NSString stringWithUTF8String:message];
			chat = chatLookupFromConv(conv);
			
			AILog(@"adiumPurpleConvWriteIm: Received %@ from %@", messageString, chat.listObject.UID);
			
			//Process any purple imgstore references into real HTML tags pointing to real images
			messageString = processPurpleImages(messageString, adiumAccount);
			
			NSMutableDictionary *mutableDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:messageString,@"Message",
						   [NSNumber numberWithInteger:flags],@"PurpleMessageFlags",
						   [NSDate dateWithTimeIntervalSince1970:mtime],@"Date",nil];

			/* The id the protocol gave this message was stashed a moment ago, in the callback that
			 * ran just before this one; take it now so it rides on the content object and a later
			 * reaction or read marker can find the message it names. */
			NSString *messageId = adiumTakePendingIncomingMessageId(purple_conversation_get_account(conv), who);
			if (messageId) [mutableDict setObject:messageId forKey:@"MessageId"];
			messageDict = mutableDict;

			[adiumAccount receivedIMChatMessage:messageDict
										 inChat:chat];
		}
	} else if ((flags & PURPLE_MESSAGE_REMOTE_SEND) == PURPLE_MESSAGE_REMOTE_SEND) {
		/* Our own message, written on another device and echoed back to us.
		 * It carries PURPLE_MESSAGE_SEND like the local echo of a message sent
		 * from here — which is why it used to be dropped above — but the
		 * protocol marks it as remote, so display it as our outgoing message. */
		CBPurpleAccount	*adiumAccount = accountLookup(purple_conversation_get_account(conv));
		AIChat			*chat = chatLookupFromConv(conv);
		NSString		*messageString = processPurpleImages([NSString stringWithUTF8String:message], adiumAccount);

		NSDictionary *messageDict = [NSDictionary dictionaryWithObjectsAndKeys:
									 messageString, @"Message",
									 [NSNumber numberWithInteger:flags], @"PurpleMessageFlags",
									 [NSDate dateWithTimeIntervalSince1970:mtime], @"Date", nil];

		[adiumAccount receivedIMChatMessageSentRemotely:messageDict inChat:chat];
	}
    [pool drain];
}

static void adiumPurpleConvWriteConv(PurpleConversation *conv, const char *who, const char *alias,
								   const char *message, PurpleMessageFlags flags,
								   time_t mtime)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	AILog(@"adiumPurpleConvWriteConv: Received %s from %s [%i]",message,who,flags);
	AIChat	*chat = chatLookupFromConv(conv);

	if (!chat) {
        [pool drain];
		return;
	}
	
	NSString			*messageString = [NSString stringWithUTF8String:message];
	
	if (!messageString) {
		AILogWithSignature(@"Received write without message: %@ %d", chat, flags);
        [pool drain];
		return;
	}
	
	if (flags & PURPLE_MESSAGE_ERROR) {	
		if ([messageString rangeOfString:@"User information not available"].location != NSNotFound) {
			//Ignore user information errors; they are irrelevent
			//XXX The user info check only works in English; libpurple should be modified to be better about this useless information spamming
            [pool drain];
			return;
		}
		
		AIChatErrorType	errorType = AIChatUnknownError;
		
		if (([messageString rangeOfString:[NSString stringWithUTF8String:_("Not logged in")]].location != NSNotFound) || 
			([messageString rangeOfString:[NSString stringWithUTF8String:_("User temporarily unavailable")]].location != NSNotFound)) {
			errorType = AIChatMessageSendingUserNotAvailable;
		} else if ([messageString rangeOfString:[NSString stringWithUTF8String:_("In local permit/deny")]].location != NSNotFound) {
			errorType = AIChatMessageSendingUserIsBlocked;
		} else if (([messageString rangeOfString:[NSString stringWithUTF8String:_("Reply too big")]].location != NSNotFound) ||
				   ([messageString rangeOfString:@"message is too large"].location != NSNotFound)) {
			//XXX - there may be other conditions, but this seems the most common so that's how we'll classify it
			errorType = AIChatMessageSendingTooLarge;
		} else if ([messageString rangeOfString:[NSString stringWithUTF8String:_("Command failed")]].location != NSNotFound) {
			errorType = AIChatCommandFailed;
		} else if ([messageString rangeOfString:[NSString stringWithUTF8String:_("Wrong number of arguments")]].location != NSNotFound) {
			errorType = AIChatInvalidNumberOfArguments;
		} else if ([messageString rangeOfString:[NSString stringWithUTF8String:_("Rate")]].location != NSNotFound) {
			//XXX Is 'Rate' really a standalone translated string?
			errorType = AIChatMessageSendingMissedRateLimitExceeded;
		} else if ([messageString rangeOfString:[NSString stringWithUTF8String:_("Too evil")]].location != NSNotFound) {
			errorType = AIChatMessageReceivingMissedRemoteIsTooEvil;
		}
		/* Another is 'refused by client', which is definitely seen when sending an offline message to an invalid screenname...
		 * but I don't know when else it is sent. -evands
		 */
		
		/* We will wait until the next run loop, in case this error message was generated by
		 * the sending of a message. This allows the results of sending the message to be displayed
		 * first.
		 */
		if (errorType != AIChatUnknownError) {
			[accountLookup(purple_conversation_get_account(conv)) performSelector:@selector(errorForChat:type:)
																	   withObject:chat
																	   withObject:[NSNumber numberWithInteger:errorType]
																	   afterDelay:0];
		} else {
			[adium.contentController performSelector:@selector(displayEvent:ofType:inChat:)
										  withObject:messageString
										  withObject:@"libpurpleMessage"
										  withObject:chat
										  afterDelay:0];
		}
		
		AILog(@"*** Conversation error %@: %@", chat, messageString);
	} else {
		/* What stood here caught the notices of a Direct IM, OSCAR's peer to peer conversation, and
		 * either turned them into a contact event or swallowed them. None of the six messages it
		 * matched exists in any protocol Adium still ships, so nothing was ever caught, and the last
		 * of them was matched against untranslated English anyway.
		 */
		BOOL				shouldDisplayMessage = TRUE;

		if (shouldDisplayMessage) {
			CBPurpleAccount *account = accountLookup(purple_conversation_get_account(conv));
			
			[account performSelector:@selector(receivedEventForChat:message:date:flags:)
						  withObject:chat
						  withObject:messageString
						  withObject:[NSDate dateWithTimeIntervalSince1970:mtime]
						  withObject:[NSNumber numberWithInteger:flags]
						  afterDelay:0];
		}
	}
    [pool drain];
}

NSString *get_real_name_for_account_conv_buddy(PurpleAccount *account, PurpleConversation *conv, char *who)
{
	g_return_val_if_fail(who != NULL && strlen(who), nil);
	
	PurplePlugin *prpl = purple_find_prpl(purple_account_get_protocol_id(account));
	PurplePluginProtocolInfo  *prpl_info = (prpl ? PURPLE_PLUGIN_PROTOCOL_INFO(prpl) : NULL);
	PurpleConvChat *convChat = purple_conversation_get_chat_data(conv);
	
	char *uid = NULL;
	
	NSString *normalizedUID;
	
	if (prpl_info && prpl_info->get_cb_real_name) {
		// Get the real name of the buddy for use as a UID, if available.
		uid = prpl_info->get_cb_real_name(purple_account_get_connection(account),
										  purple_conv_chat_get_id(convChat),
										  who);
	}
	
	if (!uid) {
		// strdup it, mostly so the free below won't have to be cased out.
		uid = g_strdup(who);
	}
		
	normalizedUID = [NSString stringWithUTF8String:purple_normalize(account, uid)];
		
	// We have to free the result of get_cb_real_name.
	g_free(uid);

	return normalizedUID;
}

static void adiumPurpleConvChatAddUsers(PurpleConversation *conv, GList *cbuddies, gboolean new_arrivals)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	if (purple_conversation_get_type(conv) == PURPLE_CONV_TYPE_CHAT) {
		PurpleAccount *account = purple_conversation_get_account(conv);

		NSMutableArray *users = [NSMutableArray array];
		
		for (GList *l = cbuddies; l; l = l->next) {
			PurpleConvChatBuddy *cb = (PurpleConvChatBuddy *)l->data;
			
			/* Prefer the protocol-provided alias (e.g. the WhatsApp address book
			 * name); fall back to cb->name, which XMPP formats as the nick. */
			NSMutableDictionary *user = [NSMutableDictionary dictionary];
			[user setObject:get_real_name_for_account_conv_buddy(account, conv, cb->name) forKey:@"UID"];
			[user setObject:[NSNumber numberWithInteger:cb->flags] forKey:@"Flags"];
			[user setObject:[NSString stringWithUTF8String:((cb->alias && *cb->alias) ? cb->alias : cb->name)] forKey:@"Alias"];
			
			[users addObject:user];
		}

		/* The conversation title (e.g. the WhatsApp group name) may have been set
		 * before this chat existed on the Adium side; sync it now. */
		{
			const char *convTitle = purple_conversation_get_title(conv);
			const char *convName = purple_conversation_get_name(conv);
			if (convTitle && convName && !purple_strequal(convTitle, convName)) {
				[accountLookup(account) updateTitle:[NSString stringWithUTF8String:convTitle]
											forChat:groupChatLookupFromConv(conv)];
			}
		}

		[accountLookup(account) updateUserListForChat:groupChatLookupFromConv(conv)
												users:users
										   newlyAdded:new_arrivals];
	} else
		AILog(@"adiumPurpleConvChatAddUsers: IM");
    [pool drain];
}

static void adiumPurpleConvChatRenameUser(PurpleConversation *conv, const char *oldName,
										const char *newName, const char *newAlias)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	AILog(@"adiumPurpleConvChatRenameUser: %s: oldName %s, newName %s, newAlias %s",
			   purple_conversation_get_name(conv),
			   oldName, newName, newAlias);
	
	if (purple_conversation_get_type(conv) == PURPLE_CONV_TYPE_CHAT) {
		PurpleConvChat *convChat = purple_conversation_get_chat_data(conv);
		PurpleConvChatBuddy *cb = purple_conv_chat_cb_find(convChat, oldName);
		
		PurpleAccount *account = purple_conversation_get_account(conv);
		
		// Ignore newAlias and set the alias to newName
		
		[accountLookup(purple_conversation_get_account(conv)) renameParticipant:get_real_name_for_account_conv_buddy(account, conv, (char *)oldName)
																		newName:get_real_name_for_account_conv_buddy(account, conv, (char *)newName)
																	   newAlias:[NSString stringWithUTF8String:newName]
																		  flags:cb->flags
																		 inChat:groupChatLookupFromConv(conv)];
	}
    [pool drain];
}

static void adiumPurpleConvChatRemoveUsers(PurpleConversation *conv, GList *users)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	if (purple_conversation_get_type(conv) == PURPLE_CONV_TYPE_CHAT) {
		NSMutableArray	*usersArray = [NSMutableArray array];
		PurpleAccount	*account = purple_conversation_get_account(conv);

		GList *l;
		for (l = users; l != NULL; l = l->next) {
			NSString *normalizedUID = get_real_name_for_account_conv_buddy(account, conv, (char *)l->data);
			[usersArray addObject:normalizedUID];
		}

		[accountLookup(account) removeUsersArray:usersArray
										fromChat:groupChatLookupFromConv(conv)];

	} else {
		AILog(@"adiumPurpleConvChatRemoveUser: IM");
	}
    [pool drain];
}

static void adiumPurpleConvUpdateUser(PurpleConversation *conv, const char *user)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	PurpleAccount *account = purple_conversation_get_account(conv);
	CBPurpleAccount *adiumAccount = accountLookup(account);
	
	PurpleConvChatBuddy *cb = purple_conv_chat_cb_find(PURPLE_CONV_CHAT(conv), user);
	
	NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
	
	GList *attribute = purple_conv_chat_cb_get_attribute_keys(cb);
	
	for (; attribute != NULL; attribute = g_list_next(attribute)) {
		[attributes setObject:[NSString stringWithUTF8String:purple_conv_chat_cb_get_attribute(cb, attribute->data)]
					   forKey:[NSString stringWithUTF8String:attribute->data]];
	}
	
	g_list_free(attribute);
	
	// We use cb->name for the alias field, since libpurple sets the one we're after (the chat name) formatted correctly inside.
	NSString *name = cb->name ? [NSString stringWithUTF8String:cb->name] : nil;
	
	[adiumAccount updateUser:get_real_name_for_account_conv_buddy(account, conv, (char *)user)
					 forChat:groupChatLookupFromConv(conv)
					   flags:cb->flags
					   alias:name
				  attributes:attributes];
    [pool drain];
}

static void adiumPurpleConvPresent(PurpleConversation *conv)
{
	
}

//This isn't a function we want Purple doing anything with, I don't think
/*!
 * @brief Is the user looking at this conversation right now?
 *
 * A protocol asks this before telling the other side that their message was read, so answering no to
 * everything, which is what this did, meant Adium never sent a read receipt on any protocol that
 * bothers to ask. Telegram is one. A protocol whose user interface does not offer this callback at
 * all is better off, because it can fall back to assuming yes; offering it and always saying no is
 * the one answer with no way around it.
 *
 * Three things have to hold. The chat is the active one, its window is the one keyboard input goes
 * to, and Adium is the application in front. A chat selected in a window buried behind another
 * application is not being read.
 */
static gboolean adiumPurpleConvHasFocus(PurpleConversation *conv)
{
	AIChat *chat = chatLookupFromConv(conv);

	if (!chat || ![NSApp isActive])
		return NO;

	NSWindow *window = [(NSWindowController *)[[chat chatContainer] windowController] window];

	return (window && [window isKeyWindow] &&
			[adium.interfaceController activeChatInWindow:window] == chat);
}

static void adiumPurpleConvUpdated(PurpleConversation *conv, PurpleConvUpdateType type)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	if (purple_conversation_get_type(conv) == PURPLE_CONV_TYPE_CHAT) {
		PurpleConvChat  *chat = purple_conversation_get_chat_data(conv);
		
		switch(type) {
			case PURPLE_CONV_UPDATE_TOPIC:
			{
				NSString *who = nil;
				
				if (chat->who != NULL) {
					who = [NSString stringWithUTF8String:chat->who];
				}
				
				[accountLookup(purple_conversation_get_account(conv)) updateTopic:(purple_conv_chat_get_topic(chat) ?
																				   [NSString stringWithUTF8String:purple_conv_chat_get_topic(chat)] :
																				   nil)
																		  forChat:groupChatLookupFromConv(conv)
																	   withSource:who];
				break;
			}
			case PURPLE_CONV_UPDATE_TITLE: {
				const char	*newTitle = purple_conversation_get_title(conv);
				NSString	*titleString = (newTitle ? [NSString stringWithUTF8String:newTitle] : nil);

				/* No title at all means "drop the one you have"; a title we could not decode
				 * does not. +stringWithUTF8String: hands back nil for bytes which aren't valid
				 * UTF-8, and passing that on would clear the chat's name and leave the window
				 * showing the room ID. */
				if (!newTitle || titleString) {
					[accountLookup(purple_conversation_get_account(conv)) updateTitle:titleString
																			 forChat:groupChatLookupFromConv(conv)];
				}

				AILog(@"Update to title: %s",newTitle);
				break;
			}
			case PURPLE_CONV_UPDATE_CHATLEFT:
				[accountLookup(purple_conversation_get_account(conv)) leftChat:groupChatLookupFromConv(conv)];
				break;
			case PURPLE_CONV_UPDATE_ADD:
			case PURPLE_CONV_UPDATE_REMOVE:
			case PURPLE_CONV_UPDATE_ACCOUNT:
			case PURPLE_CONV_UPDATE_TYPING:
			case PURPLE_CONV_UPDATE_UNSEEN:
			case PURPLE_CONV_UPDATE_LOGGING:
			case PURPLE_CONV_ACCOUNT_ONLINE:
			case PURPLE_CONV_ACCOUNT_OFFLINE:
			case PURPLE_CONV_UPDATE_AWAY:
			case PURPLE_CONV_UPDATE_ICON:
			case PURPLE_CONV_UPDATE_FEATURES:

/*				
				[accountLookup(purple_conversation_get_account(conv)) mainPerformSelector:@selector(convUpdateForChat:type:)
													   withObject:groupChatLookupFromConv(conv)
													   withObject:[NSNumber numberWithInt:type]];
*/				
			default:
				break;
		}

	} else if (purple_conversation_get_type(conv) == PURPLE_CONV_TYPE_IM) {
		PurpleConvIm  *im = purple_conversation_get_im_data(conv);
		switch (type) {
			case PURPLE_CONV_UPDATE_TYPING: {

				AITypingState typingState;

				switch (purple_conv_im_get_typing_state(im)) {
					case PURPLE_TYPING:
						typingState = AITyping;
						break;
					case PURPLE_TYPED:
						typingState = AIEnteredText;
						break;
					case PURPLE_NOT_TYPING:
					default:
						typingState = AINotTyping;
						break;
				}

				NSNumber	*typingStateNumber = [NSNumber numberWithInteger:typingState];

				[accountLookup(purple_conversation_get_account(conv)) typingUpdateForIMChat:imChatLookupFromConv(conv)
															 typing:typingStateNumber];
				break;
			}
			case PURPLE_CONV_UPDATE_AWAY: {
				//If the conversation update is UPDATE_AWAY, it seems to suppress the typing state being updated
				//Reset purple's typing tracking, then update to receive a PURPLE_CONV_UPDATE_TYPING message
				purple_conv_im_set_typing_state(im, PURPLE_NOT_TYPING);
				purple_conv_im_update_typing(im);
				break;
			}
			default:
				break;
		}
	}
    [pool drain];
}

#pragma mark Custom smileys
static gboolean adiumPurpleConvCustomSmileyAdd(PurpleConversation *conv, const char *smile, gboolean remote)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	AILog(@"%s: Added Custom Smiley %s",purple_conversation_get_name(conv),smile);
	[accountLookup(purple_conversation_get_account(conv)) chat:chatLookupFromConv(conv)
			 isWaitingOnCustomEmoticon:[NSString stringWithUTF8String:smile]];
    [pool drain];

	return TRUE;
}

static void adiumPurpleConvCustomSmileyWrite(PurpleConversation *conv, const char *smile,
									const guchar *data, gsize size)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	AILog(@"%s: Write Custom Smiley %s (%p %lu)",purple_conversation_get_name(conv),smile,data,size);

	[accountLookup(purple_conversation_get_account(conv)) chat:chatLookupFromConv(conv)
					 setCustomEmoticon:[NSString stringWithUTF8String:smile]
						 withImageData:[NSData dataWithBytes:data
													  length:size]];
    [pool drain];
}

static void adiumPurpleConvCustomSmileyClose(PurpleConversation *conv, const char *smile)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	AILog(@"%s: Close Custom Smiley %s",purple_conversation_get_name(conv),smile);

	[accountLookup(purple_conversation_get_account(conv)) chat:chatLookupFromConv(conv)
				  closedCustomEmoticon:[NSString stringWithUTF8String:smile]];
    [pool drain];
}

static gboolean adiumPurpleConvJoin(PurpleConversation *conv, const char *name,
									PurpleConvChatBuddyFlags flags,
									GHashTable *users)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	AIChat *chat = groupChatLookupFromConv(conv);
    [pool drain];
	// We return TRUE if we want to hide it.
	return !chat.showJoinLeave;
}

static gboolean adiumPurpleConvLeave(PurpleConversation *conv, const char *name,
									 const char *reason, GHashTable *users)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	AIChat *chat = groupChatLookupFromConv(conv);
    [pool drain];
	
	// We return TRUE if we want to hide it.
	return !chat.showJoinLeave;	
}

static PurpleConversationUiOps adiumPurpleConversationOps = {
	adiumPurpleConvCreate,
    adiumPurpleConvDestroy,
    adiumPurpleConvWriteChat,
    adiumPurpleConvWriteIm,
    adiumPurpleConvWriteConv,
    adiumPurpleConvChatAddUsers,
    adiumPurpleConvChatRenameUser,
    adiumPurpleConvChatRemoveUsers,
	adiumPurpleConvUpdateUser,
	
	adiumPurpleConvPresent,
	adiumPurpleConvHasFocus,

	/* Custom Smileys */
	adiumPurpleConvCustomSmileyAdd,
	adiumPurpleConvCustomSmileyWrite,
	adiumPurpleConvCustomSmileyClose,

	/* send_confirm */
	NULL,
	
	/* _purple_reserved 1-4 */
	NULL, NULL, NULL, NULL
};

PurpleConversationUiOps *adium_purple_conversation_get_ui_ops(void)
{
	return &adiumPurpleConversationOps;
}

void adiumPurpleConversation_init(void)
{	
	purple_conversations_set_ui_ops(adium_purple_conversation_get_ui_ops());

	purple_signal_connect_priority(purple_conversations_get_handle(), "conversation-updated", adium_purple_get_handle(),
								 PURPLE_CALLBACK(adiumPurpleConvUpdated), NULL,
								 PURPLE_SIGNAL_PRIORITY_LOWEST);
	
	purple_signal_connect(purple_conversations_get_handle(), "chat-buddy-joining", adium_purple_get_handle(),
						  PURPLE_CALLBACK(adiumPurpleConvJoin), NULL);
	
	purple_signal_connect(purple_conversations_get_handle(), "chat-buddy-leaving", adium_purple_get_handle(),
						  PURPLE_CALLBACK(adiumPurpleConvLeave), NULL);
	
}
