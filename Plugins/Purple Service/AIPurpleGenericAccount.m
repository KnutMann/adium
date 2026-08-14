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

#import "AIPurpleGenericAccount.h"
#import "AIPurpleGenericService.h"

#import <Adium/AIListContact.h>
#import <Adium/ESFileTransfer.h>

@implementation AIPurpleGenericAccount

- (const char *)protocolPlugin
{
	return [(AIPurpleGenericService *)self.service prplIDCString];
}

/*!
 * @brief Should this account be greyed out when the machine reports no network?
 *
 * A protocol that keeps its own connection, and the newer ones all do, has no fixed host whose
 * reachability means anything. Probing one it never contacts leaves the account permanently greyed
 * out as offline while it is in fact connected.
 */
- (BOOL)connectivityBasedOnNetworkReachability
{
	NSNumber *reachability = [(AIPurpleGenericService *)self.service descriptorValueForKey:@"NetworkReachability"];

	return reachability ? [reachability boolValue] : [super connectivityBasedOnNetworkReachability];
}

/*!
 * @brief May a file be sent to a contact who looks offline?
 *
 * On a store and forward network it may: the server holds it. Presence on those networks is sparse
 * enough that most contacts look offline whether they are or not, so asking after presence answers
 * the wrong question.
 */
- (BOOL)availableForSendingContentType:(NSString *)inType toContact:(AIListContact *)inContact
{
	if ([inType isEqualToString:CONTENT_FILE_TRANSFER_TYPE] &&
		[[(AIPurpleGenericService *)self.service descriptorValueForKey:@"OfflineFileTransfers"] boolValue]) {
		return (self.online &&
				[self conformsToProtocol:@protocol(AIAccount_Files)] &&
				(!inContact || [self allowFileTransferWithListObject:inContact]));
	}

	return [super availableForSendingContentType:inType toContact:inContact];
}

@end
