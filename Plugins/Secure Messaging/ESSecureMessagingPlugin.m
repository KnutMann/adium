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

#import "ESSecureMessagingPlugin.h"
#import "AdiumOTREncryption.h"
#import <AdiumLibpurple/AIOMEMOController.h>
#import <AdiumLibpurple/adiumPurpleOMEMO.h>

#import <Adium/AIChatControllerProtocol.h>
#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIMenuControllerProtocol.h>
#import <Adium/AIToolbarControllerProtocol.h>

#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIToolbarUtilities.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/MVMenuButton.h>
#import <AIUtilities/AIStringAdditions.h>
#import <Adium/AIAccount.h>
#import <Adium/AIChat.h>
#import <Adium/AIListContact.h>

#define	TITLE_MAKE_SECURE		AILocalizedString(@"Initiate Encrypted OTR Chat",nil)
#define	TITLE_MAKE_INSECURE		AILocalizedString(@"Cancel Encrypted Chat",nil)
#define TITLE_SHOW_DETAILS		[AILocalizedString(@"Show Details",nil) stringByAppendingEllipsis]
#define TITLE_VERIFY			[AILocalizedString(@"Verify",nil) stringByAppendingEllipsis]
#define	TITLE_ENCRYPTION_OPTIONS AILocalizedString(@"Encryption Settings",nil)
#define TITLE_ABOUT_ENCRYPTION	[AILocalizedString(@"About Encryption",nil) stringByAppendingEllipsis]

#define TITLE_ENCRYPTION		AILocalizedString(@"Encryption",nil)

#define TITLE_OMEMO_ON			AILocalizedString(@"Encrypt with OMEMO",nil)
#define TITLE_OMEMO_OFF			AILocalizedString(@"Stop Encrypting with OMEMO",nil)
#define TITLE_OMEMO_KEYS		AILocalizedString(@"OMEMO Devices",nil)
#define TITLE_OMEMO_OWN_KEY		AILocalizedString(@"This Mac: %@",nil)
#define TITLE_OMEMO_NO_DEVICES	AILocalizedString(@"No devices seen yet",nil)
#define TITLE_OMEMO_WAITING		AILocalizedString(@"Waiting for their keys",nil)

#define CHAT_NOW_SECURE				AILocalizedString(@"Encrypted OTR chat initiated.", nil)
#define CHAT_NOW_SECURE_UNVERIFIED	AILocalizedString(@"Encrypted OTR chat initiated. %@'s identity not verified.", nil)
#define CHAT_NO_LONGER_SECURE		AILocalizedString(@"Ended encrypted OTR chat.", nil)

@interface ESSecureMessagingPlugin ()
- (void)configureMenuItems;
- (void)registerToolbarItem;
- (NSMenu *)_secureMessagingMenu;
- (void)_updateToolbarIconOfChat:(AIChat *)inChat inWindow:(NSWindow *)window;
- (void)_updateToolbarItem:(NSToolbarItem *)item forChat:(AIChat *)chat;
- (void) toolbarDidAddItem:(NSToolbarItem *)item;

- (IBAction)toggleSecureMessaging:(id)sender;
- (void)chatDidBecomeVisible:(NSNotification *)notification;
- (void)dummyAction:(id)sender;
@end

@implementation ESSecureMessagingPlugin

- (void)installPlugin
{
	//Muy imporatante: Set OTR as our encryption method
	[adium.contentController setEncryptor:[[AdiumOTREncryption alloc] init]];

	_secureMessagingMenu = nil;
	lockImage_Locked = [NSImage imageNamed:@"lock-locked" forClass:[self class]];
	lockImage_Unlocked = [NSImage imageNamed:@"lock-unlocked" forClass:[self class]];

	[self registerToolbarItem];
	[self configureMenuItems];

	[adium.chatController registerChatObserver:self];

	/* The padlock has to close by itself once the other side's keys arrive, which happens a
	 * moment after the user asked for encryption rather than at the moment they asked. */
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(omemoReadinessChanged:)
												 name:AIOMEMOReadinessChangedNotification
											   object:nil];
}

