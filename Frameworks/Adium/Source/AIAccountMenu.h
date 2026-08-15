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

#import <Adium/AIAbstractListObjectMenu.h>
#import <Adium/AIContactObserverManager.h>
#import <Adium/AIStatusMenu.h>

@class AIAccount;
@protocol AIAccountMenuDelegate;

typedef enum {
	AIAccountNoSubmenu = 0,
	AIAccountStatusSubmenu,
	AIAccountOptionsSubmenu
} AIAccountSubmenuType;

/*!
 * @brief What an account carries in front of its name in a menu
 *
 * A menu item holds one picture, so showing both the status and the service means drawing them side
 * by side into one. Whether that reads as two useful facts or as two symbols fighting each other
 * depends on the icon set, which is why it is a choice rather than a decision.
 */
typedef enum {
	AIAccountMenuIconStatusAndService = 0,
	AIAccountMenuIconServiceOnly,
	AIAccountMenuIconStatusOnly
} AIAccountMenuIconType;

#define KEY_ACCOUNT_MENU_ICON	@"Account Menu Icon"

@interface AIAccountMenu : AIAbstractListObjectMenu <AIListObjectObserver, AIStatusMenuDelegate, NSMenuDelegate> {
	id<AIAccountMenuDelegate>				delegate;
	BOOL			delegateRespondsToDidSelectAccount;
	BOOL			delegateRespondsToShouldIncludeAccount;	

	BOOL			useSystemFont;
	BOOL			submenuType;
	BOOL			showTitleVerbs;
	BOOL			includeDisabledAccountsMenu;
	BOOL			delegateRespondsToSpecialMenuItem;

	NSControlSize	controlSize;

	AIStatusMenu	*statusMenu;
}

+ (id)accountMenuWithDelegate:(id<AIAccountMenuDelegate>)inDelegate
				  submenuType:(AIAccountSubmenuType)inSubmenuType
			   showTitleVerbs:(BOOL)inShowTitleVerbs;

/*!	@brief	Whether to use the system font instead of the menu font.
 *
 *	@par	By default, menu items in the account menu use the menu font, but a client can request them with the system font instead.
 */
@property (readwrite, nonatomic) BOOL useSystemFont;

@property (readwrite, nonatomic, assign) id<AIAccountMenuDelegate> delegate;

- (NSMenuItem *)menuItemForAccount:(AIAccount *)account;

@end

@protocol AIAccountMenuDelegate <NSObject>
- (void)accountMenu:(AIAccountMenu *)inAccountMenu didRebuildMenuItems:(NSArray *)menuItems;

@optional
- (void)accountMenu:(AIAccountMenu *)inAccountMenu didSelectAccount:(AIAccount *)inAccount; 	
- (BOOL)accountMenu:(AIAccountMenu *)inAccountMenu shouldIncludeAccount:(AIAccount *)inAccount; 

/*!
 * @brief At what size will this menu be used?
 *
 * If not implemented, the default is NSControlSizeRegular. NSControlSizeMini is not supported.
 */
- (NSControlSize)controlSizeForAccountMenu:(AIAccountMenu *)inAccountMenu; 

//Does the menu require a special topmost item + seperator?
- (NSMenuItem *)accountMenuSpecialMenuItem:(AIAccountMenu *)inAccountMenu;			

//Should the account menu include a submenu of 'disabled accounts'?
- (BOOL)accountMenuShouldIncludeDisabledAccountsMenu:(AIAccountMenu *)inAccountMenu;			
@end
