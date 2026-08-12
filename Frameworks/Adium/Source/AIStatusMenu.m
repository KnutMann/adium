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

#import <Adium/AIStatusMenu.h>
#import <Adium/AIStatus.h>
#import <Adium/AIAccount.h>
#import <Adium/AIStatusControllerProtocol.h>
#import <Adium/AIEditStateWindowController.h>
#import <Adium/AIStatusIcons.h>
#import <Adium/AISocialNetworkingStatusMenu.h>
#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIMenuControllerProtocol.h>
#import <AIUtilities/AIArrayAdditions.h>
#import <AIUtilities/AIDataAdditions.h>
#import <AIUtilities/AIEventAdditions.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIStringAdditions.h>

#define STATUS_TITLE_CUSTOM			[AILocalizedString(@"Custom", nil) stringByAppendingEllipsis]
#define STATE_TITLE_MENU_LENGTH		30

@interface AIStatusMenu ()
- (id)initWithDelegate:(id<AIStatusMenuDelegate>)inDelegate;
- (void)stateArrayChanged:(NSNotification *)notification;
- (void)activeStatusStateChanged:(NSNotification *)notification;
- (void)statusIconSetChanged:(NSNotification *)notification;
- (IBAction)selectCustomState:(id)sender;
- (void)selectState:(id)sender;
+ (NSArray *)statusItemsForMenuDisplay;
+ (NSSet *)activeStatusItemsHiddenFromTheMenu;
- (void)addCustomItemsForStatusTypesFrom:(AIStatusType)fromStatusType
									  to:(AIStatusType)toStatusType
					 skippingTheFirstOne:(BOOL)skipFirst;
@end

@implementation AIStatusMenu

+ (id)statusMenuWithDelegate:(id<AIStatusMenuDelegate>)inDelegate
{
	return [[[self alloc] initWithDelegate:inDelegate] autorelease];
}

- (id)initWithDelegate:(id<AIStatusMenuDelegate>)inDelegate
{
	if ((self = [super init])) {
		self.delegate = inDelegate;
		
		NSParameterAssert([delegate respondsToSelector:@selector(statusMenu:didRebuildStatusMenuItems:)]);

		menuItemArray = [[NSMutableArray alloc] init];
		stateMenuItemsAlreadyValidated = [[NSMutableSet alloc] init];

		[self rebuildMenu];

		[[NSNotificationCenter defaultCenter] addObserver:self
									   selector:@selector(stateArrayChanged:)
										   name:AIStatusStateArrayChangedNotification
										 object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
									   selector:@selector(activeStatusStateChanged:)
										   name:AIStatusActiveStateChangedNotification
										 object:nil];
		
		//Update our state menus when the state array or status icon set changes
		[[NSNotificationCenter defaultCenter] addObserver:self
									   selector:@selector(statusIconSetChanged:)
										   name:AIStatusIconSetDidChangeNotification
										 object:nil];
	}
	
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[stateMenuItemsAlreadyValidated release];
	[hiddenActiveStatusItems release];
	[menuItemArray release];

	self.delegate = nil;

	[super dealloc];
}

@synthesize delegate;

/*!
 * @brief The delegate is just too good for the menu items we've created; it will create all of the ones it wants on its own
 */
- (void)delegateWillReplaceAllMenuItems
{
	//Remove the menu items from needing update
	[stateMenuItemsAlreadyValidated removeAllObjects];

	//Clear the array itself
	[menuItemArray removeAllObjects];	
}

/*!
 * @brief The delegate created its own menu items it wants us to track and update
 */
- (void)delegateCreatedMenuItems:(NSArray *)addedMenuItems
{
	//Now add the items we were given
	[menuItemArray addObjectsFromArray:addedMenuItems];
}

- (void)stateArrayChanged:(NSNotification *)notification
{	
	[self rebuildMenu];
}

