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

#import "ESIRCAccountViewController.h"
#import <Adium/AISettingsFormView.h>
#import "ESIRCAccount.h"
#import "AIService.h"
#import <AIUtilities/AIStringFormatter.h>
#import <AIUtilities/AIAttributedStringAdditions.h>
#import <AIUtilities/AIPopUpButtonAdditions.h>

@implementation ESIRCAccountViewController

- (NSString *)nibName{
    return @"ESIRCAccountView";
}

- (void)awakeFromNib
{
	[super awakeFromNib];
	
	[popUp_encoding setMenu:[self encodingMenu]];
}

- (void)configureForAccount:(AIAccount *)inAccount
{
    [super configureForAccount:inAccount];
	
	// Encoding
	[popUp_encoding selectItemWithRepresentedObject:[account preferenceForKey:KEY_IRC_ENCODING
																		group:GROUP_ACCOUNT_STATUS]];
	
	// Connection SSL
	[checkbox_useSSL setState:[[account preferenceForKey:KEY_IRC_USE_SSL group:GROUP_ACCOUNT_STATUS] boolValue]];

	// Disable the server field when online, since this will change our Purple account name
	[textField_connectHost setEnabled:!account.online];
	
	// Execute commands
	NSString *commands = [account preferenceForKey:KEY_IRC_COMMANDS group:GROUP_ACCOUNT_STATUS] ?: @"";
	[textView_commands.textStorage setAttributedString:[NSAttributedString stringWithString:commands]];
	
	// Username
	NSString *username = [account preferenceForKey:KEY_IRC_USERNAME group:GROUP_ACCOUNT_STATUS] ?: @"";
	[textField_username setStringValue:username];
	[textField_username.cell setPlaceholderString:((ESIRCAccount *)account).defaultUsername];
	
	// Realname
	NSString *realname = [account preferenceForKey:KEY_IRC_REALNAME group:GROUP_ACCOUNT_STATUS] ?: @"";
	[textField_realname setStringValue:realname];
	[textField_realname.cell setPlaceholderString:((ESIRCAccount *)account).defaultRealname];
}

- (void)saveConfiguration
{
	[super saveConfiguration];
	
	// Encoding
	[account setPreference:[[popUp_encoding selectedItem] representedObject]
					forKey:KEY_IRC_ENCODING
					 group:GROUP_ACCOUNT_STATUS];
	
	// Connection SSL
	[account setPreference:[NSNumber numberWithBool:[checkbox_useSSL state]]
					forKey:KEY_IRC_USE_SSL
					 group:GROUP_ACCOUNT_STATUS];
	
	// Execute commands
	[account setPreference:textView_commands.textStorage.string forKey:KEY_IRC_COMMANDS group:GROUP_ACCOUNT_STATUS];
	
	// Username
	[account setPreference:(textField_username.stringValue.length ? textField_username.stringValue : nil)
					forKey:KEY_IRC_USERNAME
					 group:GROUP_ACCOUNT_STATUS];
	
	// Realname
	[account setPreference:(textField_realname.stringValue.length ? textField_realname.stringValue : nil)
					forKey:KEY_IRC_REALNAME
					 group:GROUP_ACCOUNT_STATUS];
}

#pragma mark Localization
//The xib is monolingual (English); set all visible strings from code
- (void)localizeStrings
{
	[super localizeStrings];

	NSBundle *adiumFrameworkBundle = [NSBundle bundleForClass:[AIAccountViewController class]];

	//Setup
	[label_password setStringValue:AILocalizedStringFromTableInBundle(@"Password:", nil, adiumFrameworkBundle, "Label for the password field in the account preferences")];
	[[textField_password cell] setPlaceholderString:AILocalizedString(@"(optional)", "Placeholder for the optional IRC server password field")];
	[label_server setStringValue:AILocalizedString(@"Hostname:", "Label for the IRC server field in the account preferences")];

	//Options
	[label_port setStringValue:AILocalizedStringFromTableInBundle(@"Port:", nil, adiumFrameworkBundle, "Label for the port field in the account preferences")];
	[checkbox_useSSL setTitle:AILocalizedString(@"Encrypt connection using SSL", nil)];
	[label_encoding setStringValue:AILocalizedString(@"Encoding:", nil)];
	[box_commands setTitle:AILocalizedString(@"Execute commands on connect:", nil)];
	[label_commandsHint setStringValue:AILocalizedString(@"One per line, / is optional. $me will be replaced with your current nickname.", nil)];

	//Personal
	[label_realname setStringValue:AILocalizedString(@"Realname:", nil)];
	[label_username setStringValue:AILocalizedString(@"Username (Ident):", nil)];
}


//Its own fields, as rows ----------------------------------------------------------------------------------------------
#pragma mark Its own fields, as rows

/*!
 * @brief The commands to send after connecting
 *
 * The only thing on this page the protocol knows nothing about: it is Adium that sends these, so it
 * is Adium that has to ask for them. Username, real name, SSL and the encoding are gone from here
 * because irc.c declares every one of them, along with SASL and a quit message that this nib never
 * offered at all.
 *
 * A text view rather than a field, so it gets a row of its own with the label above it, the way the
 * other multi line settings in this application are laid out.
 */
- (void)addProfileRowsToForm:(AISettingsFormView *)form
{
	[super addProfileRowsToForm:form];

	if (box_commands && ![box_commands isHidden]) {
		[box_commands removeFromSuperview];
		[form addFullWidthRow:box_commands stretch:YES];
	}
}

@end