/*!
 * @brief A conversation can now encrypt, or can no longer: redraw the padlock
 */
- (void)omemoReadinessChanged:(NSNotification *)notification
{
	AIChat *chat = adium.interfaceController.activeChat;
	if (!chat) return;

	[adium.chatController chatStatusChanged:chat
						 modifiedStatusKeys:[NSSet setWithObject:@"SecurityDetails"]
									 silent:YES];
}

- (void)uninstallPlugin
{
	[adium.chatController unregisterChatObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)configureMenuItems
{
	NSMenu		*menu = [self _secureMessagingMenu];
	
	//Add menu to toolbar item (for text mode)
	menuItem_encryption = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Encryption", nil)
																			   target:self
																			   action:@selector(dummyAction:) 
																		keyEquivalent:@""];
	[menuItem_encryption setSubmenu:menu];
	[menuItem_encryption setTag:AISecureMessagingMenu_Root];

	[adium.menuController addMenuItem:menuItem_encryption
						   toLocation:LOC_Contact_Additions];
	
	menuItem_encryptionContext = [menuItem_encryption copy];

	[adium.menuController addContextualMenuItem:menuItem_encryptionContext
									 toLocation:Context_Contact_ChatAction];
}

- (void)registerToolbarItem
{	
	toolbarItems = [[NSMutableSet alloc] init];

	//Toolbar item registration
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(toolbarWillAddItem:)
												 name:NSToolbarWillAddItemNotification
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(toolbarDidRemoveItem:)
												 name:NSToolbarDidRemoveItemNotification
											   object:nil];

	//Register our toolbar item
	NSToolbarItem	*toolbarItem;
	MVMenuButton	*button;
	button = [[MVMenuButton alloc] initWithFrame:NSMakeRect(0,0,32,32)];
	[button setImage:lockImage_Locked];

    toolbarItem = [AIToolbarUtilities toolbarItemWithIdentifier:@"Encryption"
														  label:TITLE_ENCRYPTION
												   paletteLabel:AILocalizedString(@"Encrypted Messaging",nil)
														toolTip:AILocalizedString(@"Toggle encrypted messaging. Shows a closed lock when secure and an open lock when insecure.",nil)
														 target:self
												settingSelector:@selector(setView:)
													itemContent:button
														 action:@selector(toggleSecureMessaging:)
														   menu:nil];
	[toolbarItem setMinSize:NSMakeSize(32,32)];
	[toolbarItem setMaxSize:NSMakeSize(32,32)];
	[button setToolbarItem:toolbarItem];

	//Register our toolbar item
	[adium.toolbarController registerToolbarItem:toolbarItem forToolbarType:@"MessageWindow"];
}


//After the toolbar has added the item we can set up the submenus
- (void)toolbarWillAddItem:(NSNotification *)notification
{
	NSToolbarItem	*item = [[notification userInfo] objectForKey:@"item"];
	if ([[item itemIdentifier] isEqualToString:@"Encryption"]) {
		[item setEnabled:YES];
		
		//If this is the first item added, start observing for chats becoming visible so we can update the icon
		if ([toolbarItems count] == 0) {
			[[NSNotificationCenter defaultCenter] addObserver:self
										   selector:@selector(chatDidBecomeVisible:)
											   name:@"AIChatDidBecomeVisible"
											 object:nil];
		}
		
		NSMenu		*menu = [self _secureMessagingMenu];
		
		//Add menu to view
		[[item view] setMenu:menu];
		
		//Add menu to toolbar item (for text mode)
		NSMenuItem	*mItem = [[NSMenuItem alloc] init];
		[mItem setSubmenu:menu];
		[mItem setTitle:[menu title]];
		[item setMenuFormRepresentation:mItem];

		[toolbarItems addObject:item];
		
		[self performSelector:@selector(toolbarDidAddItem:)
				   withObject:item
				   afterDelay:0];
	}
}

