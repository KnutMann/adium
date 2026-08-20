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

#import "AIPrivacyPreferences.h"
#import <Adium/AISettingsFormView.h>
#import <Adium/AIAccountMenu.h>
#import <Adium/AIAccount.h>
#import <Adium/AIListContact.h>
#import <Adium/AIListGroup.h>
#import <Adium/AIMetaContact.h>
#import <Adium/AIService.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <AIUtilities/AICompletingTextField.h>
#import <AIUtilities/AIImageTextCell.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIPopUpButtonAdditions.h>

#define PRIVACY_TABLE_ROW_HEIGHT	20.0f

/*!
 * The privacy settings, ported from RAFBlockEditorWindowController's window into
 * a settings pane the way the 1.6 line did it. The behaviour is the window's:
 * one account or all of them, four privacy levels, and for the two levels that
 * carry a user list, the list with add, remove and drag and drop from the
 * contact list. The window resized itself to show or hide that list; a pane
 * rebuilds its form instead.
 */
@interface AIPrivacyPreferences ()
- (void)holdView:(NSView *)aView;
- (void)populateForm:(AISettingsFormView *)form;
- (void)rebuildFormIfNeeded;
- (AISettingsFormView *)settingsForm;
- (AIAccount<AIAccount_Privacy> *)selectedAccount;
- (NSArray *)includedAccounts;
- (AIPrivacyOption)selectedPrivacyOption;
- (void)selectPrivacyOption:(AIPrivacyOption)privacyOption;
- (void)applyPrivacyOptionAndReloadList:(BOOL)apply;
- (void)reloadListContents;
- (void)updateTableHeight;
- (void)updateRemoveButton;
- (void)addObject:(AIListContact *)inContact;
- (void)addListObjectToList:(AIListObject *)listObject;
- (void)privacySettingsChangedExternally:(NSNotification *)inNotification;
@end

@implementation AIPrivacyPreferences

#pragma mark Pane properties

- (AIPreferenceCategory)category{
	return AIPref_Advanced;
}
- (NSString *)paneIdentifier{
	return @"Privacy";
}
- (NSString *)label{
	return AILocalizedString(@"Privacy", nil);
}
- (NSImage *)image{
	return [NSImage imageNamed:@"msg-block-contact"];
}

#pragma mark View

/*!
 * @brief Our view: built in code, arranged by the settings form
 *
 * No nib anywhere: every control is created here, then stacked by the form.
 * Mirrors the shape of -[ESOTRPreferences view].
 */