- (void)activeStatusStateChanged:(NSNotification *)notification
{
	/* +statusItemsForMenuDisplay keeps the status which is set right now in the menu even when its
	 * switch is off - but that is decided while the menu is built, and nothing else rebuilds it for
	 * a status change: an automatic status is set on the accounts by ID (AIAutomaticStatus), which
	 * never touches the status array. Without this the user's own state would carry no checkmark
	 * anywhere and the menu would be silent about where they stand.
	 *
	 * Only that one case rebuilds; every other status change needs nothing but the validation cache
	 * emptied, and rebuilding every menu of Adium each time an account goes online would be dear. */
	NSSet	*nowHiddenAndActive = [AIStatusMenu activeStatusItemsHiddenFromTheMenu];

	if (![nowHiddenAndActive isEqualToSet:hiddenActiveStatusItems]) {
		//-rebuildMenu empties the validation cache and takes down the new set itself
		[self rebuildMenu];
	} else {
		[stateMenuItemsAlreadyValidated removeAllObjects];
	}
}

- (void)statusIconSetChanged:(NSNotification *)notification
{
	[self rebuildMenu];	
}

/*!
 * @brief Generate the custom menu item for a status type
 */
- (NSMenuItem *)customMenuItemForStatusType:(AIStatusType)statusType
{
	NSMenuItem *menuItem;
	
	menuItem = [[NSMenuItem alloc] initWithTitle:STATUS_TITLE_CUSTOM
										  target:self
										  action:@selector(selectCustomState:)
								   keyEquivalent:@""];
	
	[menuItem setImage:[AIStatusIcons statusIconForStatusName:nil
												   statusType:statusType
													 iconType:AIStatusIconMenu
													direction:AIIconNormal]];
	[menuItem setTag:statusType];

	return [menuItem autorelease];
}

/*!
 * @brief Add the "Custom…" entry and the divider of every status type from @a fromStatusType up to (not including) @a toStatusType
 *
 * Every type is walked, not just the one being left behind, because a type can be missing from the
 * menu altogether: switch the built-in Away and the built-in Invisible off and, without saved away
 * statuses, not a single away status is enumerated - so the menu never crosses into the away group.
 * Deriving "Custom (away)…" from that crossing alone dropped it with them, and since it is the only
 * other way to go away from a status menu, Adium could not be set away from the menu bar, the dock,
 * the menu extra or the contact list any more. The switch tidies the menu; it must not close a door.
 *
 * @param skipFirst YES if @a fromStatusType has had its entry already - which is what the secondary
 *                  locked group (the Now Playing status) does before it begins.
 */
- (void)addCustomItemsForStatusTypesFrom:(AIStatusType)fromStatusType
									  to:(AIStatusType)toStatusType
					 skippingTheFirstOne:(BOOL)skipFirst
{
	NSInteger	statusType;

	for (statusType = (NSInteger)fromStatusType; statusType < (NSInteger)toStatusType; statusType++) {
		//Invisible shares the away group's entry everywhere in this menu; it never gets one of its own
		if (statusType == AIInvisibleStatusType) continue;

		if (!(skipFirst && (statusType == (NSInteger)fromStatusType))) {
			[menuItemArray addObject:[self customMenuItemForStatusType:(AIStatusType)statusType]];
		}

		//Add a divider
		[menuItemArray addObject:[NSMenuItem separatorItem]];
	}
}

/*!
 * @brief The statuses to show in an everyday status menu, sorted as always
 *
 * The one place where the "show in the status menu" switch is acted upon, which is why it covers the
 * menu bar, the dock, the status menu extra, the contact list window and the per-account submenus
 * of the contact list at once: all of them are only handed the menu items built below. The three
 * choosers of the status preferences and the "Set Status" menu of the accounts preferences are not
 * among them and show every status; +staticStatusStatesMenuNotifyingTarget: says why.
 *
 * Two safeguards. The status which is set right now is always shown, or no entry would carry a
 * checkmark any more and the menu would keep the user's own state from them - which is only half
 * the job, so -activeStatusStateChanged: rebuilds the menu when that status changes. And if nothing
 * at all is left, everything is shown; Offline has no "Custom…" stand-in and would otherwise be
 * unreachable from the status menu altogether.
 *
 * A whole status type falling away is <em>not</em> a dead end: -rebuildMenu builds the "Custom…"
 * entry of every type whether that type has any statuses left or not.
 */
+ (NSArray *)statusItemsForMenuDisplay
{
	NSArray			*allItems = [adium.statusController sortedFullStateArray];
	NSSet			*activeStates = [adium.statusController allActiveStatusStates];
	NSMutableArray	*visibleItems = [NSMutableArray arrayWithCapacity:[allItems count]];

	for (AIStatusItem *statusItem in allItems) {
		if ([statusItem showsInStatusMenu] || [activeStates containsObject:statusItem]) {
			[visibleItems addObject:statusItem];
		}
	}

	return ([visibleItems count] ? visibleItems : allItems);
}

