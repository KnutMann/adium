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

@class AIStatusItem;
@protocol AIStatusMenuDelegate;

@interface AIStatusMenu : NSObject <NSMenuItemValidation>{
	NSMutableArray	*menuItemArray;
	NSMutableSet	*stateMenuItemsAlreadyValidated;

	/* The statuses which are in the menu although their switch is off, because they are the status
	 * an account is in right now. Remembered from the last rebuild so that -activeStatusStateChanged:
	 * can tell whether the menu still shows the right ones. */
	NSSet			*hiddenActiveStatusItems;

	__unsafe_unretained id<AIStatusMenuDelegate>	delegate;
}

+ (id)statusMenuWithDelegate:(id<AIStatusMenuDelegate>)inDelegate;

@property (readwrite, nonatomic, assign) id<AIStatusMenuDelegate> delegate;

- (void)delegateWillReplaceAllMenuItems;
- (void)delegateCreatedMenuItems:(NSArray *)addedMenuItems;
- (void)rebuildMenu;

+ (NSMenu *)staticStatusStatesMenuNotifyingTarget:(id)target selector:(SEL)selector;
+ (NSString *)titleForMenuDisplayOfState:(AIStatusItem *)statusState;

@end

@protocol AIStatusMenuDelegate <NSObject>
- (void)statusMenu:(AIStatusMenu *)statusMenu didRebuildStatusMenuItems:(NSArray *)inMenuItems;
@optional
- (void)statusMenu:(AIStatusMenu *)statusMenu willRemoveStatusMenuItems:(NSArray *)inMenuItems;
@end
