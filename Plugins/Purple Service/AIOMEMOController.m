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

#import "AIOMEMOController.h"
#import "AIOMEMOStore.h"
#import "adiumPurpleOMEMO.h"
#import "CBPurpleAccount.h"

#import <Adium/AIChat.h>
#import <Adium/AIAccount.h>
#import <Adium/AIListContact.h>

/*
 * The seam between the interface and everything underneath it.
 *
 * The encryption lives in libpurple's world of accounts and connections; the menu lives in
 * Adium's world of chats and contacts. Rather than teach either one about the other, the
 * translation happens here and nowhere else.
 */

@implementation AIOMEMOController

/*!
 * @brief The libpurple account behind an Adium one, if it is a jabber account at all
 */
+ (PurpleAccount *)purpleAccountFor:(AIAccount *)account
{
	if (![account isKindOfClass:[CBPurpleAccount class]]) return NULL;

	PurpleAccount *underneath = [(CBPurpleAccount *)account purpleAccount];
	if (!underneath) return NULL;

	if (!purple_strequal(purple_account_get_protocol_id(underneath), "prpl-jabber")) return NULL;

	return underneath;
}

/*!
 * @brief The two things every call here needs: whose account, and whose conversation
 */
+ (BOOL)account:(PurpleAccount **)account andContact:(NSString **)contact inChat:(AIChat *)chat
{
	if (!chat || chat.isGroupChat) return NO;

	AIListContact *who = chat.listObject;
	if (!who) return NO;

	PurpleAccount *underneath = [self purpleAccountFor:chat.account];
	if (!underneath) return NO;

	if (account) *account = underneath;
	if (contact) *contact = who.UID;
	return YES;
}

+ (BOOL)isPossibleInChat:(AIChat *)chat
{
	return [self account:NULL andContact:NULL inChat:chat];
}

+ (BOOL)isEncryptingChat:(AIChat *)chat
{
	PurpleAccount *account = NULL;
	NSString *contact = nil;
	if (![self account:&account andContact:&contact inChat:chat]) return NO;

	return omemoIsEncryptingWith(account, contact);
}

+ (BOOL)isReadyInChat:(AIChat *)chat
{
	PurpleAccount *account = NULL;
	NSString *contact = nil;
	if (![self account:&account andContact:&contact inChat:chat]) return NO;

	return omemoIsReadyFor(account, contact);
}

+ (void)setEncrypting:(BOOL)encrypting inChat:(AIChat *)chat
{
	PurpleAccount *account = NULL;
	NSString *contact = nil;
	if (![self account:&account andContact:&contact inChat:chat]) return;

	omemoSetEncrypting(account, contact, encrypting);
}

#pragma mark Fingerprints

/*!
 * @brief The store belonging to an account, without making one for an account that has none
 */
+ (AIOMEMOStore *)storeFor:(AIAccount *)account
{
	PurpleAccount *underneath = [self purpleAccountFor:account];
	if (!underneath) return nil;

	const char *username = purple_account_get_username(underneath);
	if (!username) return nil;

	NSString *own = [NSString stringWithUTF8String:username];
	NSRange slash = [own rangeOfString:@"/"];
	if (slash.location != NSNotFound) own = [own substringToIndex:slash.location];

	return [AIOMEMOStore storeForAccount:[own lowercaseString]];
}

+ (NSString *)ownFingerprintForAccount:(AIAccount *)account
{
	return [[self storeFor:account] fingerprint];
}

+ (NSDictionary<NSString *, NSNumber *> *)fingerprintsInChat:(AIChat *)chat
{
	if (![self isPossibleInChat:chat]) return @{};

	AIOMEMOStore *store = [self storeFor:chat.account];
	return [store fingerprintsForJID:[chat.listObject.UID lowercaseString]] ?: @{};
}

+ (void)setAccepted:(BOOL)accepted forFingerprint:(NSString *)fingerprint inChat:(AIChat *)chat
{
	AIOMEMOStore *store = [self storeFor:chat.account];

	[store setTrust:(accepted ? AIOMEMOTrustAccepted : AIOMEMOTrustRejected)
	 forFingerprint:fingerprint];
}

@end
