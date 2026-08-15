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

#import "ESIRCAccountPlan.h"
#import "ESIRCAccount.h"

#import <Adium/AIAccount.h>
#import <AIUtilities/AIStringUtilities.h>

@implementation ESIRCAccountPlan

- (void)describe
{
	[super describe];

	//Sent by the account once it is connected. No option declares them, because they are not the protocol's
	AIAccountPlanField *commands = [AIAccountPlanField fieldNamed:@"ircCommands" kind:AIAccountFieldMultiline];

	[commands setStore:AIAccountFieldStorePreference];
	[commands setPreferenceKey:KEY_IRC_COMMANDS];
	[commands setLabel:AILocalizedString(@"Execute commands on connect", nil)];
	[commands setDetail:AILocalizedString(@"One per line, without the leading slash.",
										  "Explains how the commands sent after connecting to IRC are written")];

	[self addField:commands toCard:AIAccountCardOptions];
}

@end
