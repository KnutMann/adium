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

#import "AIPurpleGenericService.h"
#import "AIPurpleGenericAccount.h"
#import "PurpleAccountViewController.h"
#import "SLPurpleCocoaAdapter.h"

#import <Adium/AIStatusControllerProtocol.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIStringUtilities.h>

#import <libpurple/libpurple.h>

#define DESCRIPTORS_PLIST	@"AIPurpleServiceDescriptors"

@interface AIPurpleGenericService ()
- (id)initWithPrplID:(NSString *)inPrplID descriptor:(NSDictionary *)inDescriptor;
- (PurplePluginProtocolInfo *)protocolInfo;
@end

@implementation AIPurpleGenericService

+ (NSDictionary *)descriptors
{
	static NSDictionary *descriptors = nil;

	if (!descriptors) {
		NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:DESCRIPTORS_PLIST
																		  ofType:@"plist"];
		descriptors = [[NSDictionary alloc] initWithContentsOfFile:path];
	}

	return descriptors;
}

+ (void)registerServicesForLoadedProtocolsExcluding:(NSSet *)claimedPrplIDs
{
	NSDictionary *descriptors = [self descriptors];

	/* Only protocols that are actually loaded. A descriptor for a plugin that is not installed would
	 * otherwise offer an account nobody can connect. */
	for (GList *iter = purple_plugins_get_protocols(); iter; iter = iter->next) {
		PurplePlugin *prpl = iter->data;
		if (!prpl || !prpl->info || !prpl->info->id)
			continue;

		NSString *prplID = [NSString stringWithUTF8String:prpl->info->id];
		if ([claimedPrplIDs containsObject:prplID])
			continue;

		NSDictionary *descriptor = [descriptors objectForKey:prplID];
		if (!descriptor)
			continue;

		//Registers itself with the account controller from AIService's init
		[[[self alloc] initWithPrplID:prplID descriptor:descriptor] autorelease];
	}
}

- (id)initWithPrplID:(NSString *)inPrplID descriptor:(NSDictionary *)inDescriptor
{
	prplID = [inPrplID retain];
	prplIDCString = strdup([inPrplID UTF8String]);
	descriptor = [inDescriptor retain];

	/* Last, because AIService's init registers the service and asks it to register its statuses, by
	 * which time everything above has to be answerable. */
	return (self = [super init]);
}

- (void)dealloc
{
	[prplID release];
	[descriptor release];
	free(prplIDCString);

	[super dealloc];
}

- (const char *)prplIDCString
{
	return prplIDCString;
}

- (id)descriptorValueForKey:(NSString *)key
{
	return [descriptor objectForKey:key];
}

- (PurplePluginProtocolInfo *)protocolInfo
{
	PurplePlugin *prpl = purple_plugins_find_with_id(prplIDCString);

	return (prpl && prpl->info) ? PURPLE_PLUGIN_PROTOCOL_INFO(prpl) : NULL;
}

//Account creation -----------------------------------------------------------------------------------------------------
#pragma mark Account creation

- (Class)accountClass
{
	return [AIPurpleGenericAccount class];
}

- (AIAccountViewController *)accountViewController
{
	return [PurpleAccountViewController accountViewController];
}

- (DCJoinChatViewController *)joinChatView
{
	/* Nil until the generic join view exists. AIService's own answer is nil too, so a protocol with
	 * group chats simply has no join sheet yet rather than a broken one. */
	return nil;
}

//Description ----------------------------------------------------------------------------------------------------------
#pragma mark Description

- (NSString *)serviceCodeUniqueID
{
	return [descriptor objectForKey:@"ServiceCodeUniqueID"];
}

- (NSString *)serviceID
{
	return [descriptor objectForKey:@"ServiceID"];
}

- (NSString *)serviceClass
{
	return [descriptor objectForKey:@"ServiceClass"];
}

- (NSString *)shortDescription
{
	return [descriptor objectForKey:@"ShortDescription"];
}

- (NSString *)longDescription
{
	NSString *described = [descriptor objectForKey:@"LongDescription"];
	if (described)
		return described;

	/* What the plugin calls itself, which is what it tells every other client too. */
	PurplePlugin *prpl = purple_plugins_find_with_id(prplIDCString);
	if (prpl && prpl->info && prpl->info->name)
		return [NSString stringWithUTF8String:prpl->info->name];

	return [self shortDescription];
}

