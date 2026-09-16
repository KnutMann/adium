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
 * @brief The account's own address, without a resource, or nil if it does not do OMEMO
 */
+ (NSString *)addressOf:(AIAccount *)account
{
	PurpleAccount *underneath = [self purpleAccountFor:account];
	if (!underneath) return nil;

	const char *username = purple_account_get_username(underneath);
	if (!username) return nil;

	NSString *own = [NSString stringWithUTF8String:username];
	NSRange slash = [own rangeOfString:@"/"];
	if (slash.location != NSNotFound) own = [own substringToIndex:slash.location];

	return [own lowercaseString];
}

/*!
 * @brief The store belonging to an account, making one if this account is to use OMEMO
 */
+ (AIOMEMOStore *)storeFor:(AIAccount *)account
{
	NSString *own = [self addressOf:account];
	return own ? [AIOMEMOStore storeForAccount:own] : nil;
}

/*!
 * @brief The store belonging to an account, ONLY if it already has one
 *
 * For the places that want to look rather than to use. Asking the other way round would give
 * every account an identity and a hundred keys the moment somebody opened a window.
 */
+ (AIOMEMOStore *)existingStoreFor:(AIAccount *)account
{
	NSString *own = [self addressOf:account];
	return (own && [AIOMEMOStore haveStoreForAccount:own]) ? [AIOMEMOStore storeForAccount:own] : nil;
}

+ (NSString *)ownFingerprintForAccount:(AIAccount *)account
{
	return [[self existingStoreFor:account] fingerprint];
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

#pragma mark Everything one account knows, for the settings

+ (BOOL)isPossibleForAccount:(AIAccount *)account
{
	return [self purpleAccountFor:account] != NULL;
}

+ (NSArray<NSDictionary *> *)devicesKnownToAccount:(AIAccount *)account
{
	/* The looking kind, not the making kind: merely opening a settings window should not give an
	 * account an identity it never asked for. */
	return [[self existingStoreFor:account] everyDeviceSeen] ?: @[];
}

+ (void)setTrust:(NSInteger)trust forFingerprint:(NSString *)fingerprint onAccount:(AIAccount *)account
{
	[[self existingStoreFor:account] setTrust:(AIOMEMOTrust)trust forFingerprint:fingerprint];
}

@end
