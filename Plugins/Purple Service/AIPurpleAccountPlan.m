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

#import "AIPurpleAccountPlan.h"
#import "CBPurpleAccount.h"

#import <Adium/AIAccount.h>
#import <Adium/AIService.h>
#import <AIUtilities/AIStringUtilities.h>

#import <libpurple/libpurple.h>
#import <libpurple/accountopt.h>

@interface AIPurpleAccountPlan ()
- (PurplePluginProtocolInfo *)protocolInfo;
- (PurpleAccountOption *)optionForSetting:(NSString *)setting;
- (AIAccountPlanField *)fieldForSetting:(NSString *)setting;
- (NSString *)legacyKeyForSetting:(NSString *)setting;
- (NSArray *)declaredSettings;
@end

@implementation AIPurpleAccountPlan

/*!
 * @brief What the file next to this class says about a protocol
 *
 * A protocol without one gets every option it declares, which is what makes a service bindable
 * without writing anything at all.
 */
+ (NSDictionary *)descriptionForProtocol:(NSString *)protocol
{
	if (![protocol length])
		return nil;

	NSString *path = [[NSBundle bundleForClass:[AIPurpleAccountPlan class]] pathForResource:protocol ofType:@"json"];
	if (!path)
		return nil;

	NSError *error = nil;
	id parsed = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path]
												options:0
												  error:&error];

	if (![parsed isKindOfClass:[NSDictionary class]]) {
		NSLog(@"Account plan for %@ could not be read: %@", protocol, error);
		return nil;
	}

	return parsed;
}

+ (AIAccountPlan *)planForAccount:(AIAccount *)account
{
	NSString *protocol = [NSString stringWithUTF8String:[(CBPurpleAccount *)account protocolPlugin]];
	NSDictionary *fromFile = [self descriptionForProtocol:protocol];
	Class planClass = [AIPurpleAccountPlan class];

	NSString *className = [fromFile objectForKey:@"class"];
	if ([className length]) {
		Class named = NSClassFromString(className);

		if (named && [named isSubclassOfClass:[AIPurpleAccountPlan class]])
			planClass = named;
		else
			NSLog(@"Account plan for %@ names %@, which is not a plan class", protocol, className);
	}

	return [[[planClass alloc] initWithAccount:account] autorelease];
}

- (id)initWithAccount:(AIAccount *)inAccount
{
	if ((self = [super initWithAccount:inAccount]))
		description = [[AIPurpleAccountPlan descriptionForProtocol:
							[NSString stringWithUTF8String:[self protocolPlugin]]] retain];

	return self;
}

- (void)dealloc
{
	[description release];

	[super dealloc];
}

- (const char *)protocolPlugin
{
	return [(CBPurpleAccount *)[self account] protocolPlugin];
}

- (PurplePluginProtocolInfo *)protocolInfo
{
	PurplePlugin *prpl = purple_plugins_find_with_id([self protocolPlugin]);

	return (prpl && prpl->info) ? PURPLE_PLUGIN_PROTOCOL_INFO(prpl) : NULL;
}

- (NSString *)preferenceKeyForSetting:(NSString *)setting
{
	return [NSString stringWithFormat:@"%s:%@", [self protocolPlugin], setting];
}

//What the protocol says -------------------------------------------------------------------------
#pragma mark What the protocol says

- (NSArray *)declaredSettings
{
	PurplePluginProtocolInfo *info = [self protocolInfo];
	NSMutableArray *settings = [NSMutableArray array];

	if (!info)
		return settings;

	for (GList *iter = info->protocol_options; iter; iter = iter->next) {
		PurpleAccountOption *option = iter->data;
		const char *setting = option ? purple_account_option_get_setting(option) : NULL;

		if (setting)
			[settings addObject:[NSString stringWithUTF8String:setting]];
	}

	return settings;
}

- (PurpleAccountOption *)optionForSetting:(NSString *)setting
{
	PurplePluginProtocolInfo *info = [self protocolInfo];
	if (!info)
		return NULL;

	for (GList *iter = info->protocol_options; iter; iter = iter->next) {
		PurpleAccountOption *option = iter->data;
		const char *name = option ? purple_account_option_get_setting(option) : NULL;

		if (name && [setting isEqualToString:[NSString stringWithUTF8String:name]])
			return option;
	}

	return NULL;
}

