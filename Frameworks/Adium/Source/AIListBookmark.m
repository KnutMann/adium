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

#import "AIListBookmark.h"
#import <Adium/AIAccount.h>
#import <Adium/AIListGroup.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIChatControllerProtocol.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIUserIcons.h>
#import <Adium/AIService.h>
#import <Adium/AIChat.h>
#import <Adium/AIContactList.h>
#import <AIUtilities/AIAttributedStringAdditions.h>

#define	KEY_CONTAINING_OBJECT_UID	@"ContainingObjectUID"

#define KEY_ACCOUNT_INTERNAL_ID		@"AccountInternalObjectID"

/* The last title we took over from a chat. Stored so that -hasOwnDisplayName can tell a name
 * we merely copied from the protocol apart from one the user typed; the alias preference alone
 * cannot, since both end up in it. */
#define KEY_ADOPTED_DISPLAY_NAME	@"Adopted Display Name"

@interface AIListBookmark () {
	/* YES while -adoptDisplayNameFromChat: is inside -setDisplayName:, so that our own write
	 * isn't mistaken for the user picking a name. */
	BOOL		adoptingDisplayName;

	//The last name we pushed onto a chat, so we can tell our leftovers from a protocol title.
	NSString	*pushedDisplayName;
}
- (BOOL)chatIsOurs:(AIChat *)chat;
- (AIChat *)openChatWithoutActivating;
- (void)restoreGrouping;

- (void)claimChatIfOurs:(AIChat *)chat;
- (void)reconcileChatCreationDictionaryWithChat:(AIChat *)chat;

- (BOOL)hasOwnDisplayName;
- (void)adoptDisplayNameFromChat:(AIChat *)chat;
- (void)pushDisplayName:(NSString *)inDisplayName toChat:(AIChat *)chat;

- (void)_updateUnreadMessagesStatusForChat:(AIChat *)inChat;
@end

/*!
 * @brief Shorten a room ID for logging
 *
 * A WhatsApp room ID is "<phone number>-<timestamp>@g.us", and the debug log is something a
 * user is asked to hand over. Keep the tail of the local part - enough to recognise one room
 * across a log - and drop the rest.
 */
static NSString *AIRedactedRoomID(NSString *roomID)
{
	if (!roomID.length)
		return roomID;

	NSRange		at = [roomID rangeOfString:@"@" options:NSBackwardsSearch];
	NSString	*localPart = (at.location == NSNotFound ? roomID : [roomID substringToIndex:at.location]);
	NSString	*domain = (at.location == NSNotFound ? @"" : [roomID substringFromIndex:at.location]);

	if (localPart.length > 4)
		localPart = [NSString stringWithFormat:@"…%@", [localPart substringFromIndex:(localPart.length - 4)]];

	return [localPart stringByAppendingString:domain];
}

@implementation AIListBookmark

@synthesize name, password, chatCreationDictionary;

- (id)initWithUID:(NSString *)inUID
		  account:(AIAccount *)inAccount
		  service:(AIService *)inService
	   dictionary:(NSDictionary *)inChatCreationDictionary
			 name:(NSString *)inName
{
	if ((self = [super initWithUID:inUID
						   account:inAccount
						   service:inService])) {
		chatCreationDictionary = [inChatCreationDictionary copy];
		name = [inName copy];
		
		[adium.chatController registerChatObserver:self];
		
		[self.account addObserver:self
					   forKeyPath:@"isOnline"
						  options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial)
						  context:NULL];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
									 selector:@selector(chatDidOpen:) 
										 name:Chat_DidOpen
									   object:nil];
		
		// Scan all open chats to claim them, if we loaded after they were available.
		for (AIChat *chat in adium.interfaceController.openChats) {
			[self claimChatIfOurs:chat];
		}
		
		AILog(@"Created %@", self);
		
	}
	
	return self;
}