- (NSView *)view
{
	if (!view) {
		listContents = [[NSMutableArray alloc] init];

		popUp_accounts = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
		[popUp_accounts sizeToFit];

		popUp_privacyLevel = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
		{
			NSMenu *levels = [[[NSMenu alloc] init] autorelease];
			struct { NSString *title; AIPrivacyOption option; } entries[] = {
				{ AILocalizedString(@"Allow anyone", nil),								AIPrivacyOptionAllowAll },
				{ AILocalizedString(@"Allow only contacts on my contact list", nil),	AIPrivacyOptionAllowContactList },
				{ AILocalizedString(@"Allow only certain contacts", nil),				AIPrivacyOptionAllowUsers },
				{ AILocalizedString(@"Block certain contacts", nil),					AIPrivacyOptionDenyUsers },
			};
			for (size_t i = 0; i < sizeof(entries) / sizeof(entries[0]); i++) {
				NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:entries[i].title
															  action:@selector(privacyLevelChanged:)
													   keyEquivalent:@""];
				[item setTarget:self];
				[item setTag:entries[i].option];
				[levels addItem:item];
				[item release];
			}
			[popUp_privacyLevel setMenu:levels];
			[popUp_privacyLevel sizeToFit];
		}

		//The list, cell based like every other table here
		table = [[NSTableView alloc] initWithFrame:NSZeroRect];
		{
			NSTableColumn *iconColumn = [[[NSTableColumn alloc] initWithIdentifier:@"icon"] autorelease];
			[iconColumn setDataCell:[[[NSImageCell alloc] init] autorelease]];
			[iconColumn setWidth:(PRIVACY_TABLE_ROW_HEIGHT - 4.0f)];
			[table addTableColumn:iconColumn];

			NSTableColumn *contactColumn = [[[NSTableColumn alloc] initWithIdentifier:@"contact"] autorelease];
			[[contactColumn headerCell] setStringValue:AILocalizedString(@"Contact","Title of column containing user IDs of blocked contacts")];
			[table addTableColumn:contactColumn];

			accountColumn = [[NSTableColumn alloc] initWithIdentifier:@"account"];
			[[accountColumn headerCell] setStringValue:AILocalizedString(@"Account","Title of column containing blocking accounts")];
			[table addTableColumn:accountColumn];

			[table setHeaderView:nil];
			[table setRowHeight:PRIVACY_TABLE_ROW_HEIGHT];
			[table setUsesAlternatingRowBackgroundColors:YES];
			[table setAllowsMultipleSelection:YES];
			[table setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
			[table setDataSource:self];
			[table setDelegate:self];
			[table registerForDraggedTypes:[NSArray arrayWithObjects:@"AIListObject", @"AIListObjectUniqueIDs", nil]];
		}

		scrollView_table = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 3 * PRIVACY_TABLE_ROW_HEIGHT)];
		[scrollView_table setDocumentView:table];
		[scrollView_table setBorderType:NSNoBorder];
		[scrollView_table setDrawsBackground:NO];
		[scrollView_table setHasVerticalScroller:NO];
		[scrollView_table setHasHorizontalScroller:NO];
		[scrollView_table setVerticalScrollElasticity:NSScrollElasticityNone];
		[scrollView_table setHorizontalScrollElasticity:NSScrollElasticityNone];
		[table setAutoresizingMask:NSViewWidthSizable];

		button_add = [[AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Add","Add button for Privacy Settings")
													   target:self
													   action:@selector(addContact:)] retain];
		button_remove = [[AISettingsFormView pushButtonWithTitle:AILocalizedString(@"Remove", nil)
														  target:self
														  action:@selector(removeSelection:)] retain];

		accountMenu = [[AIAccountMenu accountMenuWithDelegate:self
												  submenuType:AIAccountNoSubmenu
											   showTitleVerbs:NO] retain];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(privacySettingsChangedExternally:)
													 name:@"AIPrivacySettingsChangedOutsideOfPrivacyWindow"
												   object:nil];
		[[AIContactObserverManager sharedManager] registerListObjectObserver:self];
		observersRegistered = YES;

		AISettingsFormView *form = [[AISettingsFormView alloc] initWithWidth:0.0f];
		[self populateForm:form];
		view = form;

		[form layoutForWidth:NSWidth([form frame])];
		if (![self resizable]) [view setAutoresizingMask:(NSViewMaxYMargin)];
	}

	return view;
}

- (AISettingsFormView *)settingsForm
{
	return ([view isKindOfClass:[AISettingsFormView class]] ? (AISettingsFormView *)view : nil);
}

- (void)holdView:(NSView *)aView
{
	if (!aView) return;
	if (!hostedViews) hostedViews = [[NSMutableArray alloc] init];
	if (![hostedViews containsObject:aView]) [hostedViews addObject:aView];
}

/*!
 * @brief Fill an empty form with the privacy card
 */
- (void)populateForm:(AISettingsFormView *)form
{
	BOOL	hasAccounts = ([[self includedAccounts] count] > 0);
	AIPrivacyOption option = [self selectedPrivacyOption];
	BOOL	hasList = (hasAccounts &&
					   (option == AIPrivacyOptionAllowUsers || option == AIPrivacyOptionDenyUsers));

	[form addSectionHeader:AILocalizedString(@"Privacy", nil)];

	if (hasAccounts) {
		[form addRowWithLabel:AILocalizedString(@"Account", nil)
				  popUpButton:popUp_accounts
			  accessoryButton:nil];
		[self holdView:popUp_accounts];

		[form addRowWithLabel:AILocalizedString(@"Privacy level", nil)
				  popUpButton:popUp_privacyLevel
			  accessoryButton:nil];
		[self holdView:popUp_privacyLevel];
	} else {
		/* The menu item that opens this pane is disabled in the same situation; whoever
		 * arrives here anyway - through Show All - learns why there is nothing to set. */
		[form addEmptyStateRow:AILocalizedString(@"No Connected Accounts", "Shown in the Privacy preferences when no online account supports privacy lists")];
		[form addFootnote:AILocalizedString(@"Privacy lists can only be changed while an account which supports them is connected.", "Footnote in the Privacy preferences when no online account supports privacy lists")];
	}

	if (hasList) {
		[self updateTableHeight];
		[form addEdgeToEdgeRow:scrollView_table];
		[self holdView:scrollView_table];

		[form addAccessoryView:[AISettingsFormView rowOfViews:[NSArray arrayWithObjects:
															   button_add, button_remove, nil]]];
		[self holdView:button_add];
		[self holdView:button_remove];
		[self updateRemoveButton];
	}

	builtWithAccounts = hasAccounts;
	builtWithList = hasList;
}