- (NSString *)userNameLabel
{
	NSString *label = [descriptor objectForKey:@"UserNameLabel"];

	/* Translated through the same table as everything else: the descriptor holds the English, which
	 * is the key. A label nobody has translated comes back unchanged, which is what would have
	 * happened with it written in the source too. */
	return label ? AILocalizedString(label, nil) : [super userNameLabel];
}

- (NSCharacterSet *)allowedCharacters
{
	NSString *allowed = [descriptor objectForKey:@"AllowedCharacters"];

	return allowed ? [NSCharacterSet characterSetWithCharactersInString:allowed] : [super allowedCharacters];
}

- (NSUInteger)allowedLength
{
	NSNumber *length = [descriptor objectForKey:@"AllowedLength"];

	return length ? [length unsignedIntegerValue] : [super allowedLength];
}

- (BOOL)caseSensitive
{
	NSNumber *sensitive = [descriptor objectForKey:@"CaseSensitive"];

	return sensitive ? [sensitive boolValue] : [super caseSensitive];
}

- (AIServiceImportance)serviceImportance
{
	return [[descriptor objectForKey:@"ServiceImportance"] isEqualToString:@"Primary"] ?
		AIServicePrimary : AIServiceSecondary;
}

//Asked of the protocol ------------------------------------------------------------------------------------------------
#pragma mark Asked of the protocol

/*!
 * @brief Does this protocol want a password?
 *
 * The protocol says so itself, and until now nothing asked. Telegram, Signal and WhatsApp all
 * authenticate by their own means and set this flag; every hand written service for them repeated
 * the answer in Objective-C.
 */
- (BOOL)supportsPassword
{
	PurplePluginProtocolInfo *info = [self protocolInfo];

	return info ? !(info->options & OPT_PROTO_NO_PASSWORD) : [super supportsPassword];
}

- (BOOL)requiresPassword
{
	PurplePluginProtocolInfo *info = [self protocolInfo];

	return info ? ((info->options & OPT_PROTO_PASSWORD_OPTIONAL) == 0 &&
				   (info->options & OPT_PROTO_NO_PASSWORD) == 0) : [super requiresPassword];
}

/*!
 * @brief Does this protocol have group chats?
 *
 * chat_info is what libpurple itself consults to decide whether a protocol can be asked to join a
 * room, so it is the same question asked of the same place.
 */
- (BOOL)canCreateGroupChats
{
	PurplePluginProtocolInfo *info = [self protocolInfo];

	return info ? (info->chat_info != NULL) : [super canCreateGroupChats];
}

- (BOOL)canRegisterNewAccounts
{
	PurplePluginProtocolInfo *info = [self protocolInfo];

	return info ? (info->register_user != NULL) : [super canRegisterNewAccounts];
}

//Icons ----------------------------------------------------------------------------------------------------------------
#pragma mark Icons

- (NSString *)iconNameOfType:(AIServiceIconType)iconType
{
	NSString *base = [descriptor objectForKey:@"IconBaseName"];

	return [base stringByAppendingString:((iconType == AIServiceIconSmall || iconType == AIServiceIconList) ?
										  @"-small" : @"-large")];
}

- (NSImage *)defaultServiceIconOfType:(AIServiceIconType)iconType
{
	return [NSImage imageNamed:[self iconNameOfType:iconType] forClass:[self class] loadLazily:YES];
}

- (NSString *)pathForDefaultServiceIconOfType:(AIServiceIconType)iconType
{
	return [[NSBundle bundleForClass:[self class]] pathForImageResource:[self iconNameOfType:iconType]];
}

//Statuses -------------------------------------------------------------------------------------------------------------
#pragma mark Statuses

/*!
 * @brief Available, away and offline
 *
 * Not derived from the protocol's own status types, which need a live account to ask for and whose
 * names would still have to be mapped onto Adium's by hand. This is the set every hand written
 * service in this bundle registers, character for character.
 */
- (void)registerStatuses
{
	[adium.statusController registerStatus:STATUS_NAME_AVAILABLE
						   withDescription:[adium.statusController localizedDescriptionForCoreStatusName:STATUS_NAME_AVAILABLE]
									ofType:AIAvailableStatusType
								forService:self];

	[adium.statusController registerStatus:STATUS_NAME_AWAY
						   withDescription:[adium.statusController localizedDescriptionForCoreStatusName:STATUS_NAME_AWAY]
									ofType:AIAwayStatusType
								forService:self];

	[adium.statusController registerStatus:STATUS_NAME_OFFLINE
						   withDescription:[adium.statusController localizedDescriptionForCoreStatusName:STATUS_NAME_OFFLINE]
									ofType:AIOfflineStatusType
								forService:self];
}

@end