-(id)initWithChat:(AIChat *)inChat
{
	if ((self = [self initWithUID:[NSString stringWithFormat:@"Bookmark:%@", inChat.uniqueChatID]
						  account:inChat.account
						  service:inChat.account.service
					   dictionary:inChat.chatCreationDictionary
							 name:inChat.name])) {
		/* Take the title the same way we would at any later point, so that a name we only
		 * copied from the protocol keeps following the group's renames instead of freezing
		 * at whatever the group was called the day the bookmark was made. */
		[self adoptDisplayNameFromChat:inChat];

		if ([inChat valueForProperty:KEY_TOPIC]) {
			[self setStatusMessage:[NSAttributedString stringWithString:[inChat valueForProperty:KEY_TOPIC]] notify:NotifyNow];
		}
		
		[self _updateUnreadMessagesStatusForChat:inChat];
	}
	
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
	NSString *accountInternalObjectID = [decoder decodeObjectForKey:KEY_ACCOUNT_INTERNAL_ID];
	AIAccount *myAccount = [adium.accountController accountWithInternalObjectID:accountInternalObjectID];

	if (!myAccount) {
		/* We are about to vanish without a trace, and the next -saveContactList would write
		 * the shortened list back. Say who we were, so the next time bookmarks go missing
		 * there is something to read - but a room ID is a phone number on WhatsApp, so log
		 * only as much of it as it takes to tell two bookmarks apart. */
		AILogWithSignature(@"No account %@ for bookmark %@ (service %@) - not loading it",
						   accountInternalObjectID,
						   AIRedactedRoomID([decoder decodeObjectForKey:@"name"]),
						   [decoder decodeObjectForKey:@"ServiceID"]);
		[self release];
		return nil;
	}

	if ((self = [self initWithUID:[decoder decodeObjectForKey:@"UID"]
						  account:myAccount
						  service:[adium.accountController firstServiceWithServiceID:[decoder decodeObjectForKey:@"ServiceID"]]
					   dictionary:[decoder decodeObjectForKey:@"chatCreationDictionary"]
							 name:[decoder decodeObjectForKey:@"name"]])) {
		[self restoreGrouping];
	}
	return self;
}


- (void)encodeWithCoder:(NSCoder *)encoder
{
	[encoder encodeObject:self.UID forKey:@"UID"];
	[encoder encodeObject:self.account.internalObjectID forKey:KEY_ACCOUNT_INTERNAL_ID];
	[encoder encodeObject:self.service.serviceID forKey:@"ServiceID"];
	[encoder encodeObject:self.chatCreationDictionary forKey:@"chatCreationDictionary"];
	[encoder encodeObject:name forKey:@"name"];
}

- (void)dealloc
{
	[name release]; name = nil;
	[chatCreationDictionary release]; chatCreationDictionary = nil;
	[password release]; password = nil;
	[pushedDisplayName release]; pushedDisplayName = nil;
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[adium.chatController unregisterChatObserver:self];
	[self.account removeObserver:self forKeyPath:@"isOnline"];

	[super dealloc];
}

/*!
 * @brief Remove ourself
 *
 * We've been asked to be removed. Ask the contact controller to do so.
 */
- (void)removeFromGroup:(AIListObject <AIContainingObject> *)group
{
	[adium.contactController removeBookmark:self];
}

/*!
 * @brief Our formatted UID
 *
 * If we're in an active chat, returns the name of the chat; otherwise, our UID.
 */
- (NSString *)formattedUID
{
	AIChat *chat = [adium.chatController existingChatWithName:[self name]
													onAccount:self.account];
	
	if ([self chatIsOurs:chat]) {
		return chat.name;
	} else {
		return self.name;
	}
}

- (BOOL) existsServerside
{
	return NO; //TODO: protocols where this can be yes, like XMPP
}

/*!
 * @brief Internal ID for this object
 *
 * An object ID generated by Adium that is shared by all objects which are, to most intents and purposes, identical to
 * this object.  Ths ID is composed of the service ID and UID, so any object with identical services and object IDs
 * will have the same value here.
 */
- (NSString *)internalObjectID
{
	if (!internalObjectID) {
		NSAssert(self.account != nil, @"Null list bookmark account - make sure you didn't try to touch the internalObjectID before it was loaded.");
		
		// We're not like any other bookmarks by the same name.
		internalObjectID = [[NSString stringWithFormat:@"%@.%@.%@", self.service.serviceID, self.UID, self.account.UID] retain];
	}
	
	return internalObjectID;
}

/*!
 * @brief Set our display name
 *
 * Update the display name of our chat if our display name changes.
 */
