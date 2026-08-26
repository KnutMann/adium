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

#import "AIAdvancedInspectorPane.h"
#import "AINewGroupWindowController.h"
#import <AIUtilities/AIParagraphStyleAdditions.h>
#import <Adium/AIListObject.h>
#import <Adium/AIListContact.h>
#import <Adium/AIChat.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <AIUtilities/AIArrayAdditions.h>
#import <Adium/AIAccount.h>
#import <Adium/AIService.h>
#import <Adium/AIListGroup.h>
#import <Adium/AIListBookmark.h>
#import <Adium/AILocalizationTextField.h>
#import <Adium/AIMetaContact.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIContentControllerProtocol.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIPopUpButtonAdditions.h>
#import <AIUtilities/AIStringFormatter.h>
#import <AIUtilities/AIStringAdditions.h>

#import <Adium/AIAccountMenu.h>
#import <Adium/AIContactMenu.h>
#import <AIUtilities/AIBundleAdditions.h>

#define ADVANCED_NIB_NAME (@"AIAdvancedInspectorPane")

@interface AIAdvancedInspectorPane()
- (void)reloadPopup;
- (void)reloadGroups;
- (AIListBookmark *)localGroupingBookmark;
- (void)configureControlDimming;
- (void)addNewGroup:(id)sender;
- (void)removeGroup;
- (void)newGroupControllerDidEnd:(NSNotification *)notification;
@end

@implementation AIAdvancedInspectorPane

- (id) init
{
	self = [super init];
	if (self != nil) {
		[NSBundle ai_loadNibNamed:[self nibName] owner:self];
		/* The loader hands every top level object one reference that belongs to nobody
		 * (see AIBundleAdditions.h); the strong ivar holds its own, so the stray one is
		 * given up here, once. */
		if (inspectorContentView) CFRelease((__bridge CFTypeRef)inspectorContentView);

		//The xib is monolingual (English) and uses plain controls; set all visible strings from code
		[label_account setStringValue:AILocalizedString(@"Account:", "Label beside the account popup in the Advanced tab of the Get Info window")];
		[label_contact setStringValue:AILocalizedString(@"Contact:", "Label beside the contact popup in the Advanced tab of the Get Info window")];
		[label_encryption setStringValue:AILocalizedString(@"Encryption:", "Label beside the encryption preference popup in the Advanced tab of the Get Info window")];
		[label_visibility setStringValue:AILocalizedString(@"Visibility:", "Label beside the 'Always show this contact' checkbox in the Advanced tab of the Get Info window")];
		[label_bookmark setStringValue:AILocalizedString(@"Bookmark:", "Label beside the 'Automatically join on connect' checkbox in the Advanced tab of the Get Info window")];
		[checkBox_alwaysShow setTitle:AILocalizedString(@"Always show this contact", nil)];
		[checkBox_autoJoin setTitle:AILocalizedString(@"Automatically join on connect", nil)];

		//Load Encryption menus
		[popUp_encryption setMenu:[adium.contentController encryptionMenuNotifyingTarget:self withDefault:YES]];
		[[popUp_encryption menu] setAutoenablesItems:NO];
		
		//Observe contact list changes
		[[NSNotificationCenter defaultCenter] addObserver:self
								   selector:@selector(reloadPopup)
									   name:Contact_ListChanged
									 object:nil];	
		//Observe account changes
		[[NSNotificationCenter defaultCenter] addObserver:self
								   selector:@selector(reloadPopup)
									   name:Account_ListChanged
									 object:nil];

		accountMenu = [AIAccountMenu accountMenuWithDelegate:self
												 submenuType:AIAccountNoSubmenu
											  showTitleVerbs:NO];
	}
	
	return self;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}


-(NSString *)nibName
{
	return ADVANCED_NIB_NAME;
}

-(NSView *)inspectorContentView
{
	return inspectorContentView;
}

/*!
 * @brief The displayed object if its grouping is purely local, i.e. if it is a bookmark
 *
 * A bookmark is not on any server, so it has no remote groups and this pane's account/contact
 * popups have nothing to choose between: the only groups it has are the local ones in -groups.
 *
 * Deliberately a class test and not -existsServerside, which looks like the same question but
 * is not: AIMetaContact answers NO to it as well, and metacontacts are edited here exactly as
 * before, through the popups and their contained contacts' remote groups.
 */
- (AIListBookmark *)localGroupingBookmark
{
	return ([displayedObject isKindOfClass:[AIListBookmark class]] ? (AIListBookmark *)displayedObject : nil);
}

/*!
 * @brief Take a fresh, ordered snapshot of the groups to show and redisplay the table
 *
 * Every row index the table hands back is an index into displayedGroups, so the group shown
 * in a row and the group acted on for that row are guaranteed to be the same one.
 */