/*!
 * @brief The statuses which are only in the menu because they are set right now
 *
 * The exception +statusItemsForMenuDisplay makes, on its own: when this set changes, the menu it
 * built no longer shows what it should, and -activeStatusStateChanged: rebuilds.
 */
+ (NSSet *)activeStatusItemsHiddenFromTheMenu
{
	NSMutableSet	*hiddenAndActive = [NSMutableSet set];

	for (AIStatusItem *statusItem in [adium.statusController allActiveStatusStates]) {
		if (![statusItem showsInStatusMenu]) [hiddenAndActive addObject:statusItem];
	}

	return hiddenAndActive;
}

/*!
 * @brief Rebuild the menu
 */
- (void)rebuildMenu
{
	NSEnumerator			*enumerator;
	NSMenuItem				*menuItem;
	AIStatus				*statusState;
	AIStatusType			currentStatusType = AIAvailableStatusType;
	AIStatusMutabilityType	currentStatusMutabilityType = AILockedStatusState;

	[adium.menuController delayMenuItemPostProcessing];
	
	if ([delegate respondsToSelector:@selector(statusMenu:willRemoveStatusMenuItems:)]) {
		[delegate statusMenu:self willRemoveStatusMenuItems:menuItemArray];
	}

	[menuItemArray removeAllObjects];
	[stateMenuItemsAlreadyValidated removeAllObjects];

	/* Taken down before the menu is built, and out of the same answer the build is about to use:
	 * this is what -activeStatusStateChanged: compares against to decide whether the menu still
	 * shows the status the user is in. */
	[hiddenActiveStatusItems release];
	hiddenActiveStatusItems = [[AIStatusMenu activeStatusItemsHiddenFromTheMenu] retain];

	/* Create a menu item for each state.  States must first be sorted such that states of the same AIStatusType
		* are grouped together.
		*/
	enumerator = [[AIStatusMenu statusItemsForMenuDisplay] objectEnumerator];
	while ((statusState = [enumerator nextObject])) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		AIStatusType thisStatusType = statusState.statusType;
		AIStatusMutabilityType thisStatusMutabilityType = [statusState mutabilityType];
		
		if ((currentStatusMutabilityType != AISecondaryLockedStatusState) &&
			(thisStatusMutabilityType == AISecondaryLockedStatusState)) {
			//Add the custom item, as we are ending this group
			[menuItemArray addObject:[self customMenuItemForStatusType:currentStatusType]];
			
			//Add a divider when we switch to a secondary locked group
			[menuItemArray addObject:[NSMenuItem separatorItem]];
		}
		
		//We treat Invisible statuses as being the same as Away for purposes of the menu
		if (thisStatusType == AIInvisibleStatusType) thisStatusType = AIAwayStatusType;
		
		/* Add the "Custom..." state option and a separatorItem before beginning to add items for a new statusType
			* Sorting the menu items before enumerating means that we know our statuses are sorted first by statusType
			*/
		if ((currentStatusType != thisStatusType) &&
			(currentStatusType != AIOfflineStatusType)) {
			/* Every type between the one being left and the one beginning, so that a type with no
			 * statuses left to enumerate still gets its "Custom…" entry. The one after a secondary
			 * locked group is skipped: that group added it before it began. */
			[self addCustomItemsForStatusTypesFrom:currentStatusType
												to:thisStatusType
							   skippingTheFirstOne:(currentStatusMutabilityType == AISecondaryLockedStatusState)];

			currentStatusType = thisStatusType;
		}

		menuItem = [[NSMenuItem alloc] initWithTitle:[AIStatusMenu titleForMenuDisplayOfState:statusState]
											  target:self
											  action:@selector(selectState:)
									   keyEquivalent:@""];
		
		[menuItem setToolTip:[statusState statusMessageTooltipString]];
		[menuItem setRepresentedObject:[NSDictionary dictionaryWithObject:statusState
																   forKey:@"AIStatus"]];
		[menuItem setTag:currentStatusType];
		[menuItem setImage:[statusState menuIcon]];
		[menuItemArray addObject:menuItem];
		[menuItem release];
		
		currentStatusMutabilityType = thisStatusMutabilityType;
		[pool release];
	}
	
	if (currentStatusType != AIOfflineStatusType) {
		/* The types the enumeration never reached still want their "Custom..." entry. At present the
		 * last status type is always AIOfflineStatusType, so this is for completeness. */
		[self addCustomItemsForStatusTypesFrom:currentStatusType
											to:AIOfflineStatusType
						   skippingTheFirstOne:(currentStatusMutabilityType == AISecondaryLockedStatusState)];

		//Nothing follows, so the divider the loop appended has nothing left to divide
		if ([[menuItemArray lastObject] isSeparatorItem]) [menuItemArray removeLastObject];
	}

	//Now that we are done creating the menu items, tell the plugin about them
	[delegate statusMenu:self didRebuildStatusMenuItems:menuItemArray];
	
	[adium.menuController endDelayMenuItemPostProcessing];
}