- (void)toolbarDidAddItem:(NSToolbarItem *)item
{
	/* Only need to take action if we haven't already validated the initial state of this item.
	 * This will only be true when the toolbar is revealed for the first time having been hidden when window opened.
	 */
	if (![validatedItems containsObject:item]) {
		NSEnumerator *enumerator = [[NSApp windows] objectEnumerator];
		NSWindow	 *window;
		NSToolbar	 *thisItemsToolbar = [item toolbar];
		
		//Look at each window to find the toolbar we are in
		while ((window = [enumerator nextObject])) {
			if ([window toolbar] == thisItemsToolbar) break;
		}
		
		if (window) {
			[self _updateToolbarItem:item
							 forChat:[adium.interfaceController activeChatInWindow:window]];
		}
	}
}

- (void)toolbarDidRemoveItem: (NSNotification *)notification
{
	NSToolbarItem	*item = [[notification userInfo] objectForKey:@"item"];
	if ([toolbarItems containsObject:item]) {
		[item setView:nil];
		[toolbarItems removeObject:item];
		[validatedItems removeObject:item];

		if ([toolbarItems count] == 0) {
			[[NSNotificationCenter defaultCenter] removeObserver:self
												  name:@"AIChatDidBecomeVisible"
												object:nil];
		}
	}
}

//A chat became visible in a window.  Update the item with the @"Encryption" identifier to show the IsSecure state for this chat
- (void)chatDidBecomeVisible:(NSNotification *)notification
{
	[self _updateToolbarIconOfChat:[notification object]
						  inWindow:[[notification userInfo] objectForKey:@"NSWindow"]];
}

//When the IsSecure key of a chat changes, update the @"Encryption" item immediately
- (NSSet *)updateChat:(AIChat *)inChat keys:(NSSet *)inModifiedKeys silent:(BOOL)silent
{
    if ([inModifiedKeys containsObject:@"securityDetails"]) {
		[self _updateToolbarIconOfChat:inChat
							  inWindow:[adium.interfaceController windowForChat:inChat]];
		
		/* Add a status message to the chat */
		BOOL		chatIsSecure = [inChat isSecure];
		if (chatIsSecure != [inChat boolValueForProperty:@"secureMessagingLastEncryptedState"]) {
			NSString	*message;
			NSString	*type;

			[inChat setValue:[NSNumber numberWithBool:chatIsSecure]
							 forProperty:@"secureMessagingLastEncryptedState"
							 notify:NotifyNever];

			if (chatIsSecure) {
				if ([inChat encryptionStatus] == EncryptionStatus_Unverified) {
					AIListObject	*listObject = [inChat listObject];
					NSString		*displayName = (listObject ?
													listObject.formattedUID :
													inChat.displayName);

					message = [NSString stringWithFormat:CHAT_NOW_SECURE_UNVERIFIED, displayName];
					type = @"encryptionStartedUnverified";

				} else {
					message = CHAT_NOW_SECURE;
					type = @"encryptionStarted";
				}

			} else {
				message = CHAT_NO_LONGER_SECURE;
				type = @"encryptionEnded";
			}

			if ([inChat isOpen]) {
				[adium.contentController displayEvent:message
												 ofType:type
												 inChat:inChat];
			}
		}
	}

	return nil;
}

- (void)_updateToolbarItem:(NSToolbarItem *)item forChat:(AIChat *)chat
{
	NSImage			*image;

	/* The padlock closes for OMEMO as well as for OTR, but only once we actually hold the keys
	 * to encrypt with. A conversation that has been switched on and is still waiting for the
	 * other side's keys is not yet encrypted, and showing it as though it were would be the one
	 * kind of wrong a padlock must never be. */
	if ([chat isSecure] ||
		([AIOMEMOController isEncryptingChat:chat] && [AIOMEMOController isReadyInChat:chat])) {
		image = lockImage_Locked;
	} else {
		image = lockImage_Unlocked;				
	}
	
	[item setEnabled:([chat supportsSecureMessagingToggling] || [AIOMEMOController isPossibleInChat:chat])];
	[(MVMenuButton *)[item view] setImage:image];
	[validatedItems addObject:item];
}