/*!
 * @brief Build the form again if it would come out differently now
 *
 * Where the window animated its frame to show or hide the list, the pane's shape
 * is decided at build time: account or none, list or none.
 */
- (void)rebuildFormIfNeeded
{
	AISettingsFormView *form = [self settingsForm];
	if (!form) return;

	BOOL	hasAccounts = ([[self includedAccounts] count] > 0);
	AIPrivacyOption option = [self selectedPrivacyOption];
	BOOL	hasList = (hasAccounts &&
					   (option == AIPrivacyOptionAllowUsers || option == AIPrivacyOptionDenyUsers));

	if (hasAccounts == builtWithAccounts && hasList == builtWithList) return;

	/* Out of the cards before the cards go: everything hosted is retained by us
	 * as well, so this hands the controls back rather than freeing them. */
	for (NSView *hosted in hostedViews)
		[hosted removeFromSuperview];

	[form removeAllSections];
	[self populateForm:form];
	[form layoutForWidth:NSWidth([form frame])];
}

/*!
 * @brief Perform actions before the view closes
 */
- (void)viewWillClose
{
	[self tearDown];
}

- (void)tearDown
{
	if (observersRegistered) {
		[[AIContactObserverManager sharedManager] unregisterListObjectObserver:self];
		[[NSNotificationCenter defaultCenter] removeObserver:self];
		observersRegistered = NO;
	}

	[table setDataSource:nil];
	[table setDelegate:nil];

	[accountMenu release]; accountMenu = nil;
	[listContents release]; listContents = nil;
	[hostedViews release]; hostedViews = nil;
	[popUp_accounts release]; popUp_accounts = nil;
	[popUp_privacyLevel release]; popUp_privacyLevel = nil;
	[table release]; table = nil;
	[scrollView_table release]; scrollView_table = nil;
	[accountColumn release]; accountColumn = nil;
	[button_add release]; button_add = nil;
	[button_remove release]; button_remove = nil;
}

- (void)dealloc
{
	[self tearDown];
	[super dealloc];
}

#pragma mark Accounts

/*!
 * @brief Every account the menu offers, i.e. online and able to keep privacy lists
 */
- (NSArray *)includedAccounts
{
	NSMutableArray *accounts = [NSMutableArray array];
	for (AIAccount *account in adium.accountController.accounts) {
		if (account.online && [account conformsToProtocol:@protocol(AIAccount_Privacy)])
			[accounts addObject:account];
	}
	return accounts;
}

/*!
 * @brief The selected account, or nil when "All" is
 */
- (AIAccount<AIAccount_Privacy> *)selectedAccount
{
	return [[popUp_accounts selectedItem] representedObject];
}

- (BOOL)accountMenu:(AIAccountMenu *)inAccountMenu shouldIncludeAccount:(AIAccount *)inAccount
{
	return (inAccount.online && [inAccount conformsToProtocol:@protocol(AIAccount_Privacy)]);
}

//The All item leads the menu once more than one account qualifies
- (NSMenuItem *)accountMenuSpecialMenuItem:(AIAccountMenu *)inAccountMenu
{
	if ([[self includedAccounts] count] > 1) {
		return [[[NSMenuItem alloc] initWithTitle:AILocalizedString(@"All", nil)
										   target:self
										   action:@selector(selectedAllAccountItem:)
									keyEquivalent:@""] autorelease];
	}
	return nil;
}