- (void)setDisplayName:(NSString *)inDisplayName
{
	BOOL adopting = adoptingDisplayName;

	if (!adopting) {
		/* Every other caller is the user renaming us, one way or another - from here on this
		 * is a name of our own and a protocol title must not overrule it. Writing back the
		 * very name we adopted doesn't count: the info inspector sends the field's contents
		 * whenever it loses focus, and merely tabbing through it must not freeze the name. */
		NSString *adopted = [self preferenceForKey:KEY_ADOPTED_DISPLAY_NAME group:GROUP_LIST_BOOKMARK];

		if (adopted && ![adopted isEqualToString:inDisplayName])
			[self setPreference:nil forKey:KEY_ADOPTED_DISPLAY_NAME group:GROUP_LIST_BOOKMARK];
	}

	[super setDisplayName:inDisplayName];

	if (adopting)
		return;			//The chat is where the name came from; there is nothing to push back.

	AIChat *chat = [adium.chatController existingChatWithName:[self name]
					onAccount:self.account];

	if (![self chatIsOurs:chat])
		return;

	if ([self hasOwnDisplayName]) {
		[self pushDisplayName:self.displayName toChat:chat];

	} else if (pushedDisplayName && [pushedDisplayName isEqualToString:chat.displayName]) {
		/* Our name was just cleared and the chat is still showing what we put there. Leaving
		 * it would make the name unremovable while the chat is open - and -updateChat: would
		 * read our own leftover straight back out again as if the protocol had sent it. Hand
		 * the chat its own name back; if the protocol knows a title it will send it again,
		 * and having no alias means precisely "call it whatever the protocol calls it".
		 * A title we did not write is left alone - it is not ours to delete. */
		[self pushDisplayName:chat.name toChat:chat];
	}
}

/*!
 * @brief Put a name onto our chat and remember that we did
 *
 * The chat's Display Name array records the chat itself as the owner, no matter who wrote the
 * entry, so nothing else can tell our doing from the protocol's afterwards.
 */
- (void)pushDisplayName:(NSString *)inDisplayName toChat:(AIChat *)chat
{
	if ([inDisplayName isEqualToString:chat.displayName])
		return;

	[pushedDisplayName release];
	pushedDisplayName = [inDisplayName copy];

	chat.displayName = inDisplayName;
}

/*!
 * @brief Do we carry a name of our own?
 *
 * Without an alias our display name falls back to our formattedUID, which for a group chat
 * is the room ID the protocol uses internally - for WhatsApp the group JID. That is not a
 * name; it is what we would like to get rid of.
 *
 * A title we adopted from a chat isn't one of our own either, even though it sits in the same
 * alias preference a typed name does: the group may be renamed, and the new name has to win.
 * That is what KEY_ADOPTED_DISPLAY_NAME is for.
 */
- (BOOL)hasOwnDisplayName
{
	NSString *ourName = self.displayName;

	if (!ourName.length)
		return NO;

	NSString *adopted = [self preferenceForKey:KEY_ADOPTED_DISPLAY_NAME group:GROUP_LIST_BOOKMARK];
	if (adopted && [ourName isEqualToString:adopted])
		return NO;

	/* Our formattedUID hands back the chat's name while a chat of ours is open, and that is
	 * the normalized spelling of our own name - so compare both normalized. */
	AIService *service = self.account.service;
	return ![[service normalizeChatName:ourName] isEqualToString:[service normalizeChatName:self.name]];
}

/*!
 * @brief Take over the name the protocol gave our chat
 *
 * Bookmarks created before the chat had a readable title carry the room ID as their name;
 * WhatsApp group chats are the usual case, since the group name only becomes known once the
 * conversation exists. As soon as a chat of ours knows better, adopt it - but never over a
 * name the user picked, which is what -hasOwnDisplayName guards.
 *
 * The name is written twice: as the alias, so the contact list shows it and it survives a
 * restart, and into KEY_ADOPTED_DISPLAY_NAME, so we still know next time that it wasn't ours.
 * -setDisplayName: fires chatStatusChanged and brings us back through
 * -updateChat:keys:silent:; the second pass finds the same name already in place and stops at
 * the guard below.
 */
- (void)adoptDisplayNameFromChat:(AIChat *)chat
{
	if ([self hasOwnDisplayName])
		return;

	NSString	*chatName = chat.displayName;
	AIService	*service = self.account.service;

	/* A chat with no title of its own reports its room ID here; that is what we already are.
	 * Compare normalized: AIChatController hands a new chat the unnormalized name as its
	 * display name while chat.name is normalized, so the two differ by case alone for
	 * services whose room IDs aren't lowercase to begin with (IRC, XMPP MUCs). */
	if (!chatName.length ||
		[[service normalizeChatName:chatName] isEqualToString:[service normalizeChatName:self.name]])
		return;

	if ([chatName isEqualToString:self.displayName])
		return;			//Already adopted - don't rewrite the preferences on every update.

	AILogWithSignature(@"%@: adopting \"%@\"", self.logDescription, chatName);

	adoptingDisplayName = YES;
	[self setPreference:chatName forKey:KEY_ADOPTED_DISPLAY_NAME group:GROUP_LIST_BOOKMARK];
	[self setDisplayName:chatName];
	adoptingDisplayName = NO;
}

