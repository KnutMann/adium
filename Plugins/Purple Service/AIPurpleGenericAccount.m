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
#import <libpurple/accountopt.h>
#import <Adium/ESFileTransfer.h>

@implementation AIPurpleGenericAccount

- (const char *)protocolPlugin
{
	return [(AIPurpleGenericService *)self.service prplIDCString];
}

/*!
 * @brief The name libpurple knows this account by
 *
 * Normally the formatted UID, which is what a service that formats addresses wants. A protocol whose
 * account name is a name rather than an address wants the name the user typed and nothing else: the
 * formatted one carries whatever the protocol reported about itself on the last connection, which is
 * a different string and files the account's message store somewhere else.
 */
- (const char *)purpleAccountName
{
	if ([[(AIPurpleGenericService *)self.service descriptorValueForKey:@"AccountNameFromUID"] boolValue])
		return [self.UID UTF8String];

	return [super purpleAccountName];
}

/*!
 * @brief Should Adium show its own copy of an outgoing group message?
 *
 * A protocol that echoes what was sent, including from the phone or another linked device, wants
 * Adium to display the echo rather than a local copy, or messages sent elsewhere never appear here.
 */
- (BOOL)shouldDisplayOutgoingMUCMessages
{
	NSNumber *echoes = [(AIPurpleGenericService *)self.service descriptorValueForKey:@"EchoesOutgoingMessages"];

	return echoes ? ![echoes boolValue] : [super shouldDisplayOutgoingMUCMessages];
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

/*!
 * @brief Hand the protocol its own options back
 *
 * Every option this protocol declared, read from where the account keeps it and written into the
 * libpurple account. Neither side had to be told which options exist: the protocol says so, and the
 * settings pane built its rows from the same list.
 */
- (void)configurePurpleAccount
{
	[super configurePurpleAccount];

	AIPurpleGenericService *service = (AIPurpleGenericService *)self.service;
	PurplePlugin *prpl = purple_plugins_find_with_id([service prplIDCString]);
	PurplePluginProtocolInfo *info = (prpl && prpl->info) ? PURPLE_PLUGIN_PROTOCOL_INFO(prpl) : NULL;
	if (!info)
		return;

	for (GList *iter = info->protocol_options; iter; iter = iter->next) {
		PurpleAccountOption *option = iter->data;
		const char *setting = option ? purple_account_option_get_setting(option) : NULL;
		if (!setting)
			continue;

		NSString *key = [NSString stringWithFormat:@"%s:%s", [service prplIDCString], setting];
		id stored = [self preferenceForKey:key group:GROUP_ACCOUNT_STATUS];

		/* Nothing stored means the user never touched it, and the protocol's own default is already
		 * in place. Writing it back would only turn a default that may change into a fixed value. */
		if (!stored)
			continue;

		switch (purple_account_option_get_type(option)) {
			case PURPLE_PREF_BOOLEAN:
				purple_account_set_bool(account, setting, [stored boolValue]);
				break;

			case PURPLE_PREF_INT:
				purple_account_set_int(account, setting, (int)[stored integerValue]);
				break;

			case PURPLE_PREF_STRING:
			case PURPLE_PREF_PATH:
			case PURPLE_PREF_STRING_LIST:
				purple_account_set_string(account, setting, [stored UTF8String]);
				break;

			default:
				break;
		}
	}
}

@end
