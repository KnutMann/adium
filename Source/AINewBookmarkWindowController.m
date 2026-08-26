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
#import "AINewBookmarkWindowController.h"
#import "AINewGroupWindowController.h"
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AIListGroup.h>
#import <Adium/AIListBookmark.h>
#import <Adium/AIContactList.h>
#import <Adium/AIAccount.h>
#import <Adium/AIChat.h>
#import <Adium/AIServiceMenu.h>

#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <AIUtilities/AIPopUpButtonAdditions.h>

#define		ADD_BOOKMARK_NIB		@"AddBookmark"
#define		DEFAULT_GROUP_NAME		AILocalizedString(@"Contacts",nil)

@interface AINewBookmarkWindowController ()
- (id)initWithChat:(AIChat *)inChat notifyingTarget:(id)inTarget;
- (void)buildGroupMenu;
- (AIListGroup *)groupTheChatIsAlreadyIn;
- (void)newGroup:(id)sender;
- (void)newGroupDidEnd:(NSNotification *)inNotification;
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
@end

@implementation AINewBookmarkWindowController

/* The ownership home of every shown window. -showOnWindow: consumes the caller's reference (see
 * the header), so what keeps a shown controller alive is its place in this set; both exits leave
 * it. The same design as ESTextAndButtonsWindowController. */
static NSMutableSet *openNewBookmarkWindows = nil;

- (void)showOnWindow:(NSWindow *)parentWindow
{
	if (!openNewBookmarkWindows) openNewBookmarkWindows = [[NSMutableSet alloc] init];
	[openNewBookmarkWindows addObject:self];

	if(parentWindow) {
	   [parentWindow beginSheet:self.window
	   	   completionHandler:^(NSModalResponse returnCode) {
	   		[self sheetDidEnd:self.window returnCode:returnCode contextInfo:NULL];
	   	}];
	} else {
		[self showWindow:nil];
		[self.window makeKeyAndOrderFront:nil];
	}
}

- (id)initWithChat:(AIChat *)inChat notifyingTarget:(id)inTarget
{
	if ((self = [super initWithWindowNibName:ADD_BOOKMARK_NIB])) {
		chat = inChat;
		target = inTarget;
	}

	return self;
}

/*!
 *	@brief didEnd selector for the sheet created above, dismisses the sheet
 */
-(void)sheetDidEnd:(NSWindow*)sheet returnCode:(NSInteger)returnCode contextInfo:(void*)contextInfo
{
	[sheet orderOut:nil];

	/* Out of the set, but not before this turn of the run loop ends: both exits are reached from
	 * inside AppKit's own close, which goes on addressing this object afterwards. It also makes the
	 * two harmless should they ever both run, which the pair of autoreleases here would not have
	 * been, since that would have given the same reference back twice.
	 */
	CFAutorelease(CFBridgingRetain(self));
	[openNewBookmarkWindows removeObject:self];
}

- (void)windowWillClose:(id)sender
{
	[super windowWillClose:sender];

	/* Out of the set, but not before this turn of the run loop ends: both exits are reached from
	 * inside AppKit's own close, which goes on addressing this object afterwards. It also makes the
	 * two harmless should they ever both run, which the pair of autoreleases here would not have
	 * been, since that would have given the same reference back twice.
	 */
	CFAutorelease(CFBridgingRetain(self));
	[openNewBookmarkWindows removeObject:self];
}

/*!
 * @name windowDidLoad
 * @brief the sheet finished loading, populate the group menu with contactlist's groups
 */
-(void)windowDidLoad
{
	[self buildGroupMenu];
	
	if (chat) {
		/* chat.name is the room ID the protocol works with - for WhatsApp the group JID,
		 * which is no use to anybody reading the contact list. Offer the name the protocol
		 * gave the chat; the user can still type over it. */
		[textField_name setStringValue:(chat.displayName ?: chat.name)];
	}
	
	[label_name setStringValue:AILocalizedString(@"Name:", nil)];
	[label_group setStringValue:AILocalizedString(@"Group:", nil)];
	[button_add setTitle:AILocalizedStringFromTable(@"Add", @"Buttons", nil)];
	[button_cancel setTitle:AILocalizedStringFromTable(@"Cancel", @"Buttons", nil)];
}