- (BOOL)offersPassword
{
	NSNumber *fromFile = [[description objectForKey:@"account"] objectForKey:@"password"];
	if (fromFile)
		return [fromFile boolValue];

	/* A protocol that authenticates by its own means, which all the newer ones do, says so through
	 * OPT_PROTO_NO_PASSWORD. Asking it beats each of them stating the same thing in code. */
	PurplePluginProtocolInfo *info = [self protocolInfo];

	return info ? !(info->options & OPT_PROTO_NO_PASSWORD) : [super offersPassword];
}

- (BOOL)offersReadReceipts
{
	NSNumber *fromFile = [[description objectForKey:@"privacy"] objectForKey:@"readReceipts"];

	return fromFile ? [fromFile boolValue] : [super offersReadReceipts];
}

- (id)defaultForOption:(NSString *)setting
{
	/* What the other side lists this link as. Every protocol that asks for one names it the same way,
	 * and each of them puts its own name there, which is not what a person recognises in their list of
	 * linked devices. */
	if ([setting isEqualToString:@"device-name"]) {
		NSString *machine = [[NSHost currentHost] localizedName];
		if (![machine length])
			machine = [[NSProcessInfo processInfo] hostName];

		return [NSString stringWithFormat:AILocalizedString(@"Adium on %@", "Name this computer gives itself in another device's list of linked devices. %@ is the computer's name."), machine];
	}

	return nil;
}

- (void)migrateLegacy
{
	//Nothing that a key mapping cannot express
}

- (NSString *)legacyKeyForSetting:(NSString *)setting
{
	NSDictionary *legacy = [description objectForKey:@"legacy"];

	for (NSString *oldKey in legacy) {
		if ([[legacy objectForKey:oldKey] isEqualToString:setting])
			return oldKey;
	}

	return nil;
}

//The rows ---------------------------------------------------------------------------------------
#pragma mark The rows

/*!
 * @brief One option of the protocol, as a field
 *
 * Everything but the placement comes from the protocol itself, which is why naming an option is all a
 * file has to do.
 */
- (AIAccountPlanField *)fieldForSetting:(NSString *)setting
{
	PurpleAccountOption *option = [self optionForSetting:setting];
	if (!option)
		return nil;

	NSString *name = [NSString stringWithFormat:@"option:%@", setting];
	AIAccountPlanField *field = nil;

	switch (purple_account_option_get_type(option)) {
		case PURPLE_PREF_BOOLEAN:
			field = [AIAccountPlanField fieldNamed:name kind:AIAccountFieldSwitch];
			[field setDefaultValue:[NSNumber numberWithBool:purple_account_option_get_default_bool(option)]];
			break;

		case PURPLE_PREF_INT:
			field = [AIAccountPlanField fieldNamed:name kind:AIAccountFieldNumber];
			[field setDefaultValue:[NSNumber numberWithInt:purple_account_option_get_default_int(option)]];
			break;

		case PURPLE_PREF_STRING:
		case PURPLE_PREF_PATH: {
			const char *fallback = purple_account_option_get_default_string(option);

			field = [AIAccountPlanField fieldNamed:name kind:AIAccountFieldText];

			if (fallback && *fallback)
				[field setDefaultValue:[NSString stringWithUTF8String:fallback]];

			break;
		}

		case PURPLE_PREF_STRING_LIST: {
			NSMutableArray *titles = [NSMutableArray array];
			NSMutableArray *values = [NSMutableArray array];

			for (GList *entry = purple_account_option_get_list(option); entry; entry = entry->next) {
				PurpleKeyValuePair *pair = entry->data;
				if (!pair || !pair->key)
					continue;

				[titles addObject:[NSString stringWithUTF8String:pair->key]];
				[values addObject:(pair->value ? [NSString stringWithUTF8String:(const char *)pair->value] : @"")];
			}

			if (![titles count])
				return nil;

			const char *fallback = purple_account_option_get_default_list_value(option);

			field = [AIAccountPlanField fieldNamed:name kind:AIAccountFieldChoice];
			[field setChoiceTitles:titles];
			[field setChoiceValues:values];

			if (fallback)
				[field setDefaultValue:[NSString stringWithUTF8String:fallback]];

			break;
		}

		default:
			//A type nothing here knows how to show is left out rather than shown wrongly
			return nil;
	}

	const char *text = purple_account_option_get_text(option);

	//Its own name if it has one. A protocol that names nothing gets the setting, which is at least true
	[field setLabel:((text && *text) ? [NSString stringWithUTF8String:text] : setting)];
	[field setStore:AIAccountFieldStorePreference];
	[field setPreferenceKey:[self preferenceKeyForSetting:setting]];
	[field setLegacyKey:[self legacyKeyForSetting:setting]];

	id computed = [self defaultForOption:setting];
	if (computed)
		[field setDefaultValue:computed];

	[self refineField:field forSetting:setting];

	return field;
}

