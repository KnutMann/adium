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

#import "AIPurpleSignalAccount.h"
#import <Adium/AIChat.h>
#import <Adium/AIListContact.h>
#import <Adium/ESFileTransfer.h>
#import "AISignalAccountViewController.h"

@implementation AIPurpleSignalAccount

- (const char *)protocolPlugin
{
	return "prpl-hehoe-presage";
}

/* The username is the Signal account UUID, passed straight through: presage
 * takes it verbatim and, on the first link, tells the user which one to use if
 * the placeholder was wrong. No JID or domain to derive, unlike WhatsApp. */
- (const char *)purpleAccountName
{
	return [self.UID UTF8String];
}

/* There is no fixed server host whose reachability could be probed; presage
 * manages its own connection to Signal. Without this, the network connectivity
 * plugin keeps the account greyed out as "network offline". */
- (BOOL)connectivityBasedOnNetworkReachability
{
	return NO;
}

/* presage echoes outgoing messages back, including those sent from the phone or
 * another linked device. Returning NO makes Adium display those echoes rather
 * than its own local copy, so messages sent elsewhere show up here too - the
 * same reason the WhatsApp account does it. */
- (BOOL)shouldDisplayOutgoingMUCMessages
{
	return NO;
}

/* Signal is store-and-forward and its presence data is sparse, so a contact who
 * can receive perfectly well usually looks offline. Allow file transfers anyway,
 * as the WhatsApp account does. */
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