- (void)accountMenu:(AIAccountMenu *)inAccountMenu didRebuildMenuItems:(NSArray *)menuItems
{
	AIAccount	*previouslySelectedAccount = ([popUp_accounts menu] ?
											  [[popUp_accounts selectedItem] representedObject] : nil);
	NSMenu		*menu = [[NSMenu alloc] init];

	for (NSMenuItem *menuItem in menuItems)
		[menu addItem:menuItem];
	[popUp_accounts setMenu:menu];
	[menu release];

	if (previouslySelectedAccount)
		[popUp_accounts selectItemWithRepresentedObject:previouslySelectedAccount];

	[self accountMenu:inAccountMenu didSelectAccount:[self selectedAccount]];
}

- (void)accountMenu:(AIAccountMenu *)inAccountMenu didSelectAccount:(AIAccount *)inAccount
{
	AIAccount<AIAccount_Privacy> *account = [self selectedAccount];

	if (account) {
		[accountColumn setHidden:YES];
		[self selectPrivacyOption:[account privacyOptions]];

	} else {
		/* All accounts: one shared answer if they agree, and the placeholder entry
		 * when they do not. */
		AIPrivacyOption currentState = AIPrivacyOptionUnknown;
		for (AIAccount<AIAccount_Privacy> *anAccount in [self includedAccounts]) {
			AIPrivacyOption accountState = [anAccount privacyOptions];
			if (currentState == AIPrivacyOptionUnknown) {
				currentState = accountState;
			} else if (accountState != currentState) {
				currentState = AIPrivacyOptionCustom;
			}
		}
		[accountColumn setHidden:NO];
		[self selectPrivacyOption:currentState];
	}
}

- (IBAction)selectedAllAccountItem:(id)sender
{
	[self accountMenu:accountMenu didSelectAccount:nil];
}

#pragma mark Privacy option

- (AIPrivacyOption)selectedPrivacyOption
{
	return (AIPrivacyOption)[[popUp_privacyLevel selectedItem] tag];
}

/*!
 * @brief Show a privacy option, without applying it anywhere
 */
- (void)selectPrivacyOption:(AIPrivacyOption)privacyOption
{
	if (privacyOption == AIPrivacyOptionCustom) {
		if (![popUp_privacyLevel selectItemWithTag:privacyOption]) {
			NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:AILocalizedString(@"(Multiple privacy levels are active)", nil)
															  action:NULL
													   keyEquivalent:@""];
			[menuItem setTag:AIPrivacyOptionCustom];
			[[popUp_privacyLevel menu] addItem:menuItem];
			[menuItem release];

			[popUp_privacyLevel selectItemWithTag:privacyOption];
		}
	} else {
		NSInteger customItemIndex = [popUp_privacyLevel indexOfItemWithTag:AIPrivacyOptionCustom];
		if (customItemIndex != -1)
			[[popUp_privacyLevel menu] removeItemAtIndex:customItemIndex];

		[popUp_privacyLevel selectItemWithTag:privacyOption];
	}

	[self applyPrivacyOptionAndReloadList:NO];
}

- (IBAction)privacyLevelChanged:(id)sender
{
	[self applyPrivacyOptionAndReloadList:YES];
}

/*!
 * @brief Push the chosen option to the account(s) if asked, then mirror their lists
 */
- (void)applyPrivacyOptionAndReloadList:(BOOL)apply
{
	AIPrivacyOption privacyOption = [self selectedPrivacyOption];

	if (apply && privacyOption != AIPrivacyOptionCustom) {
		AIAccount<AIAccount_Privacy> *account = [self selectedAccount];
		if (account) {
			[account setPrivacyOptions:privacyOption];
		} else {
			for (AIAccount<AIAccount_Privacy> *anAccount in [self includedAccounts])
				[anAccount setPrivacyOptions:privacyOption];
		}
	}

	[self reloadListContents];
	[self rebuildFormIfNeeded];
}

/*!
 * @brief Make listContents match the serverside list(s) for the selection
 */
