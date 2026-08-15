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

#import "AIPurpleGenericAccountViewController.h"
#import "AIPurpleGenericService.h"

#import <Adium/AIAccount.h>
#import <Adium/AISettingsFormView.h>
#import <AIUtilities/AIStringUtilities.h>

#import <libpurple/libpurple.h>
#import <libpurple/accountopt.h>

@interface AIPurpleGenericAccountViewController ()
- (NSString *)preferenceKeyForSetting:(const char *)setting;
- (void)optionSwitchChanged:(id)sender;
- (void)optionFieldChanged:(id)sender;
- (void)optionMenuChanged:(id)sender;
@end

@implementation AIPurpleGenericAccountViewController

- (void)configureForAccount:(AIAccount *)inAccount
{
	[super configureForAccount:inAccount];

	AIPurpleGenericService *service = (AIPurpleGenericService *)inAccount.service;
	if (![service isKindOfClass:[AIPurpleGenericService class]])
		return;

	/* A protocol that authenticates by its own means, which all the newer ones do, says so through
	 * OPT_PROTO_NO_PASSWORD. Asking it beats three services each stating the same thing in code. */
	if (![service supportsPassword]) {
		[label_password setHidden:YES];
		[textField_password setHidden:YES];
	}

	/* And a protocol that connects wherever it likes declares no server or port for anyone to set.
	 * Pidgin builds its whole account dialog out of these options; this reads two of them. */
	if (![service protocolHasOption:@"server"]) {
		[label_server setHidden:YES];
		[textField_connectHost setHidden:YES];
	}

	if (![service protocolHasOption:@"port"]) {
		[label_port setHidden:YES];
		[textField_connectPort setHidden:YES];
	}
}

//The protocol's own options -------------------------------------------------------------------------------------------
#pragma mark The protocol's own options

/*!
 * @brief Where one option's value is kept
 *
 * Namespaced by protocol, because two protocols naming a setting "server" mean two different servers
 * and an account belongs to one of them.
 */
- (NSString *)preferenceKeyForSetting:(const char *)setting
{
	AIPurpleGenericService *service = (AIPurpleGenericService *)[account service];

	return [NSString stringWithFormat:@"%s:%s", [service prplIDCString], setting];
}

- (BOOL)hasProtocolOptions
{
	AIPurpleGenericService *service = (AIPurpleGenericService *)[account service];
	if (![service isKindOfClass:[AIPurpleGenericService class]])
		return NO;

	PurplePlugin *prpl = purple_plugins_find_with_id([service prplIDCString]);
	PurplePluginProtocolInfo *info = (prpl && prpl->info) ? PURPLE_PLUGIN_PROTOCOL_INFO(prpl) : NULL;

	return (info && info->protocol_options != NULL);
}

- (void)addOptionRowsToForm:(AISettingsFormView *)form
{
	AIPurpleGenericService *service = (AIPurpleGenericService *)[account service];
	if (![service isKindOfClass:[AIPurpleGenericService class]])
		return;

	PurplePlugin *prpl = purple_plugins_find_with_id([service prplIDCString]);
	PurplePluginProtocolInfo *info = (prpl && prpl->info) ? PURPLE_PLUGIN_PROTOCOL_INFO(prpl) : NULL;
	if (!info)
		return;

	for (GList *iter = info->protocol_options; iter; iter = iter->next) {
		PurpleAccountOption *option = iter->data;
		if (!option)
			continue;

		const char *setting = purple_account_option_get_setting(option);
		if (!setting)
			continue;

		const char *text = purple_account_option_get_text(option);

		/* Its own label if it has one. A protocol which names an option and nothing else gets the
		 * setting name, which is at least the truth. */
		NSString *label = (text && *text) ? [NSString stringWithUTF8String:text]
										  : [NSString stringWithUTF8String:setting];
		NSString *key = [self preferenceKeyForSetting:setting];
		id stored = [account preferenceForKey:key group:GROUP_ACCOUNT_STATUS];

		switch (purple_account_option_get_type(option)) {
			case PURPLE_PREF_BOOLEAN: {
				NSSwitch *control = [AISettingsFormView switchWithTarget:self action:@selector(optionSwitchChanged:)];
				BOOL on = stored ? [stored boolValue] : purple_account_option_get_default_bool(option);

				[control setState:(on ? NSControlStateValueOn : NSControlStateValueOff)];
				[control setIdentifier:key];
				[form addRowWithLabel:label control:control];
				break;
			}

			case PURPLE_PREF_INT: {
				NSTextField *control = [AISettingsFormView valueFieldWithWidth:70.0f
																	   target:self
																	   action:@selector(optionFieldChanged:)];

				[control setIntegerValue:(stored ? [stored integerValue] : purple_account_option_get_default_int(option))];
				[control setIdentifier:key];
				[form addRowWithLabel:label control:control];
				break;
			}

			case PURPLE_PREF_STRING:
			case PURPLE_PREF_PATH: {
				const char *fallback = purple_account_option_get_default_string(option);
				NSTextField *control = [AISettingsFormView textFieldWithTarget:self action:@selector(optionFieldChanged:)];

				[control setStringValue:(stored ? stored : (fallback ? [NSString stringWithUTF8String:fallback] : @""))];
				[control setIdentifier:key];
				[form addRowWithLabel:label control:control];
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
					break;

				NSPopUpButton *control = [AISettingsFormView popUpButtonWithTitles:titles
																		   target:self
																		   action:@selector(optionMenuChanged:)];

				//The menu shows what a person reads; what is stored is what the protocol wants
				for (NSUInteger i = 0; i < [titles count]; i++)
					[[control itemAtIndex:i] setRepresentedObject:[values objectAtIndex:i]];

				const char *fallback = purple_account_option_get_default_list_value(option);
				NSString *current = stored ? stored : (fallback ? [NSString stringWithUTF8String:fallback] : nil);
				NSUInteger index = (current ? [values indexOfObject:current] : NSNotFound);
				if (index != NSNotFound)
					[control selectItemAtIndex:(NSInteger)index];

				[control setIdentifier:key];
				[form addRowWithLabel:label control:control];
				break;
			}

			default:
				//A type nothing here knows how to show is left out rather than shown wrongly
				break;
		}
	}
}

//Written as they change: a settings pane has no OK to wait for
- (void)optionSwitchChanged:(id)sender
{
	[account setPreference:[NSNumber numberWithBool:([sender state] == NSControlStateValueOn)]
					forKey:[sender identifier]
					 group:GROUP_ACCOUNT_STATUS];
}

- (void)optionFieldChanged:(id)sender
{
	[account setPreference:[sender stringValue]
					forKey:[sender identifier]
					 group:GROUP_ACCOUNT_STATUS];
}

- (void)optionMenuChanged:(id)sender
{
	[account setPreference:[[sender selectedItem] representedObject]
					forKey:[sender identifier]
					 group:GROUP_ACCOUNT_STATUS];
}

@end