- (void)reloadGroups
{
	AIListBookmark	*bookmark = [self localGroupingBookmark];
	NSSet			*groups = (bookmark ? bookmark.groups : currentSelectedContact.remoteGroups);

	displayedGroups = [groups.allObjects sortedArrayUsingSelector:@selector(compare:)];

	[tableView_groups reloadData];
	[self configureControlDimming];
}

- (void)configureControlDimming
{
	/* The + and - buttons act through the selected account, which is meaningless for a
	 * bookmark: + would write a contact named "Bookmark:<chat>" into the real serverside
	 * contact list. A bookmark's groups are shown here, but changed in the contact list -
	 * by dragging it, or by "Remove Contact", which asks before it acts. */
	BOOL editable = ([self localGroupingBookmark] == nil);

	[button_addOrRemoveGroup setEnabled:(editable && [tableView_groups numberOfSelectedRows] > 0) forSegment:1];
}

-(void)updateForListObject:(AIListObject *)inObject
{
	if (displayedObject != inObject) {
		displayedObject = ([inObject isKindOfClass:[AIListContact class]] ?
						   [(AIListContact *)inObject parentContact] :
						   inObject);

		//Rebuild the account and contacts lists
		[self reloadPopup];
	}
	
	if(![inObject isKindOfClass:[AIListContact class]]) {
		[popUp_encryption selectItemWithTag:EncryptedChat_Default];
	} else {
		[popUp_encryption selectItemWithTag:((AIListContact *)inObject).encryptedChatPreferences];
	}
	
	[checkBox_alwaysShow setEnabled:![inObject isKindOfClass:[AIListGroup class]]];
	[checkBox_alwaysShow setState:inObject.alwaysVisible];
	
	[checkBox_autoJoin setEnabled:[inObject isKindOfClass:[AIListBookmark class]]];
	[checkBox_autoJoin setState:[[inObject preferenceForKey:KEY_AUTO_JOIN group:GROUP_LIST_BOOKMARK] boolValue]];
	
	/* Groups have no account or contact to pick, and a bookmark has no choice to offer: it
	 * belongs to exactly one account and is its own only contact. */
	BOOL canPickAccountAndContact = (![inObject isKindOfClass:[AIListGroup class]] &&
									 ![inObject isKindOfClass:[AIListBookmark class]]);

	[popUp_accounts setEnabled:canPickAccountAndContact];
	[popUp_contact setEnabled:canPickAccountAndContact];
	[button_addOrRemoveGroup setEnabled:canPickAccountAndContact forSegment:0];
}

#pragma mark Preference callbacks

- (IBAction)selectedEncryptionPreference:(id)sender
{
	[displayedObject setPreference:[NSNumber numberWithInteger:[sender tag]] 
							forKey:KEY_ENCRYPTED_CHAT_PREFERENCE 
							group:GROUP_ENCRYPTION];
}

- (IBAction)setVisible:(id)sender
{
	[displayedObject setAlwaysVisible:[checkBox_alwaysShow state]];
}

- (IBAction)setAutoJoin:(id)sender
{
	[displayedObject setPreference:[NSNumber numberWithBool:[sender state]] 
							forKey:KEY_AUTO_JOIN
							 group:GROUP_LIST_BOOKMARK];
}

#pragma mark Menus
-(void)reloadPopup
{	
	if (switchingContacts)
		return;
	
	[accountMenu rebuildMenu];
	
	NSMenu *groupMenu = [adium.contactController groupMenuWithTarget:self];
	
	[groupMenu addItem:[NSMenuItem separatorItem]];
	
	[groupMenu addItemWithTitle:[AILocalizedString(@"New Group", nil) stringByAppendingEllipsis]
						 target:self
						 action:@selector(addNewGroup:)
				  keyEquivalent:@""];
	
	[button_addOrRemoveGroup setMenu:groupMenu];
	[button_addOrRemoveGroup setMenuIndicatorShown:YES forSegment:0];
	
	[self configureControlDimming];
}

- (void)accountMenu:(AIAccountMenu *)inAccountMenu didSelectAccount:(AIAccount *)inAccount
{
	currentSelectedAccount = inAccount;
	
	if (!contactMenu) {
		// Instantiate here so we don't end up creating a massive menu for all contacts.
		contactMenu = [AIContactMenu contactMenuWithDelegate:self
										 forContactsInObject:displayedObject];
	} else {
		[contactMenu setContainingObject:displayedObject];
	}
}

- (BOOL)accountMenu:(AIAccountMenu *)inAccountMenu shouldIncludeAccount:(AIAccount *)inAccount
{
	if (!inAccount.online) {
		return NO;
	}
	
	if ([displayedObject isKindOfClass:[AIMetaContact class]]) {
		NSArray *services = [((AIMetaContact *)displayedObject).uniqueContainedObjects valueForKeyPath:@"service.serviceClass"];
		return [services containsObject:inAccount.service.serviceClass];
	} else 	if ([displayedObject isKindOfClass:[AIListContact class]]) {
		return [displayedObject.service.serviceClass isEqualToString:inAccount.service.serviceClass];
	}
	
	return NO;
}