- (void)reloadListContents
{
	AIPrivacyOption privacyOption = [self selectedPrivacyOption];

	[listContents removeAllObjects];
	if (privacyOption == AIPrivacyOptionAllowUsers || privacyOption == AIPrivacyOptionDenyUsers) {
		AIPrivacyType	privacyType = ((privacyOption == AIPrivacyOptionAllowUsers) ?
									   AIPrivacyTypePermit : AIPrivacyTypeDeny);
		AIAccount<AIAccount_Privacy> *account = [self selectedAccount];

		if (account) {
			[listContents addObjectsFromArray:[account listObjectsOnPrivacyList:privacyType]];
		} else {
			for (AIAccount<AIAccount_Privacy> *anAccount in [self includedAccounts])
				[listContents addObjectsFromArray:[anAccount listObjectsOnPrivacyList:privacyType]];
		}
	}

	[table reloadData];
	[self updateTableHeight];
	[self updateRemoveButton];
}

#pragma mark Changing the list

- (void)addObject:(AIListContact *)inContact
{
	if (!inContact) return;

	if (![listContents containsObject:inContact])
		[listContents addObject:inContact];

	[inContact setIsOnPrivacyList:YES
					   updateList:YES
					  privacyType:(([self selectedPrivacyOption] == AIPrivacyOptionAllowUsers) ?
								   AIPrivacyTypePermit : AIPrivacyTypeDeny)];
}

/*!
 * @brief Ask for a contact to add, with completion against the roster
 *
 * The window carried its own sheet nib for this; an alert with a completing
 * field on it asks the same question in less machinery. In the All case the
 * contact is added on every included account, as the window's sheet offered.
 */
- (IBAction)addContact:(id)sender
{
	AICompletingTextField *field = [[[AICompletingTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)] autorelease];
	AIAccount *account = [self selectedAccount];

	[field setCompletingStrings:nil];
	for (AIListContact *contact in adium.contactController.allContacts) {
		if (!account || contact.service == account.service) {
			NSString *UID = contact.UID;
			[field addCompletionString:contact.formattedUID withImpliedCompletion:UID];
			[field addCompletionString:contact.displayName withImpliedCompletion:UID];
			[field addCompletionString:UID];
		}
	}

	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:(([self selectedPrivacyOption] == AIPrivacyOptionAllowUsers) ?
						   AILocalizedString(@"Allow a contact", "Title of the prompt for a contact to add to the allow list") :
						   AILocalizedString(@"Block a contact", "Title of the prompt for a contact to add to the block list"))];
	[alert setInformativeText:AILocalizedString(@"Enter the contact's user name.", nil)];
	[alert addButtonWithTitle:AILocalizedString(@"Add","Add button for Privacy Settings")];
	[alert addButtonWithTitle:AILocalizedString(@"Cancel","Cancel button for Privacy Settings")];
	[alert setAccessoryView:field];
	[[alert window] setInitialFirstResponder:field];

	[alert beginSheetModalForWindow:[view window] completionHandler:^(NSModalResponse returnCode) {
		if (returnCode != NSAlertFirstButtonReturn)
			return;

		id impliedValue = [field impliedValue];
		NSArray *accounts = (account ? [NSArray arrayWithObject:account] : [self includedAccounts]);

		for (AIAccount *anAccount in accounts) {
			if ([impliedValue isKindOfClass:[AIMetaContact class]]) {
				for (AIListContact *containedContact in [(AIMetaContact *)impliedValue listContactsIncludingOfflineAccounts]) {
					if ([containedContact.service.serviceClass isEqualToString:anAccount.service.serviceClass]) {
						[self addObject:[adium.contactController contactWithService:anAccount.service
																			account:anAccount
																				UID:containedContact.UID]];
					}
				}
			} else {
				NSString *UID = nil;
				if ([impliedValue isKindOfClass:[AIListContact class]]) {
					UID = [(AIListContact *)impliedValue UID];
				} else if ([impliedValue isKindOfClass:[NSString class]] && [impliedValue length]) {
					UID = [anAccount.service normalizeUID:impliedValue removeIgnoredCharacters:YES];
				}
				if (UID) {
					[self addObject:[adium.contactController contactWithService:anAccount.service
																		account:anAccount
																			UID:UID]];
				}
			}
		}

		[self reloadListContents];
	}];
}