/*!
* @brief Menu validation
 *
 * Our state menu items should always be active, so always return YES for validation.
 *
 * Here we lazily set the state of our menu items if our stateMenuItemsAlreadyValidated set indicates it is needed.
 *
 * Random note: stateMenuItemsAlreadyValidated will almost never have a count of 0 because separatorItems
 * get included but never get validated.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if (![stateMenuItemsAlreadyValidated containsObject:menuItem]) {
		NSDictionary	*dict = [menuItem representedObject];
		AIAccount		*account = [dict objectForKey:@"AIAccount"];
		AIStatus		*menuItemStatusState = [dict objectForKey:@"AIStatus"];
		
		if (account) {
			/* Account-specific menu items */
			AIStatus *appropriateActiveStatusState = account.statusState;
			
			/* Our "Custom..." menu choice has a nil represented object.  If the appropriate active search state is
				* in our array of states from which we made menu items, we'll be searching to match it.  If it isn't,
				* we have a custom state and will be searching for the custom item of the right type, switching all other
				* menu items to NSControlStateValueOff.
				*/
			if ([adium.statusController.flatStatusSet containsObject:appropriateActiveStatusState]) {
				//If the search state is in the array so is a saved state, search for the match
				if (menuItemStatusState == appropriateActiveStatusState) {
					if ([menuItem state] != NSControlStateValueOn) [menuItem setState:NSControlStateValueOn];
				} else {
					if ([menuItem state] != NSControlStateValueOff) [menuItem setState:NSControlStateValueOff];
				}
			} else {
				//If there is not a status state, we are in a Custom state. Search for the correct Custom item.
				if (menuItemStatusState) {
					//If the menu item has an associated state, it's always off.
					if ([menuItem state] != NSControlStateValueOff) [menuItem setState:NSControlStateValueOff];
				} else {
					//If it doesn't, check the tag to see if it should be on or off.
					if ([menuItem tag] == appropriateActiveStatusState.statusType) {
						if ([menuItem state] != NSControlStateValueOn) [menuItem setState:NSControlStateValueOn];
					} else {
						if ([menuItem state] != NSControlStateValueOff) [menuItem setState:NSControlStateValueOff];
					}
				}
			}
		} else {
			/* General menu items */
			NSSet	*allActiveStatusStates = [adium.statusController allActiveStatusStates];
			int		onState = (([allActiveStatusStates count] == 1) ? NSControlStateValueOn : NSControlStateValueMixed);
			
			if (menuItemStatusState) {
				//If this menu item has a status state, set it to the right on state if that state is active
				if ([allActiveStatusStates containsObject:menuItemStatusState]) {
					if ([menuItem state] != onState) [menuItem setState:onState];
				} else {
					if ([menuItem state] != NSControlStateValueOff) [menuItem setState:NSControlStateValueOff];
				}
			} else {
				//If it doesn't, check the tag to see if it should be on or off by looking for a matching custom state
				NSEnumerator	*activeStatusStatesEnumerator = [allActiveStatusStates objectEnumerator];
				NSSet			*flatStatusSet = adium.statusController.flatStatusSet;
				AIStatus		*statusState;
				BOOL			foundCorrectStatusState = NO;
				
				while (!foundCorrectStatusState && (statusState = [activeStatusStatesEnumerator nextObject])) {
					/* We found a custom match if our array of menu item states doesn't contain this state and
					* its statusType matches the menuItem's tag.
					*/
					foundCorrectStatusState = (![flatStatusSet containsObject:statusState] &&
											   ([menuItem tag] == statusState.statusType));
				}
				
				if (foundCorrectStatusState) {
					if ([menuItem state] != NSControlStateValueOn) [menuItem setState:onState];
				} else {
					if ([menuItem state] != NSControlStateValueOff) [menuItem setState:NSControlStateValueOff];
				}
			}
		}
		
		[stateMenuItemsAlreadyValidated addObject:menuItem];
	}
	
	return YES;
}

