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

#import <Adium/AIContactControllerProtocol.h>

@class AIAccount, AISettingsFormView;

@interface AIAccountViewController : NSObject {
	/* These are the views used in Adium's account preferences.  If views aren't provided by a custom account view
	 * nib, default views with the most common controls will be used.  There is no need to provide a custom nib
	 * if your account code only needs the default controls.  Avoid using the auxiliary tabs if possible. */
    IBOutlet	NSView			*view_setup;              		//Account setup (UID, password, etc)
    IBOutlet	NSView			*view_profile;              	//Account profile (Alias, profile)
    IBOutlet	NSView			*view_options;              	//Account options (Host, port, mail, protocol, etc)
    IBOutlet	NSView			*view_privacy;              	//Account privacy (Encryption, typing, etc)
    IBOutlet	NSTabView		*view_auxiliaryTabView;			//Tab view containing auxiliary tabs
	
	//These common controls are used by most protocols, so we place them here as a convenience to protocol code.
	//Custom account view nibs are encouraged to connect to these outlets.
	IBOutlet	NSTextField		*textField_accountUIDLabel;		//Label on UID field
	IBOutlet	NSTextField		*textField_accountUID;			//UID field
	IBOutlet	NSTextField		*label_password;				//Label on the password field
	IBOutlet	NSTextField		*textField_password;			//Password field

	BOOL						passwordWasShown;			//Whether the field was filled from the keychain
	NSMutableDictionary			*switchesByCheckBox;		//Switches standing in for nib checkboxes
	NSMutableDictionary			*checkBoxesBySwitch;
	IBOutlet	NSTextField		*textField_connectHost;			//Connect host
	IBOutlet	NSTextField		*textField_connectPort;			//Connect port
	IBOutlet	NSTextField		*textField_alias;				//User alias (or display name)
	IBOutlet	NSTextField		*label_alias;					//Label for the alias field
	IBOutlet	NSButton		*checkBox_checkMail;			//Check for new mail
	
	IBOutlet	NSTextField		*label_port;					//Label for the port field
	IBOutlet	NSTextField		*label_server;					//Label for the login server field
	
	IBOutlet	NSTextField		*label_typing;					//Label for the typing preference
	IBOutlet	NSButton		*checkBox_sendTyping;			//Send the user's typing state
	
	IBOutlet	NSTextField		*label_readReceipts;			//Label for the read receipt preference
	IBOutlet	NSButton		*checkBox_sendReadReceipts;		//Send read markers once the user read a message
	
	IBOutlet	NSTextField		*label_encryption;				//Label for the encryption preference
	IBOutlet	NSPopUpButton	*popUp_encryption;				//Encryption preference
	
	IBOutlet	NSProgressIndicator *progressIndicator_registering;
	IBOutlet	NSTextField			*textField_registering;
	
	//Instance variables
    AIAccount			*account;
	NSMutableDictionary	*changedPrefDict;
}

+ (id)accountViewController;
- (id)init;
- (NSView *)setupView;
- (NSView *)profileView;
- (NSView *)optionsView;
- (NSView *)privacyView;
- (void)configureForAccount:(AIAccount *)inAccount;
- (IBAction)changedPreference:(id)sender;
- (NSString *)nibName;
- (void)saveConfiguration;

- (void)didBeginRegistration;
- (void)usernameAndPasswordRegistered:(NSNotification*)notification;


/*!
 * @brief Does this controller use the shared account views rather than a nib of its own?
 *
 * A service which brings its own nib has fields nobody here knows about, so its views are shown
 * whole. One using the shared ones has exactly the fields below, and those can be laid out as
 * ordinary settings rows.
 */
- (BOOL)usesSharedAccountViews;

/*!
 * @brief Put the shared fields into a settings form as rows
 *
 * The very same controls, moved out of their nib view and into rows. Nothing about loading or saving
 * changes, because both still read and write these outlets; only where they sit does.
 */
- (void)addAccountRowsToForm:(AISettingsFormView *)form;
- (void)addProfileRowsToForm:(AISettingsFormView *)form;
- (void)addPrivacyRowsToForm:(AISettingsFormView *)form;

/*!
 * @brief One row around a control that already exists, for a subclass adding its own
 */
- (void)addRow:(AISettingsFormView *)form control:(NSView *)control label:(NSTextField *)labelField fallback:(NSString *)fallback;

/*!
 * @brief A nib checkbox shown as the switch a settings row uses
 */
- (void)addSwitchRow:(AISettingsFormView *)form checkBox:(NSButton *)checkBox label:(NSString *)label;

@end

@interface AIAccountViewController (ForSubclasses)
- (NSDictionary *)keyToKeyDict;
- (void)localizeStrings;
@end
