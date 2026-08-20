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
#import "AIIRCConsoleController.h"

#import <Adium/AIListContact.h>
#import <Adium/ESFileTransfer.h>

@implementation AIPurpleGenericAccount

- (void)dealloc
{
	[consoleController close];
	[consoleController release];
	consoleController = nil;

	[super dealloc];
}

- (const char *)protocolPlugin
{
	return [(AIPurpleGenericService *)self.service prplIDCString];
}

#pragma mark Server console

/*!
 * @brief Does this account get the raw IRC server console?
 *
 * Only the IRCv3 protocol among the descriptor-bound ones speaks a line
 * protocol and emits the irc-sending-text/irc-receiving-text pair the console
 * listens on. Enabled for debug builds, otherwise behind the same hidden
 * default the built-in IRC uses.
 */
- (BOOL)enableConsole
{
	const char *prplID = [self protocolPlugin];

	if (!prplID || strcmp(prplID, "prpl-eionrobb-ircv3") != 0)
		return NO;

#ifdef DEBUG_BUILD
	return YES;
#else
	return [[NSUserDefaults standardUserDefaults] boolForKey:@"AIIRCConsole"];
#endif
}

- (IBAction)showConsole:(id)sender
{
	if (consoleController)
		[consoleController showWindow:sender];
	else
		NSBeep();
}

- (NSArray *)accountActionMenuItems
{
	NSArray *superItems = [super accountActionMenuItems];

	if (![self enableConsole])
		return superItems;

	NSMenuItem *consoleMenuItem = [[[NSMenuItem alloc] initWithTitle:AILocalizedString(@"Console", nil)
															  action:@selector(showConsole:)
													   keyEquivalent:@""] autorelease];
	[consoleMenuItem setTarget:self];

	NSMutableArray *items = [NSMutableArray arrayWithObject:consoleMenuItem];
	if (superItems) [items addObjectsFromArray:superItems];

	return items;
}

- (void)didConnect
{
	[super didConnect];

	if ([self enableConsole]) {
		if (!consoleController) consoleController = [[AIIRCConsoleController alloc] init];
		[consoleController setPurpleConnection:purple_account_get_connection(account)];
	}
}

- (void)didDisconnect
{
	[consoleController setPurpleConnection:NULL];

	[super didDisconnect];
}

/*!
 * @brief The name libpurple knows this account by
 *
 * Normally the formatted UID, which is what a service that formats addresses wants. A protocol whose
 * account name is a name rather than an address wants the name the user typed and nothing else: the
 * formatted one carries whatever the protocol reported about itself on the last connection, which is
 * a different string and files the account's message store somewhere else.
 *
 * IRC and its like carry the server here instead of in an option, so for those the name is the nick
 * and the server together. A server that is not set yet leaves the name alone rather than spelling
 * out that it is missing.
 */
- (const char *)purpleAccountName
{
	AIPurpleGenericService *service = (AIPurpleGenericService *)self.service;

	if ([[service descriptorValueForKey:@"AccountNameFromUID"] boolValue])
		return [self.UID UTF8String];

	if ([[service descriptorValueForKey:@"AccountNameIncludesHost"] boolValue] && self.host.length)
		return [[NSString stringWithFormat:@"%@@%@", self.formattedUID, self.host] UTF8String];

	return [super purpleAccountName];
}

/*!
 * @brief Hand libpurple the account name again
 *
 * The name is fixed when the account is created, so a protocol carrying its server in that name would
 * keep connecting to the old one after the server field is changed.
 */
- (void)configurePurpleAccount
{
	[super configurePurpleAccount];

	if ([[(AIPurpleGenericService *)self.service descriptorValueForKey:@"AccountNameIncludesHost"] boolValue])
		purple_account_set_username(self.purpleAccount, self.purpleAccountName);
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

@end