- (void)_updateToolbarIconOfChat:(AIChat *)chat inWindow:(NSWindow *)window
{
	NSToolbar		*toolbar = [window toolbar];
	NSEnumerator	*enumerator = [[toolbar items] objectEnumerator];
	NSToolbarItem	*item;
	
	while ((item = [enumerator nextObject])) {
		if ([[item itemIdentifier] isEqualToString:@"Encryption"]) {
			[self _updateToolbarItem:item forChat:chat];
			break;
		}
	}	
}

- (IBAction)toggleSecureMessaging:(id)sender
{
	AIChat	*chat = adium.interfaceController.activeChat;

	[chat.account requestSecureMessaging:!chat.isSecure
									inChat:chat];
}

- (IBAction)showDetails:(id)sender
{
	/* Unlike the old panel, the details string is no longer run through a format-string
	 * expansion, so any "%" characters it contains are displayed literally. */
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setAlertStyle:NSAlertStyleInformational];
	[alert setMessageText:AILocalizedString(@"Details",nil)];
	[alert setInformativeText:([[adium.interfaceController.activeChat securityDetails] objectForKey:@"Description"] ?: @"")];
	[alert addButtonWithTitle:AILocalizedString(@"OK",nil)];
	[alert runModal];
}

- (IBAction)verify:(id)sender
{
	AIChat	*chat = adium.interfaceController.activeChat;
	
	[chat.account promptToVerifyEncryptionIdentityInChat:chat];	
}

- (IBAction)showAbout:(id)sender
{
	NSString	*aboutEncryption;
	
	aboutEncryption = adium.interfaceController.activeChat.account.aboutEncryption;
	
	if (aboutEncryption) {
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setAlertStyle:NSAlertStyleInformational];
		[alert setMessageText:AILocalizedString(@"About Encryption",nil)];
		[alert setInformativeText:aboutEncryption];
		[alert addButtonWithTitle:AILocalizedString(@"OK",nil)];
		[alert runModal];
	}
}

- (IBAction)selectedEncryptionPreference:(id)sender
{
	AIListContact	*listContact = adium.interfaceController.activeChat.listObject.parentContact;
	
	[listContact setPreference:[NSNumber numberWithInteger:[sender tag]]
						forKey:KEY_ENCRYPTED_CHAT_PREFERENCE
						 group:GROUP_ENCRYPTION];
}

//Disable the insertion if a text field is not active
#pragma mark OMEMO

/*!
 * @brief Start or stop encrypting this conversation with OMEMO
 */
- (IBAction)toggleOMEMO:(id)sender
{
	AIChat *chat = adium.interfaceController.activeChat;
	if (!chat) return;

	BOOL wasOn = [AIOMEMOController isEncryptingChat:chat];
	[AIOMEMOController setEncrypting:!wasOn inChat:chat];

	[adium.chatController chatStatusChanged:chat
						 modifiedStatusKeys:[NSSet setWithObject:@"SecurityDetails"]
									 silent:YES];
}

/*!
 * @brief Accept or turn down one of the other party's devices
 *
 * A device is either accepted or it is not; there is no third state to pick, because undecided
 * is what it already was before anybody looked.
 */
- (IBAction)toggleOMEMODevice:(id)sender
{
	AIChat *chat = adium.interfaceController.activeChat;
	NSString *fingerprint = [sender representedObject];
	if (!chat || !fingerprint) return;

	[AIOMEMOController setAccepted:([sender state] != NSControlStateValueOn)
					forFingerprint:fingerprint
							inChat:chat];
}

/*!
 * @brief Fill the device submenu as it opens
 *
 * Built each time rather than kept, because a device the other party added a minute ago should
 * be in it, and one they removed should not.
 */
