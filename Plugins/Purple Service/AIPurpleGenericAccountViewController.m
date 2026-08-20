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

#import "AIPurpleGenericAccountViewController.h"
#import "AIPurpleGenericService.h"

#import <Adium/AIAccount.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIStringUtilities.h>

#import <libpurple/libpurple.h>
#import <libpurple/accountopt.h>

@interface AIPurpleGenericAccountViewController ()
@end

@implementation AIPurpleGenericAccountViewController

- (void)configureForAccount:(AIAccount *)inAccount
{
	[super configureForAccount:inAccount];

	AIPurpleGenericService *service = (AIPurpleGenericService *)inAccount.service;
	if (![service isKindOfClass:[AIPurpleGenericService class]])
		return;

	/* A protocol that authenticates by its own means, which all the newer ones do, says so through
	 * OPT_PROTO_NO_PASSWORD. Asking it beats three services each stating the same thing in code. */
	if (![service supportsPassword]) {
		[label_password setHidden:YES];
		[textField_password setHidden:YES];
	}

	/* And a protocol that connects wherever it likes declares no server or port for anyone to set.
	 * Pidgin builds its whole account dialog out of these options; this reads two of them.
	 *
	 * IRC is the exception that declares no server option and still needs one, because it carries the
	 * server in the account name. The descriptor says so, and then the field stays. */
	if (![service protocolHasOption:@"server"] &&
		![[service descriptorValueForKey:@"AccountNameIncludesHost"] boolValue]) {
		[label_server setHidden:YES];
		[textField_connectHost setHidden:YES];
	}

	if (![service protocolHasOption:@"port"]) {
		[label_port setHidden:YES];
		[textField_connectPort setHidden:YES];
	}
}

@end