/*!
 * @brief For a newly created bookmark, set the group that -restoreGrouping will move us to. This is saved, so has no use on existing bookmarks
 */
- (void)setInitialGroup:(AIListGroup *)inGroup
{
	[self setPreference:inGroup.UID
				 forKey:KEY_CONTAINING_OBJECT_UID
				  group:PREF_GROUP_OBJECT_STATUS_CACHE];	
}

/*!
 * @brief Add a containing group
 *
 * When adding a containing group, save the group's UID so that we can rejoin the group next time.
 */
- (void)addContainingGroup:(AIListGroup *)inGroup
{
	[super addContainingGroup:inGroup];
	
	NSString *groupUID = inGroup.UID;
	NSString *savedGroupUID = [self preferenceForKey:KEY_CONTAINING_OBJECT_UID group:PREF_GROUP_OBJECT_STATUS_CACHE];
	
	if((!savedGroupUID || ![groupUID isEqualToString:savedGroupUID]) &&
		(inGroup != adium.contactController.contactList)) {
		// We either don't have a group, or this is a new, non-root-list group. Set our preference.
		
		[self setPreference:groupUID
					 forKey:KEY_CONTAINING_OBJECT_UID
					  group:PREF_GROUP_OBJECT_STATUS_CACHE];
	}
}

/*!
 * @brief Restore grouping
 *
 * When asked to restore grouping, move ourselves to the appropriate AIListGroup:
 * - The root contact list if contact list groups are disabled, or
 * - The last saved group. If the last saved group is missing for some reason, we move to "Bookmarks".
 */
- (void)restoreGrouping
{
	NSSet *targetGroup = nil;
	// In reality, it's extremely unlikely the saved group would be lost.
	NSString *savedGroupUID = [self preferenceForKey:KEY_CONTAINING_OBJECT_UID group:PREF_GROUP_OBJECT_STATUS_CACHE] ?: AILocalizedString(@"Bookmarks", nil);

	if (adium.contactController.useContactListGroups) {
		targetGroup = [NSSet setWithObject:[adium.contactController groupWithUID:savedGroupUID]];
	} else {
		targetGroup = [NSSet setWithObject:adium.contactController.contactList];
	}

	[adium.contactController moveContact:self fromGroups:self.groups intoGroups:targetGroup];
}

/*!
 * @brief Open our chat
 *
 * @return A chat for the bookmark
 *
 * This is called when we are double-clicked in the contact list.
 * Either find or create a chat appropriately, and activate it.
 */
- (AIChat *)openChat
{
	AIChat *chat = [self openChatWithoutActivating];
	
	if (!chat) {
		return nil;
	}
	
	if(!chat.isOpen) {
		[adium.interfaceController openChat:chat];
	}
	
	[adium.interfaceController setActiveChat:chat];
	
	return chat;
}

/*!
 * @brief Open our chat without activating it
 *
 * This is called when joining automatically on connect, and within the
 * method which opens on double click.
 */
