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

#import "ESPurpleJabberAccountPlan.h"
#import "ESPurpleJabberAccount.h"

#import <Adium/AIAccount.h>

@implementation ESPurpleJabberAccountPlan

/*!
 * @brief Two switches become the one choice the protocol has always had
 *
 * Adium kept "Require TLS" and "Force Old SSL" apart and turned them into a single
 * connection_security value on every connect. That rule is read here once, so that the row shows what
 * the account is actually running on rather than the protocol's own default. Neither switch has had a
 * place in the interface since the options came from the protocol.
 */
- (void)migrateLegacy
{
	[super migrateLegacy];

	NSString *key = [self preferenceKeyForSetting:@"connection_security"];

	//Only ever once: a chosen value is not something to overwrite with a derived one
	if ([[self account] preferenceForKey:key group:GROUP_ACCOUNT_STATUS])
		return;

	NSString *security;

	if ([[[self account] preferenceForKey:KEY_JABBER_FORCE_OLD_SSL group:GROUP_ACCOUNT_STATUS] boolValue])
		security = @"old_ssl";
	else if ([[[self account] preferenceForKey:KEY_JABBER_REQUIRE_TLS group:GROUP_ACCOUNT_STATUS] boolValue])
		security = @"require_tls";
	else
		security = @"opportunistic_tls";

	[[self account] setPreference:security forKey:key group:GROUP_ACCOUNT_STATUS];
}

@end
