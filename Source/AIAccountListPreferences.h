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

#import <Adium/AIPreferencePane.h>
#import <Adium/AISettingsNavigationController.h>
#import <Adium/AISettingsFormView.h>

@class AIAccountSettingsPage;
#import <Adium/AIContactObserverManager.h>
#import <AIUtilities/AISegmentedControl.h>

@class AIAccountController, AIAccount, AIAutoScrollView, AIImageViewWithImagePicker;

@interface AIAccountListPreferences : AIPreferencePane <AIListObjectObserver, NSTableViewDelegate, AISettingsNavigationControllerDelegate> {
	//Account list
    IBOutlet		NSScrollView			*scrollView_accountList;
    IBOutlet		NSTableView				*tableView_accountList;
	IBOutlet		AISegmentedControl		*button_addOrRemoveAccount;
	/* Unused: the (i) button of a row opens the account editor now. The outlet has to stay for as
	 * long as the nib connects it, or loading the nib raises NSUnknownKeyException. */
	IBOutlet		NSButton				*button_editAccount;
	/* Unused: the pane no longer shows an overview line below the list. The outlet has to stay
	 * for as long as the nib connects it, or loading the nib raises NSUnknownKeyException. */
	IBOutlet		NSTextField				*textField_overview;

	/* The nib is only a supplier of ready made controls now; our view is the settings form we
	 * move them into. This keeps the nib's top level view (and with it the nib's ownership of
	 * everything we did not move) alive for as long as we use its controls. */
	NSView							*nibView;

	/* The pane is a page stack now: the list is its root page, an account's settings slide in on
	 * top. AIModularPane knows only about a view, so the controller has to be held here. */
	AISettingsNavigationController	*navigationController;
	AISettingsFormView				*listForm;
	AIAccountSettingsPage			*detailPage;
	AIAccount						*newAccountBeingCreated;	//Not retained; the account controller holds it

    //Account List
    NSArray							*accountArray;

	NSMutableDictionary				*requiredHeightDict;

	NSTimer							*reconnectTimeUpdater;
}

- (IBAction)addOrRemoveAccount:(id)sender;
- (void)deleteAccount:(AIAccount *)inAccount;
- (void)editAccount:(AIAccount *)inAccount;
- (IBAction)editSelectedAccount:(id)sender;
- (NSString *)statusMessageForAccount:(AIAccount *)account;
- (NSMenu *)menuForRow:(NSInteger) row;

@end