/*!
 * @brief Select a state menu item
 *
 * Invoked by a state menu item, sets the state corresponding to the menu item as the active state.
 *
 * If the representedObject NSDictionary has an @"AIAccount" object, set the state just for the appropriate AIAccount.
 * Otherwise, set the state globally.
 */
- (void)selectState:(id)sender
{
	NSDictionary	*dict = [sender representedObject];
	AIStatusItem	*statusItem = [dict objectForKey:@"AIStatus"];
	AIAccount		*account = [dict objectForKey:@"AIAccount"];
	
	/* Random undocumented feature of the moment... hold option and select a state to bring up the custom status window
	 * for modifying and then setting it. Alternately, select an active status (one in the on state) to do the same.
	 * Selecting a mixed state item should still select it to switch to full-on (all accounts).
	 */	
	NSEventType eventType = [[NSApp currentEvent] type];
	BOOL		keyEvent = (eventType == NSEventTypeKeyDown || eventType == NSEventTypeKeyUp);
	BOOL		isOptionClick = [NSEvent optionKey] && !keyEvent;
	if (isOptionClick ||
		(([sender state] == NSControlStateValueOn) && (statusItem.statusType != AIOfflineStatusType))) {
		[AIEditStateWindowController editCustomState:(AIStatus *)statusItem
											 forType:statusItem.statusType
										  andAccount:account
									  withSaveOption:YES
											onWindow:nil
									 notifyingTarget:adium.statusController];
		
	} else {
		if (account) {
			BOOL shouldRebuild;
			
			shouldRebuild = [adium.statusController removeIfNecessaryTemporaryStatusState:account.statusState];
			[account setStatusState:(AIStatus *)statusItem];
			
			//Enable the account if it isn't currently enabled
			if (!account.enabled && statusItem.statusType != AIOfflineStatusType) {
				[account setEnabled:YES];
			}
			
			if (shouldRebuild) {
				//Rebuild our menus if there was a change
				[[NSNotificationCenter defaultCenter] postNotificationName:AIStatusStateArrayChangedNotification object:nil];
			}
			
		} else {
			[adium.statusController setActiveStatusState:(AIStatus *)statusItem];
		}
	}
}

/*!
 * @brief Select the custom state menu item
 *
 * Invoked by the custom state menu item, opens a custom state window.
 * If the representedObject NSDictionary has an @"AIAccount" object, configure just for the appropriate AIAccount.
 * Otherwise, configure globally.
 */
- (IBAction)selectCustomState:(id)sender
{
	NSDictionary	*dict = [sender representedObject];
	AIAccount		*account = [dict objectForKey:@"AIAccount"];
	AIStatusType	statusType = (AIStatusType)[sender tag];
	AIStatus		*baseStatusState;
	
	if (account) {
		baseStatusState = account.statusState;
	} else {
		baseStatusState = adium.statusController.activeStatusState;
	}
	
	/* If we are going to a custom state of a different type, we don't want to prefill with baseStatusState as it stands.
	 * Instead, we load the last used status of that type.
	 */
	if ((baseStatusState.statusType != statusType)) {
		NSDictionary *lastStatusStates = [adium.preferenceController preferenceForKey:@"LastStatusStates"
																				  group:PREF_GROUP_STATUS_PREFERENCES];
		NSData		*lastStatusStateData = [lastStatusStates objectForKey:[[NSNumber numberWithInt:statusType] stringValue]];
		AIStatus	*lastStatusStateOfThisType = (lastStatusStateData ?
												  [NSKeyedUnarchiver objectWithArchivedData:lastStatusStateData] :
												  nil);
		if (lastStatusStateOfThisType) {
			// Restore the current status message into this last-saved variety, since users tend want to keep them.
			// If it doesn't exist, use the last-saved status message.
			if (baseStatusState.statusMessage.length) {
				lastStatusStateOfThisType.statusMessage = baseStatusState.statusMessage;
			}
			
			baseStatusState = [[lastStatusStateOfThisType retain] autorelease];
		}
	}

	[AIEditStateWindowController editCustomState:baseStatusState
										 forType:statusType
									  andAccount:account
								  withSaveOption:YES
										onWindow:nil
								 notifyingTarget:adium.statusController];
}