- (void)accountMenu:(AIAccountMenu *)inAccountMenu didRebuildMenuItems:(NSArray *)menuItems
{
	[popUp_accounts setMenu:[inAccountMenu menu]];

	[self accountMenu:inAccountMenu didSelectAccount:([popUp_accounts numberOfItems] ?
													  [[popUp_accounts selectedItem] representedObject] :
													  nil)];
}

- (void)contactMenuDidRebuild:(AIContactMenu *)inContactMenu
{
	[popUp_contact setMenu:inContactMenu.menu];
	
	[self contactMenu:inContactMenu didSelectContact:([popUp_contact numberOfItems] ?
													  [[popUp_contact selectedItem] representedObject] :
													  nil)];
}

- (void)contactMenu:(AIContactMenu *)inContactMenu didSelectContact:(AIListContact *)inContact
{
	// Avoid triggering a full reload when this ends up creating a new contact.
	switchingContacts = YES;

	if ([inContact isKindOfClass:[AIListBookmark class]]) {
		/* A bookmark has no per-account twin to look up. -contactWithService:account:UID:
		 * would not find it - bookmarks are kept in bookmarkDict under a different key - and
		 * would silently create an ordinary contact carrying the bookmark's "Bookmark:<chat>"
		 * UID: an object that is on no server, cannot be one, and would be written to one the
		 * moment somebody used the + button on it. */
		currentSelectedContact = inContact;
	} else {
		currentSelectedContact = [adium.contactController contactWithService:inContact.service
																	account:currentSelectedAccount
																		UID:inContact.UID];
	}

	switchingContacts = NO;

	// Update the groups.
	[self reloadGroups];
}

- (BOOL)contactMenu:(AIContactMenu *)inContactMenu shouldIncludeContact:(AIListContact *)inContact
{
	AIAccount *selectedAccount = currentSelectedAccount;
	
	// Include this contact if it's the same as the selected account.
	return [selectedAccount.service.serviceClass isEqualToString:inContact.service.serviceClass];
}

- (NSControlSize)controlSizeForAccountMenu:(AIAccountMenu *)inAccountMenu
{
	return NSControlSizeSmall;
}

#pragma mark Group control
- (void)addNewGroup:(id)sender
{
	AINewGroupWindowController *newGroupController = [[AINewGroupWindowController alloc] init];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(newGroupControllerDidEnd:)
												 name:@"NewGroupWindowControllerDidEnd"
											   object:newGroupController.window];
	
	[newGroupController showOnWindow:inspectorContentView.window];
}

- (void)removeGroup
{
	/* Also reached by the delete key, which no dimming can switch off. */
	if ([self localGroupingBookmark])
		return;

	for (AIListGroup *group in [displayedGroups objectsAtIndexes:tableView_groups.selectedRowIndexes]) {
		[currentSelectedContact removeFromGroup:group];
	}

	[tableView_groups deselectAll:nil];
	[self reloadGroups];
}

- (void)newGroupControllerDidEnd:(NSNotification *)notification
{
	NSParameterAssert([notification.object isKindOfClass:[NSWindow class]]);
	NSParameterAssert([((NSWindow *)notification.object).windowController isKindOfClass:[AINewGroupWindowController class]]);
	
	AINewGroupWindowController *windowController = ((NSWindow *)notification.object).windowController;
	
	if (windowController.group) {
		[currentSelectedAccount addContact:currentSelectedContact toGroup:windowController.group];

		[tableView_groups deselectAll:nil];
		[self reloadGroups];
	}
	
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:@"NewGroupWindowControllerDidEnd"
												  object:notification.object];
}

- (void)selectGroup:(id)sender
{
	AIListGroup *group = [sender representedObject];
	
	[currentSelectedAccount addContact:currentSelectedContact toGroup:group];

	[tableView_groups deselectAll:nil];
	[self reloadGroups];
}

- (void)addOrRemoveGroup:(id)sender
{
	NSInteger selectedSegment = [sender selectedSegment];
	
	switch (selectedSegment) {
		case 0:
			[sender showMenuForSegment:selectedSegment];
			break;
		case 1:
			[self removeGroup];
			break;
	}
}

#pragma mark Accounts Table View Data Sources
/*!
 * @brief Number of table view rows
 */
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return displayedGroups.count;
}

/*!
 * @brief Table view set object value
 */
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString		*identifier = [tableColumn identifier];
	
	if ([identifier isEqualToString:@"group"]) {
		return ((AIListGroup *)[displayedGroups objectAtIndex:row]).displayName;
	}
	
	return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self configureControlDimming];
}

- (void)tableViewDeleteSelectedRows:(NSTableView *)tableView
{
	[self removeGroup];
}

@end