- (IBAction)removeSelection:(id)sender
{
	NSIndexSet *selectedItems = [table selectedRowIndexes];
	if (![selectedItems count]) return;

	for (NSInteger selection = [selectedItems lastIndex]; selection != NSNotFound; selection = [selectedItems indexLessThanIndex:selection]) {
		AIListContact *contact = [listContents objectAtIndex:selection];
		[contact setIsOnPrivacyList:NO
						 updateList:YES
						privacyType:(([self selectedPrivacyOption] == AIPrivacyOptionAllowUsers) ?
									 AIPrivacyTypePermit : AIPrivacyTypeDeny)];
		[listContents removeObject:contact];
	}

	[table reloadData];
	[table deselectAll:nil];
	[self updateTableHeight];
	[self updateRemoveButton];
}

#pragma mark Outside changes

- (void)privacySettingsChangedExternally:(NSNotification *)inNotification
{
	[self accountMenu:accountMenu didSelectAccount:[self selectedAccount]];
}

- (NSSet *)updateListObject:(AIListObject *)inObject keys:(NSSet *)inModifiedKeys silent:(BOOL)silent
{
	if ([inModifiedKeys containsObject:KEY_IS_BLOCKED])
		[self privacySettingsChangedExternally:nil];

	return nil;
}

#pragma mark Table

- (void)updateTableHeight
{
	if (!scrollView_table) return;

	NSUInteger	rows = MAX([listContents count], (NSUInteger)1);
	CGFloat		height = rows * (PRIVACY_TABLE_ROW_HEIGHT + [table intercellSpacing].height);

	if (fabs(NSHeight([scrollView_table frame]) - height) < 0.5f) return;

	[scrollView_table setFrameSize:NSMakeSize(NSWidth([scrollView_table frame]), height)];
	if ([scrollView_table superview]) [[self settingsForm] noteContentSizeChanged];
}

- (void)updateRemoveButton
{
	[button_remove setEnabled:([table numberOfSelectedRows] > 0)];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	[self updateRemoveButton];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [listContents count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if (rowIndex < 0 || rowIndex >= (NSInteger)[listContents count]) return nil;

	NSString		*identifier = [aTableColumn identifier];
	AIListContact	*contact = [listContents objectAtIndex:rowIndex];

	if ([identifier isEqualToString:@"icon"]) {
		return [contact menuIcon];
	} else if ([identifier isEqualToString:@"contact"]) {
		return contact.formattedUID;
	} else if ([identifier isEqualToString:@"account"]) {
		return contact.account.formattedUID;
	}

	return nil;
}

#pragma mark Dropping contacts onto the list

- (NSDragOperation)tableView:(NSTableView*)tv
				validateDrop:(id <NSDraggingInfo>)info
				 proposedRow:(NSInteger)row
	   proposedDropOperation:(NSTableViewDropOperation)op
{
	[tv setDropRow:row dropOperation:NSTableViewDropAbove];
	return NSDragOperationCopy;
}

- (void)addListObjectToList:(AIListObject *)listObject
{
	if ([listObject isKindOfClass:[AIListGroup class]]) {
		for (AIListObject *containedObject in [(AIListGroup *)listObject uniqueContainedObjects])
			[self addListObjectToList:containedObject];

	} else if ([listObject isKindOfClass:[AIMetaContact class]]) {
		for (AIListObject *containedObject in [(AIMetaContact *)listObject uniqueContainedObjects])
			[self addListObjectToList:containedObject];

	} else if ([listObject isKindOfClass:[AIListContact class]]) {
		if ([(AIListContact *)listObject account].online)
			[self addObject:(AIListContact *)listObject];
	}
}

- (BOOL)tableView:(NSTableView*)tv acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)op
{
	if (![info.draggingPasteboard.types containsObject:@"AIListObjectUniqueIDs"])
		return NO;

	for (NSString *uniqueUID in [info.draggingPasteboard propertyListForType:@"AIListObjectUniqueIDs"])
		[self addListObjectToList:[adium.contactController existingListObjectWithUniqueID:uniqueUID]];

	[self reloadListContents];
	return YES;
}

@end
