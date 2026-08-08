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

#import "AIPurpleWhatsAppAccount.h"
#import "AIWhatsAppAccountViewController.h"

@implementation AIPurpleWhatsAppAccount

- (const char *)protocolPlugin
{
	return "prpl-hehoe-whatsmeow";
}

/* purple-gowhatsapp expects the username as a bare international number
 * with the @s.whatsapp.net domain. Let the user enter the natural
 * +49... form and derive the JID automatically. */
- (const char *)purpleAccountName
{
	NSString *userName = self.UID;

	if ([userName hasPrefix:@"+"]) {
		userName = [userName substringFromIndex:1];
	}
	if ([userName rangeOfString:@"@"].location == NSNotFound) {
		userName = [userName stringByAppendingString:@"@s.whatsapp.net"];
	}

	return [userName UTF8String];
}

/* There is no fixed server host whose reachability could be probed;
 * the plugin manages its own connectivity. Without this, the network
 * connectivity plugin keeps the account greyed out as "network offline". */
- (BOOL)connectivityBasedOnNetworkReachability
{
	return NO;
}

- (void)configurePurpleAccount
{
	[super configurePurpleAccount];

	NSNumber *ignoreStatus = [self preferenceForKey:KEY_WHATSAPP_IGNORE_STATUS group:GROUP_ACCOUNT_STATUS];
	purple_account_set_bool(account, "ignore-status-broadcast",
							(!ignoreStatus || [ignoreStatus boolValue]));

	/* Shown in WhatsApp's linked-devices list on the phone; the plugin's
	 * default is "purple-whatsmeow on <hostname>". */
	NSString *computerName = [[NSHost currentHost] localizedName];
	if (![computerName length]) computerName = [[NSProcessInfo processInfo] hostName];
	purple_account_set_string(account, "device-name",
							  [[NSString stringWithFormat:@"Adium on %@", computerName] UTF8String]);
}

@end
