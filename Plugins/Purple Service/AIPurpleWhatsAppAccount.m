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
#import <Adium/AIChat.h>
#import <Adium/AIContentMessage.h>
#import <Adium/AIListContact.h>
#import <Adium/ESFileTransfer.h>
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

/* A contact who never set a profile name gives the alias nothing to show, and
 * the display fallback chain ends at the raw JID, so a nameless business
 * account was headed 4917...@s.whatsapp.net. Give every number@s.whatsapp.net
 * contact its phone number in international notation as the formatted UID;
 * any name from the server still wins, this only replaces the bare-JID
 * fallback. Lids stay untouched: their digits are not a phone number. */
- (AIListContact *)contactWithUID:(NSString *)sourceUID
{
	AIListContact *contact = [super contactWithUID:sourceUID];

	if (![contact valueForProperty:KEY_FORMATTED_UID]) {
		NSString *UID = contact.UID;
		if ([UID hasSuffix:@"@s.whatsapp.net"]) {
			NSString *number = [UID substringToIndex:(UID.length - @"@s.whatsapp.net".length)];
			if (number.length &&
				[number rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound) {
				[contact setFormattedUID:[@"+" stringByAppendingString:number] notify:NotifyLater];
			}
		}
	}

	return contact;
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

	NSString *pictures = [self preferenceForKey:KEY_WHATSAPP_PROFILE_PICTURES group:GROUP_ACCOUNT_STATUS];
	purple_account_set_string(account, "get-icons",
							  [(pictures ?: @"original") UTF8String]);

	/* Shown in WhatsApp's linked-devices list on the phone; the plugin's
	 * default is "purple-whatsmeow on <hostname>". */
	NSString *computerName = [[NSHost currentHost] localizedName];
	if (![computerName length]) computerName = [[NSProcessInfo processInfo] hostName];
	purple_account_set_string(account, "device-name",
							  [[NSString stringWithFormat:@"Adium on %@", computerName] UTF8String]);
}

/* With the fetch-history option set, the phone supplies the messages before an
 * opening conversation, complete with their ids, ticks and reactions. Adium's
 * own transcript excerpt would repeat those lines without any of that, so it
 * steps aside. */
- (BOOL)providesConversationHistory
{
	return account && purple_account_get_int(account, "fetch-history-on-open", 0) > 0;
}

/* Adopt the WhatsApp profile name as this account's display name, so outgoing
 * messages show it instead of the bare phone number. The plugin stores it as an
 * account string once the contact sync delivers it; the user's own display-name
 * preference always wins. */
- (void)didConnect
{
	[super didConnect];
	[self performSelector:@selector(ai_adoptWhatsAppProfileName) withObject:nil afterDelay:8.0];
	[self performSelector:@selector(ai_adoptWhatsAppProfileName) withObject:nil afterDelay:25.0];
}

- (void)ai_adoptWhatsAppProfileName
{
	if (!account) return;

	const char *selfName = purple_account_get_string(account, "self-display-name", NULL);
	if (!selfName || !*selfName) return;

	NSData *existingPreference = [self preferenceForKey:KEY_ACCOUNT_DISPLAY_NAME group:GROUP_ACCOUNT_STATUS];
	if (existingPreference) return;

	[self setDisplayName:[NSString stringWithUTF8String:selfName]];
}

/* The plugin echoes every outgoing group message back (including those sent
 * from other devices such as the phone). Returning NO makes Adium display the
 * echoes instead of its local copy, so phone-sent messages appear too. */
- (BOOL)shouldDisplayOutgoingMUCMessages
{
	return NO;
}

/* Localize the plugin's fixed English system messages before display */
- (void)receivedEventForChat:(AIChat *)chat
					 message:(NSString *)message
						date:(NSDate *)date
					   flags:(NSNumber *)flagsNumber
{
	static NSDictionary *localizedPluginMessages = nil;
	if (!localizedPluginMessages) {
		localizedPluginMessages = [[NSDictionary alloc] initWithObjectsAndKeys:
			AILocalizedString(@"This contact is trying to call you. Adium does not support WhatsApp calls.", "WhatsApp call event"),
			@"This contact is trying to call you. Adium does not support WhatsApp calls.",
			AILocalizedString(@"This contact is calling you. Adium does not support WhatsApp calls.", "WhatsApp call event"),
			@"This contact is calling you. Adium does not support WhatsApp calls.",
			nil];
	}
	NSString *localized = [localizedPluginMessages objectForKey:message];
	[super receivedEventForChat:chat message:(localized ? localized : message) date:date flags:flagsNumber];
}

/* WhatsApp channels ("Updates" tab) arrive from JIDs ending in @newsletter.
 * Drop their posts when the account option asks for it, like status broadcasts. */
- (void)receivedIMChatMessage:(NSDictionary *)messageDict inChat:(AIChat *)chat
{
	if ([chat.listObject.UID hasSuffix:@"@newsletter"]) {
		NSNumber *ignoreNewsletters = [self preferenceForKey:@"WhatsApp:Ignore Newsletters"
													   group:GROUP_ACCOUNT_STATUS];
		if (!ignoreNewsletters || [ignoreNewsletters boolValue])
			return;
	}
	[super receivedIMChatMessage:messageDict inChat:chat];
}

/* The libpurple contract the prpl builds on is HTML: glue/send_message.c runs
 * purple_markup_strip_html over every outgoing text. Adium encodes outgoing
 * text raw, so a literal "<" swallowed everything up to the next ">" on the
 * wire and newlines arrived flattened to spaces. Escape into exactly the HTML
 * that strip inverts: entities for the three metacharacters, <br> for line
 * breaks. */
static NSString *escapedForWhatsAppWire(NSString *text)
{
	NSMutableString *escaped = [[text mutableCopy] autorelease];

	[escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:NSLiteralSearch range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:NSLiteralSearch range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:NSLiteralSearch range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@"\r\n" withString:@"<br>" options:NSLiteralSearch range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@"\n" withString:@"<br>" options:NSLiteralSearch range:NSMakeRange(0, escaped.length)];
	[escaped replaceOccurrencesOfString:@"\r" withString:@"<br>" options:NSLiteralSearch range:NSMakeRange(0, escaped.length)];

	return escaped;
}

/* A reply armed in the message view rides in front of the escaped text as the
 * prpl's "?reply <id> " command, added here at the purple boundary so that
 * neither the entry field nor the displayed message ever contain it. The prpl
 * resolves the id against its cache, strips the command, and sends the rest
 * with the quote attached. Armed state is one send long, whatever that send
 * turns out to be. */
- (NSString *)encodedAttributedStringForSendingContentMessage:(AIContentMessage *)inContentMessage
{
	NSString	*encoded = [super encodedAttributedStringForSendingContentMessage:inContentMessage];
	AIChat		*chat = inContentMessage.chat;
	NSString	*token = [chat valueForProperty:@"PendingReplyToken"];

	if ([encoded length]) {
		encoded = escapedForWhatsAppWire(encoded);
	}

	if ([token length]) {
		/* A token with whitespace would shift the command's parts; ids never
		 * carry any, so refusing is purely defensive. An OTR-encrypted chat
		 * gets no prefix either (the menu no longer offers one there): the
		 * encryptor runs after this and would seal the command into the
		 * ciphertext, where the prpl cannot strip it and the recipient would
		 * read it as literal text. */
		if ([encoded length] && !chat.isSecure &&
			[token rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location == NSNotFound) {
			encoded = [NSString stringWithFormat:@"?reply %@ %@", token, encoded];
		}
		[chat setValue:nil forProperty:@"PendingReplyToken" notify:NotifyNever];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"AIChatPendingReplyConsumed" object:chat];
	}

	return encoded;
}

/* WhatsApp is store-and-forward: files can be sent regardless of the contact's
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