- (void)refineField:(AIAccountPlanField *)field forSetting:(NSString *)setting
{
	//A protocol that words its options well needs nothing here, and most of them do
}

- (void)describe
{
	//Before any row is built, or a row would show a default where a migrated value belongs
	[self migrateLegacy];

	[super describe];

	NSDictionary *accountSection = [description objectForKey:@"account"];
	NSArray *declared = [self declaredSettings];
	NSMutableSet *placed = [NSMutableSet set];


	/* Adium asks for the server and the port itself and hands both to the protocol under exactly these
	 * names, so a row built from the protocol would be a second field for one setting. */
	id wantsServer = [accountSection objectForKey:@"server"];
	BOOL serverInAccountName = [wantsServer isKindOfClass:[NSString class]] &&
							   [wantsServer isEqualToString:@"inAccountName"];

	if (serverInAccountName || (wantsServer ? [wantsServer boolValue] : [declared containsObject:@"server"])) {
		AIAccountPlanField *server = [AIAccountPlanField fieldNamed:@"server" kind:AIAccountFieldText];

		[server setStore:AIAccountFieldStorePreference];
		[server setPreferenceKey:KEY_CONNECT_HOST];
		[server setLabel:AILocalizedString(@"Server", nil)];
		[self addField:server toCard:AIAccountCardAccount];
	}

	[placed addObject:@"server"];

	id wantsPort = [accountSection objectForKey:@"port"];

	if (wantsPort ? [wantsPort boolValue] : [declared containsObject:@"port"]) {
		AIAccountPlanField *port = [AIAccountPlanField fieldNamed:@"port" kind:AIAccountFieldNumber];
		PurpleAccountOption *declaredPort = [self optionForSetting:@"port"];

		[port setStore:AIAccountFieldStorePreference];
		[port setPreferenceKey:KEY_CONNECT_PORT];
		[port setLabel:AILocalizedString(@"Port", nil)];

		//Empty means the protocol's own port, so say which one that is rather than leaving it blank
		if (declaredPort)
			[port setPlaceholder:[NSString stringWithFormat:@"%d", purple_account_option_get_default_int(declaredPort)]];

		[self addField:port toCard:AIAccountCardAccount];
	}

	[placed addObject:@"port"];

	/* Adium's own, not any protocol's: a list of commands sent as soon as the connection is up.
	 * CBPurpleAccount runs them through libpurple's command registry, so any protocol that registers
	 * commands can have them, and the file says which ones should offer it. */
	if ([[description objectForKey:@"commandsOnConnect"] boolValue]) {
		AIAccountPlanField *commands = [AIAccountPlanField fieldNamed:@"connectCommands"
																 kind:AIAccountFieldMultiline];

		[commands setStore:AIAccountFieldStorePreference];
		[commands setPreferenceKey:KEY_CONNECT_COMMANDS];
		[commands setLegacyKey:@"IRC:Commands"];
		[commands setLabel:AILocalizedString(@"Execute commands on connect", nil)];
		[commands setDetail:AILocalizedString(@"One per line, without the leading slash.",
											  "Explains how the commands sent after connecting are written")];

		[self addField:commands toCard:AIAccountCardOptions];
	}

	//What the file puts in front of a person, in the order it names them
	for (NSString *setting in [accountSection objectForKey:@"options"]) {
		[self addField:[self fieldForSetting:setting] toCard:AIAccountCardAccount];
		[placed addObject:setting];
	}

	for (NSString *setting in [description objectForKey:@"options"]) {
		[self addField:[self fieldForSetting:setting] toCard:AIAccountCardOptions];
		[placed addObject:setting];
	}

	[placed addObjectsFromArray:[description objectForKey:@"hidden"]];

	/* And everything the file does not mention, so that an option a protocol gains in an update is
	 * offered rather than silently dropped. */
	for (NSString *setting in declared) {
		if ([placed containsObject:setting])
			continue;

		/* Always behind the row, never in among the ones somebody chose. A protocol declares as many
		 * options as it likes and names them for itself, and meeting a dozen of those first is what
		 * the page is arranged to prevent. A protocol nobody has curated at all therefore shows the
		 * fields every account has and one row leading to the rest. */
		[self addField:[self fieldForSetting:setting] toCard:AIAccountCardMore];
	}
}

@end