#pragma mark -
#pragma mark Class methods
+ (NSMenu *)staticStatusStatesMenuNotifyingTarget:(id)target selector:(SEL)selector
{
	NSMenu			*statusStatesMenu = [[NSMenu alloc] init];
	NSEnumerator	*enumerator;
	AIStatus		*statusState;
	AIStatusType	currentStatusType = AIAvailableStatusType;
	NSMenuItem		*menuItem;
	
	[statusStatesMenu setMenuChangedMessagesEnabled:NO];
	[statusStatesMenu setAutoenablesItems:NO];
	
	/* Create a menu item for each state.  States must first be sorted such that states of the same
	 * AIStatusType are grouped together.
	 *
	 * Deliberately every status, not +statusItemsForMenuDisplay. The line runs between the everyday
	 * status menus, which filter, and the preference panes, which do not - and this method serves
	 * only the latter:
	 *
	 *   - The three choosers of the status preferences would otherwise hide a setting that is in
	 *     force and fall back to "Do not change" - whereupon the next click would write
	 *     STATUS_STATE_ID_NONE and switch off an automatic status the user never touched.
	 *   - The "Set Status" submenu of the accounts preferences, and the status menu of an account's
	 *     info sheet, are where an account is set up; every status Adium knows belongs there,
	 *     whether or not the user keeps it out of the menu bar.
	 *
	 * Hiding a status tidies the everyday menu; it takes nothing away. */
	enumerator = [[adium.statusController sortedFullStateArray] objectEnumerator];
	while ((statusState = [enumerator nextObject])) {
		AIStatusType thisStatusType = statusState.statusType;

		//We treat Invisible statuses as being the same as Away for purposes of the menu
		if (thisStatusType == AIInvisibleStatusType) thisStatusType = AIAwayStatusType;

		if (currentStatusType != thisStatusType) {
			//Add a divider between each type of status
			[statusStatesMenu addItem:[NSMenuItem separatorItem]];
			currentStatusType = thisStatusType;
		}
	
		menuItem = [[NSMenuItem alloc] initWithTitle:[AIStatusMenu titleForMenuDisplayOfState:statusState]
											  target:target
											  action:selector
									   keyEquivalent:@""];
	
		[menuItem setImage:[statusState menuIcon]];
		[menuItem setTag:statusState.statusType];
		[menuItem setRepresentedObject:[NSDictionary dictionaryWithObject:statusState
																   forKey:@"AIStatus"]];
		[menuItem setToolTip:[statusState statusMessageTooltipString]];

		[statusStatesMenu addItem:menuItem];
		[menuItem release];
	}
	
	[statusStatesMenu setMenuChangedMessagesEnabled:YES];
	
	return [statusStatesMenu autorelease];
}

/*!
* @brief Determine a string to use as a menu title
 *
 * This method truncates a state title string for display as a menu item.
 * Wide menus aren't pretty and may cause crashing in certain versions of OS X, so all state
 * titles should be run through this method before being used as menu item titles.
 *
 * @param statusState The state for which we want a title
 *
 * @result An appropriate NSString title
 */
+ (NSString *)titleForMenuDisplayOfState:(AIStatusItem *)statusState
{
	NSString	*title = [statusState title];
	
	/* Why plus 3? Say STATE_TITLE_MENU_LENGTH was 7, and the title is @"ABCDEFGHIJ".
	* The shortened title will be @"ABCDEFG..." which looks to be just as long - even
	* if the ellipsis is an ellipsis character and therefore technically two characters
	* shorter. Better to just use the full string, which appears as being the same length.
	*/
	if ([title length] > (STATE_TITLE_MENU_LENGTH + 3)) {
		title = [title stringWithEllipsisByTruncatingToLength:STATE_TITLE_MENU_LENGTH];
	}
	
	return title;
}

@end