- (void)menuNeedsUpdate:(NSMenu *)menu
{
	[menu removeAllItems];

	AIChat *chat = adium.interfaceController.activeChat;
	if (!chat) return;

	/* Our own fingerprint first. It is the thing the user reads out to the other person, and
	 * putting it anywhere else means hunting for it during a phone call. */
	NSString *own = [AIOMEMOController ownFingerprintForAccount:chat.account];
	if (own) {
		NSMenuItem *mine = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:TITLE_OMEMO_OWN_KEY, own]
													  target:nil
													  action:nil
											   keyEquivalent:@""];
		[mine setTag:AISecureMessagingMenu_OMEMOOwnKey];
		[menu addItem:mine];
		[menu addItem:[NSMenuItem separatorItem]];
	}

	NSDictionary *theirs = [AIOMEMOController fingerprintsInChat:chat];
	if (![theirs count]) {
		NSString *why = [AIOMEMOController isEncryptingChat:chat] ? TITLE_OMEMO_WAITING : TITLE_OMEMO_NO_DEVICES;
		NSMenuItem *nothing = [[NSMenuItem alloc] initWithTitle:why target:nil action:nil keyEquivalent:@""];
		[nothing setEnabled:NO];
		[menu addItem:nothing];
		return;
	}

	for (NSString *fingerprint in [[theirs allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		NSMenuItem *device = [[NSMenuItem alloc] initWithTitle:fingerprint
														target:self
														action:@selector(toggleOMEMODevice:)
												 keyEquivalent:@""];
		[device setTag:AISecureMessagingMenu_OMEMODevice];
		[device setRepresentedObject:fingerprint];
		[device setState:([theirs[fingerprint] integerValue] == 1 ? NSControlStateValueOn
																  : NSControlStateValueOff)];
		[menu addItem:device];
	}
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	AIChat *chat;
	
	if (menuItem == menuItem_encryptionContext) {
		chat = adium.menuController.currentContextMenuChat;
	} else {
		chat = adium.interfaceController.activeChat;
	}

	if (!chat) return NO;

	if ([[[menuItem menu] title] isEqualToString:ENCRYPTION_MENU_TITLE]) {
		/* Options submenu */
		AIEncryptedChatPreference tag = (AIEncryptedChatPreference)[menuItem tag];
		
		AIListContact	*listContact = chat.listObject.parentContact;
		
		AIEncryptedChatPreference userPreference = [[listContact preferenceForKey:KEY_ENCRYPTED_CHAT_PREFERENCE
																			group:GROUP_ENCRYPTION] intValue];
		
		switch (tag) {
			case EncryptedChat_Default:
			{
				if (listContact) {
					//Set the state (checked or unchecked) as appropriate. Default = no pref or the actual 'default' value.
					[menuItem setState:(tag == userPreference || ![listContact preferenceForKey:KEY_ENCRYPTED_CHAT_PREFERENCE
																						  group:GROUP_ENCRYPTION])];
				}
				return YES;
				break;
			}
			case EncryptedChat_Never:
			case EncryptedChat_Manually:
			case EncryptedChat_Automatically:
			case EncryptedChat_RejectUnencryptedMessages:
			{
				if (listContact) {
					//Set the state (checked or unchecked) as appropriate
					[menuItem setState:(tag == userPreference)];
				}
				return YES;
				break;
			}
		}
	} else {
		/* Items on the main menu */
		AISecureMessagingMenuTag tag = (AISecureMessagingMenuTag)[menuItem tag];
		
		switch (tag) {
			case AISecureMessagingMenu_Root:
				return  [chat supportsSecureMessagingToggling];
				break;

			case AISecureMessagingMenu_Toggle:
				// The menu item should indicate what will happen if it is selected.. the opposite of our secure state
				if ([chat isSecure]) {
					[menuItem setTitle:TITLE_MAKE_INSECURE];
				} else {
					[menuItem setTitle:TITLE_MAKE_SECURE];
				
					AIListContact *listContact = chat.listObject.parentContact;
					AIEncryptedChatPreference userPreference = [[listContact preferenceForKey:KEY_ENCRYPTED_CHAT_PREFERENCE
																						group:GROUP_ENCRYPTION] intValue];
					
					// Disable 'Initiate Encrypted OTR Chat' menu item if chat encryption is disabled
					if (userPreference == EncryptedChat_Never) {
                    	return NO;
                    }
				}

				return YES;
				break;
				
			case AISecureMessagingMenu_ShowDetails:
			case AISecureMessagingMenu_Verify:
				//Only enable show details if the chat is secure
				return [chat isSecure];
				break;
				
			case AISecureMessagingMenu_Options:
				//Only enable options if the chat is with a single person 
				return ([chat supportsSecureMessagingToggling] && chat.listObject && !chat.isGroupChat);
				break;
				
			case AISecureMessagingMenu_ShowAbout:
				return [chat supportsSecureMessagingToggling];
				break;

			case AISecureMessagingMenu_OMEMO:
				if (![AIOMEMOController isPossibleInChat:chat]) return NO;

				[menuItem setTitle:([AIOMEMOController isEncryptingChat:chat] ? TITLE_OMEMO_OFF
																			  : TITLE_OMEMO_ON)];
				return YES;
				break;

			case AISecureMessagingMenu_OMEMOKeys:
				return [AIOMEMOController isPossibleInChat:chat];
				break;

			case AISecureMessagingMenu_OMEMOOwnKey:
				//There to be read, not to be chosen
				return NO;
				break;

			case AISecureMessagingMenu_OMEMODevice:
				return YES;
				break;
		}
	}

	return YES;
}

- (NSMenu *)_secureMessagingMenu
{
	if (!_secureMessagingMenu) {
		NSMenuItem	*item;

		_secureMessagingMenu = [[NSMenu alloc] init];
		[_secureMessagingMenu setTitle:TITLE_ENCRYPTION];

		item = [[NSMenuItem alloc] initWithTitle:TITLE_MAKE_SECURE
										   target:self
										   action:@selector(toggleSecureMessaging:)
									keyEquivalent:@""];
		[item setTag:AISecureMessagingMenu_Toggle];
		[_secureMessagingMenu addItem:item];
		
		item = [[NSMenuItem alloc] initWithTitle:TITLE_SHOW_DETAILS
										   target:self
										   action:@selector(showDetails:)
									keyEquivalent:@""];
		[item setTag:AISecureMessagingMenu_ShowDetails];
		[_secureMessagingMenu addItem:item];

		item = [[NSMenuItem alloc] initWithTitle:TITLE_VERIFY
										   target:self
										   action:@selector(verify:)
									keyEquivalent:@""];
		[item setTag:AISecureMessagingMenu_Verify];
		[_secureMessagingMenu addItem:item];
		
		item = [[NSMenuItem alloc] initWithTitle:TITLE_ENCRYPTION_OPTIONS
										   target:nil
										   action:nil
									keyEquivalent:@""];
		[item setTag:AISecureMessagingMenu_Options];
		[item setSubmenu:[adium.contentController encryptionMenuNotifyingTarget:self
																	  withDefault:YES]];
		[_secureMessagingMenu addItem:item];		

		[_secureMessagingMenu addItem:[NSMenuItem separatorItem]];

		item = [[NSMenuItem alloc] initWithTitle:TITLE_OMEMO_ON
										  target:self
										  action:@selector(toggleOMEMO:)
								   keyEquivalent:@""];
		[item setTag:AISecureMessagingMenu_OMEMO];
		[_secureMessagingMenu addItem:item];

		/* The devices go in a submenu built afresh each time it is shown, because which devices
		 * somebody has is not a thing that stays still. */
		item = [[NSMenuItem alloc] initWithTitle:TITLE_OMEMO_KEYS
										  target:nil
										  action:nil
								   keyEquivalent:@""];
		[item setTag:AISecureMessagingMenu_OMEMOKeys];
		[item setSubmenu:[[NSMenu alloc] init]];
		[[item submenu] setDelegate:(id<NSMenuDelegate>)self];
		[_secureMessagingMenu addItem:item];

		[_secureMessagingMenu addItem:[NSMenuItem separatorItem]];
		item = [[NSMenuItem alloc] initWithTitle:TITLE_ABOUT_ENCRYPTION
										   target:self
										   action:@selector(showAbout:)
									keyEquivalent:@""];
		[item setTag:AISecureMessagingMenu_ShowAbout];
		[_secureMessagingMenu addItem:item];
	}
	
	return [_secureMessagingMenu copy];
}

- (void)dummyAction:(id)sender {};

@end
