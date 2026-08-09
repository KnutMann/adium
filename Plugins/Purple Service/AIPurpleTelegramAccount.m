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

#import "AIPurpleTelegramAccount.h"
#import <Adium/ESFileTransfer.h>

@implementation AIPurpleTelegramAccount

- (const char *)protocolPlugin
{
	return "telegram-tdlib";
}

/* There is no fixed server host whose reachability could be probed;
 * the plugin manages its own connectivity. Without this, the network
 * connectivity plugin keeps the account greyed out as "network offline". */
- (BOOL)connectivityBasedOnNetworkReachability
{
	return NO;
}

/* Telegram is store-and-forward: files can be sent regardless of the contact's
 * apparent presence. Presence data is sparse on this network, so most contacts
 * look offline even though they can receive media just fine. */
- (BOOL)availableForSendingContentType:(NSString *)inType toContact:(AIListContact *)inContact
{
	if ([inType isEqualToString:CONTENT_FILE_TRANSFER_TYPE]) {
		return (self.online &&
				[self conformsToProtocol:@protocol(AIAccount_Files)] &&
				(!inContact || [self allowFileTransferWithListObject:inContact]));
	}
	return [super availableForSendingContentType:inType toContact:inContact];
}

@end