/*!
 * @name add
 * @brief User pressed ok on sheet - Calls createBookmarkWithInfo: on the delegate class AIBookmarkController, which creates 
 * a new bookmark with the entered name & moves it to the entered group.
 */
- (IBAction)add:(id)sender
{
	[target createBookmarkForChat:chat
						 withName:[textField_name stringValue]
						  inGroup:[[popUp_group selectedItem] representedObject]];

	[self closeWindow:nil];
}

/*!
 *@brief user pressed cancel on panel -dismisses the sheet
 */
- (IBAction)cancel:(id)sender
{
	[self closeWindow:nil];
}

//Add to Group ---------------------------------------------------------------------------------------------------------
#pragma mark Add to Group
/*!
 * @brief Build the menu of available destination groups
 */
- (void)buildGroupMenu
{
	NSMenu			*menu;
	//Rebuild the menu
	menu = [adium.contactController groupMenuWithTarget:nil];

	//Add a default group name to the menu if there are no groups listed
	if ([menu numberOfItems] == 0) {
		[menu addItemWithTitle:DEFAULT_GROUP_NAME
						target:nil
						action:nil
				 keyEquivalent:@""];
	}
	
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItemWithTitle:[AILocalizedString(@"New Group",nil) stringByAppendingEllipsis]
					target:self
					action:@selector(newGroup:)
			 keyEquivalent:@""];

	[popUp_group setMenu:menu];
	[popUp_group selectItemAtIndex:0];

	/* Index 0 is whichever group happens to sort first, which has nothing to do with this
	 * chat; accepting the sheet without touching the popup then files the entry somewhere the
	 * user has no reason to look. If the room is already represented in the list, offer that
	 * group instead. */
	AIListGroup *group = [self groupTheChatIsAlreadyIn];

	if (group)
		[popUp_group selectItemWithRepresentedObject:group];
}

/*!
 * @brief The group the room is filed under already, if any
 *
 * A bookmark for this chat which is still around (misfiled or simply pre-existing) knows best;
 * failing that, an ordinary contact carrying the room ID is where the user has been keeping
 * this room. Returns nil if neither exists, or if it sits in the root list rather than a group.
 */
- (AIListGroup *)groupTheChatIsAlreadyIn
{
	AIListObject *listObject = [adium.contactController existingBookmarkForChat:chat];

	if (!listObject && chat.name.length) {
		listObject = [adium.contactController existingContactWithService:chat.account.service
																 account:chat.account
																	 UID:chat.name];
	}

	for (AIListObject *containingObject in listObject.groups) {
		/* The root list is an AIListGroup too, but it isn't in the menu and picking it would
		 * only mean "no group at all". */
		if ([containingObject isKindOfClass:[AIListGroup class]] &&
			![containingObject isKindOfClass:[AIContactList class]])
			return (AIListGroup *)containingObject;
	}

	return nil;
}

/*!
 * @brief Prompt the user to add a new group immediately
 */
- (void)newGroup:(id)sender
{
	AINewGroupWindowController *newGroupWindowController = [[AINewGroupWindowController alloc] init];
	
	//Observe for the New Group window to close
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(newGroupDidEnd:) 
												 name:@"NewGroupWindowControllerDidEnd"
											   object:[newGroupWindowController window]];
	
	[newGroupWindowController showOnWindow:[self window]];
}
/*!
 * @name newGroupDidEnd:
 * @brief the New Group sheet has ended, if a new group was created, select it, otherwise
 * select the first group.
 */

- (void)newGroupDidEnd:(NSNotification *)inNotification
{
	NSWindow	*window = [inNotification object];

	if ([[window windowController] isKindOfClass:[AINewGroupWindowController class]]) {
		AIListGroup *group = [(AINewGroupWindowController *)[window windowController] group];
		//Rebuild the group menu
		[self buildGroupMenu];
		
		/* Select the new group if it exists; otherwise select the first group (so we don't still have New Group... selected).
		 * If the user cancelled, group will be nil since the group doesn't exist.
		 */
		if (![popUp_group selectItemWithRepresentedObject:group]) {
			[popUp_group selectItemAtIndex:0];			
		}
		
		[[self window] performSelector:@selector(makeKeyAndOrderFront:)
							withObject:self
							afterDelay:0];
	}

	//Stop observing
	[[NSNotificationCenter defaultCenter] removeObserver:self
										  name:@"NewGroupWindowControllerDidEnd" 
										object:window];
}

@end
