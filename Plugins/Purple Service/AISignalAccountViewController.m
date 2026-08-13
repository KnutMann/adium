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

#import "AISignalAccountViewController.h"
#import <Adium/AIAccount.h>

/*!
 * @brief Account editor for Signal
 *
 * Signal authenticates by linking Adium as a secondary device via QR code, so
 * there is no password and no server to configure; those fields are hidden. The
 * QR code appears on its own when the account is enabled, through the same image
 * request window WhatsApp's linking uses.
 */
@implementation AISignalAccountViewController

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
}

@end