- (AIChat *)openChatWithoutActivating
{
	AIChat *chat = [adium.chatController existingChatWithName:self.name
					onAccount:self.account];

	/* If the room is already open, its join information is the real thing. Take that before
	 * reaching for the prpl's defaults below, which are only an educated guess. */
	if ([self chatIsOurs:chat])
		[self reconcileChatCreationDictionaryWithChat:chat];

	if (self.account.joiningGroupChatRequiresCreationDictionary && !self.chatCreationDictionary) {
		/* Bookmarks used to be stored without any join information, so every one of them
		 * ends up here through no fault of the user. Ask the account what it would use to
		 * join this room and mend the bookmark rather than offering to throw it away. */
		NSDictionary *repairedDictionary = [self.account defaultChatCreationDictionaryForChatName:self.name];

		if (repairedDictionary) {
			AILogWithSignature(@"%@ had no chat creation dictionary; using the protocol's defaults for this room",
							   self.logDescription);
			[chatCreationDictionary release];
			chatCreationDictionary = [repairedDictionary copy];
			[adium.contactController saveContactList];

		} else {
			NSAlert *alert = [[[NSAlert alloc] init] autorelease];
			[alert setMessageText:AILocalizedString(@"Unable to join bookmarked chat", nil)];
			[alert setInformativeText:[NSString stringWithFormat:
									   AILocalizedString(@"The bookmark %@ does not contain enough information and can not be used. Please recreate it next time you join the chat.\nWould you like to remove this bookmark?", nil),
									   [self displayName]]];
			/* Cancel goes first, and so is the default: a stray Return must not delete
			 * something the user collected. An account which is merely offline lands here
			 * too, and then there is nothing wrong with the bookmark at all. */
			[alert addButtonWithTitle:AILocalizedStringFromTable(@"Cancel", @"Buttons", nil)];	//NSAlertFirstButtonReturn
			[alert addButtonWithTitle:AILocalizedStringFromTable(@"Delete", @"Buttons", nil)];	//NSAlertSecondButtonReturn
			if ([alert runModal] == NSAlertSecondButtonReturn) {
				AILogWithSignature(@"Removing %@ at the user's request (no chat creation dictionary)",
								   self.logDescription);
				[adium.contactController removeBookmark:self];
			}
			return nil;
		}
	}

	if (![self chatIsOurs:chat]) {
		//Open a new group chat (bookmarked chat)
		chat = [adium.chatController chatWithName:self.name
				identifier:NULL
				onAccount:self.account
				chatCreationInfo:self.chatCreationDictionary];
	} else {
		/* The chat existed already, so -chatWithName: never got the chance to hand it our
		 * join information. Do it here, or the repair above would make us stop recognising
		 * our own chat. */
		[self reconcileChatCreationDictionaryWithChat:chat];
	}

	return chat;
}

/*!
 * @brief A chat opened
 *
 * If this chat is our representation, set it up appropriately with our settings.
 */
- (void)chatDidOpen:(NSNotification *)notification
{
	AIChat *chat = [notification object];

	[self claimChatIfOurs:chat];
}

/*!
 * @brief Claim a chat
 *
 * Has no effect if the chat is not ours.
 *
 * Establishes any defaults we wish for our chats to have. Called when they are created.
 */
- (void)claimChatIfOurs:(AIChat *)chat
{
	if ([self chatIsOurs:chat]) {
		[self reconcileChatCreationDictionaryWithChat:chat];

		/* Push our name down only if we have one of our own; a bookmark still named after the
		 * room ID - or carrying a title it merely adopted, which may since have changed -
		 * would otherwise stamp a stale name back onto a chat that knows better. */
		if ([self hasOwnDisplayName])
			[self pushDisplayName:self.displayName toChat:chat];
		else
			[self adoptDisplayNameFromChat:chat];

		[self setStatusMessage:[NSAttributedString stringWithString:([chat valueForProperty:KEY_TOPIC] ?: @"")] notify:NotifyNow];
	}
}

/*!
 * @brief Can this object be part of a metacontact?
 *
 * Bookmarks cannot join meta contacts.
 */
- (BOOL)canJoinMetaContacts
{
	return NO;
}

/*!
 * @brief Is this chat ours?
 *
 * If the chat's name, account, and creation dictionary matches ours, it should be considered ours.
 */
- (BOOL)chatIsOurs:(AIChat *)chat
{
	if (!chat ||
		chat.account != self.account ||
		![chat.name isEqualToString:[self.account.service normalizeChatName:self.name]])
		return NO;

	/* A missing creation dictionary on either side is not a mismatch, it is a gap. Bookmarks
	 * stored before Adium filled these in have none at all - and those are exactly the ones
	 * still named after the room ID, so insisting on a match would lock them out of the
	 * repair they need. A chat can be without one too: AIChatController only sets it when it
	 * creates the chat itself, never when the protocol brings one in.
	 *
	 * Account and room name identify a room; the dictionary only says how to join it, and
	 * -reconcileChatCreationDictionaryWithChat: fills in whichever side is missing it. */
	if (!chat.chatCreationDictionary || !self.chatCreationDictionary)
		return YES;

	return [chat.chatCreationDictionary isEqualToDictionary:self.chatCreationDictionary];
}

/*!
 * @brief Make us and our chat agree on how the room is joined
 *
 * Whichever side knows hands it to the other. The chat's dictionary is the better source - it
 * came from the protocol - so ours is only written when we had none, which is the case where
 * the bookmark could not be joined at all.
 */
