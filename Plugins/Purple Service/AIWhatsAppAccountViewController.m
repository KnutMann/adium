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

#import "AIWhatsAppAccountViewController.h"
#import <Adium/AIAccount.h>

/*!
 * @brief Account editor for WhatsApp
 *
 * WhatsApp authenticates by linking Adium as a device via QR code, so
 * there is no password and no server to configure; those fields are
 * hidden. Adds a checkbox controlling whether WhatsApp status
 * broadcasts are shown as messages.
 */
@implementation AIWhatsAppAccountViewController

- (void)configureForAccount:(AIAccount *)inAccount
{
	[super configureForAccount:inAccount];

	//No password: the account is linked to the phone via QR code
	[label_password setHidden:YES];
	[textField_password setHidden:YES];

	//No server settings either
	[label_server setHidden:YES];
	[textField_connectHost setHidden:YES];
	[label_port setHidden:YES];
	[textField_connectPort setHidden:YES];

	//Checkbox: suppress WhatsApp status broadcasts (stories)
	if (!checkBox_ignoreStatusBroadcasts && textField_connectHost) {
		NSView *optionsContainer = [textField_connectHost superview];
		NSRect hostFrame = [textField_connectHost frame];

		checkBox_ignoreStatusBroadcasts = [[NSButton alloc] initWithFrame:NSMakeRect(20, NSMinY(hostFrame) - 4, NSWidth([optionsContainer frame]) - 40, 24)];
		[checkBox_ignoreStatusBroadcasts setButtonType:NSButtonTypeSwitch];
		[checkBox_ignoreStatusBroadcasts setTitle:AILocalizedString(@"Don't show status updates as messages", "WhatsApp account option")];
		[[checkBox_ignoreStatusBroadcasts cell] setControlSize:NSControlSizeSmall];
		[checkBox_ignoreStatusBroadcasts setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]]];
		[optionsContainer addSubview:checkBox_ignoreStatusBroadcasts];
		[checkBox_ignoreStatusBroadcasts release];
	}

	NSNumber *ignoreStatus = [inAccount preferenceForKey:KEY_WHATSAPP_IGNORE_STATUS group:GROUP_ACCOUNT_STATUS];
	[checkBox_ignoreStatusBroadcasts setState:((!ignoreStatus || [ignoreStatus boolValue]) ? NSControlStateValueOn : NSControlStateValueOff)];
}

- (void)saveConfiguration
{
	[super saveConfiguration];

	[account setPreference:[NSNumber numberWithBool:([checkBox_ignoreStatusBroadcasts state] == NSControlStateValueOn)]
					forKey:KEY_WHATSAPP_IGNORE_STATUS
					 group:GROUP_ACCOUNT_STATUS];
}

@end