- (void)reconcileChatCreationDictionaryWithChat:(AIChat *)chat
{
	if (!chat)
		return;

	if (!self.chatCreationDictionary && chat.chatCreationDictionary) {
		AILogWithSignature(@"%@ takes the join information from its open chat", self.logDescription);
		[chatCreationDictionary release];
		chatCreationDictionary = [chat.chatCreationDictionary copy];
		[adium.contactController saveContactList];

	} else if (self.chatCreationDictionary && !chat.chatCreationDictionary) {
		chat.chatCreationDictionary = self.chatCreationDictionary;
	}
}

#pragma mark -
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath isEqualToString:@"isOnline"] && object == self.account) {
		// If an account is just initially signing on, a -setOnline:notify:silently will still broadcast an event for the contact.
		// The initial delay an account (usually) sets is done after they're set as online, so these bookmarks would always fire.
		// Thus, we have to use the secondary, silent notification so that the online gets propogated without the events.
		[self setOnline:self.account.online notify:NotifyLater silently:YES];
		[self notifyOfChangedPropertiesSilently:YES];
		
		if (self.account.online && [[self preferenceForKey:KEY_AUTO_JOIN group:GROUP_LIST_BOOKMARK] boolValue]) {
			[self openChatWithoutActivating];
		}
	}
}

- (NSSet *)updateChat:(AIChat *)inChat keys:(NSSet *)inModifiedKeys silent:(BOOL)silent
{
	if ([self chatIsOurs:inChat]) {

		[self reconcileChatCreationDictionaryWithChat:inChat];

		/* The readable title often arrives well after the chat does - with WhatsApp it can
		 * take until the participant list turns up. Heal a bookmark still named after the
		 * room ID whenever it does. (Key as set by -[AIChat setDisplayName:].) */
		if (!inModifiedKeys || [inModifiedKeys containsObject:@"Display Name"]) {
			[self adoptDisplayNameFromChat:inChat];
		}

		if ([inModifiedKeys containsObject:KEY_TOPIC]) {
			[self setStatusMessage:[NSAttributedString stringWithString:([inChat valueForProperty:KEY_TOPIC] ?: @"")] notify:NotifyNow];
		}
	
		if ([inModifiedKeys containsObject:KEY_UNVIEWED_CONTENT] || [inModifiedKeys containsObject:KEY_UNVIEWED_MENTION]) {
			[self _updateUnreadMessagesStatusForChat:inChat];
		}
	}
	
	return nil;
}

- (void)_updateUnreadMessagesStatusForChat:(AIChat *)inChat
{
	NSString *statusMessage = nil;
	
	if (inChat.unviewedMentionCount) {
		// We contain mentions; display both this and the content count.
		if (inChat.unviewedMentionCount > 1) {
			statusMessage = [NSString stringWithFormat:AILocalizedString(@"%lu mentions, %lu messages", "Status message for a bookmark (>1 mention, >1 messages)"),
							 (unsigned long)inChat.unviewedMentionCount, (unsigned long)inChat.unviewedContentCount];
		} else if (inChat.unviewedContentCount > 1) {
			statusMessage = [NSString stringWithFormat:AILocalizedString(@"1 mention, %lu messages", "Status message for a bookmark (1 mention, >1 messages)"),
							 (unsigned long)inChat.unviewedContentCount];
		} else {
			statusMessage = AILocalizedString(@"1 mention, 1 message", "Status message for a bookmark (1 mention, 1 message)");
		}
	} else if (inChat.unviewedContentCount) {
		// We don't contain mentions; display the content count.
		if (inChat.unviewedContentCount > 1) {
			statusMessage = [NSString stringWithFormat:AILocalizedString(@"%lu messages", "Status message for a bookmark (>1 messages)"),
							 (unsigned long)inChat.unviewedContentCount];
		} else {
			statusMessage = AILocalizedString(@"1 message", "Status message for a bookmark (1 message)");
		}
	}
	
	[self setValue:statusMessage forProperty:KEY_UNREAD_STATUS notify:NotifyNow];
}

#pragma mark -
- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@:%p %@ - %@ on %@ in %@>",NSStringFromClass([self class]), self, self.formattedUID, [self chatCreationDictionary], self.account, self.remoteGroups];
}

- (NSString *)logDescription
{
	/* The account's UID is the user's own phone number on WhatsApp, so that gets shortened
	 * as well - it only needs to tell two accounts of the same service apart. */
	return [NSString stringWithFormat:@"<%@:%p %@ on %@ %@>",
			NSStringFromClass([self class]), self,
			AIRedactedRoomID(self.name),
			self.account.service.serviceID, AIRedactedRoomID(self.account.UID)];
}

@end
