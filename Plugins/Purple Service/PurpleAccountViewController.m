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

#import "PurpleAccountViewController.h"
#import "CBPurpleAccount.h"

#import <Adium/AISettingsFormView.h>

#import <libpurple/libpurple.h>
#import <libpurple/accountopt.h>
#import <AIUtilities/AIMenuAdditions.h>

@interface PurpleAccountViewController()
- (void)addEncodingItemsWithNames:(NSArray *)inArray withTitle:(NSString *)inTitle toMenu:(NSMenu *)menu;
@end

@implementation PurpleAccountViewController

//Configure our controls
- (void)configureForAccount:(AIAccount *)inAccount
{
    [super configureForAccount:inAccount];
	
	[checkBox_broadcastMusic setState:[[account preferenceForKey:KEY_BROADCAST_MUSIC_INFO
														   group:GROUP_ACCOUNT_STATUS] boolValue]];
	
	
	[checkBox_displayCustomEmoticons setState:[[account preferenceForKey:KEY_DISPLAY_CUSTOM_EMOTICONS
																   group:GROUP_ACCOUNT_STATUS] boolValue]];
}

//Save controls
- (void)saveConfiguration
{
    [super saveConfiguration];

	/* Only what the user was actually shown. Of the services using this controller only Jabber's nib
	 * connects these two, so for every other one the state read here is the state of a nil outlet,
	 * which is zero, and writing it stores "off" for a setting nobody was offered. That was once per
	 * OK and rare enough to go unnoticed; it is about to happen on every change. */
	if (checkBox_broadcastMusic) {
		[account setPreference:[NSNumber numberWithBool:[checkBox_broadcastMusic state]]
						forKey:KEY_BROADCAST_MUSIC_INFO
						 group:GROUP_ACCOUNT_STATUS];
	}

	if (checkBox_displayCustomEmoticons) {
		[account setPreference:[NSNumber numberWithBool:[checkBox_displayCustomEmoticons state]]
						forKey:KEY_DISPLAY_CUSTOM_EMOTICONS
						 group:GROUP_ACCOUNT_STATUS];
	}
}

#pragma mark Encoding

- (void)addEncodingItemsWithNames:(NSArray *)inArray withTitle:(NSString *)inTitle toMenu:(NSMenu *)menu
{
	NSString		*name;
	NSMenuItem		*menuItem;
    BOOL			canIndent = [NSMenuItem instancesRespondToSelector:@selector(setIndentationLevel:)];
	
    menuItem = [[NSMenuItem alloc] initWithTitle:inTitle
																	target:nil
																	action:nil
															 keyEquivalent:@""];
	[menuItem setEnabled:NO];
	[menu addItem:menuItem];
	[menuItem release];
	
	for (name in inArray) {
		menuItem = [[NSMenuItem alloc] initWithTitle:name
																		target:nil
																		action:nil
																 keyEquivalent:@""];
		[menuItem setRepresentedObject:name];
		if (canIndent) [menuItem setIndentationLevel:1];
		
		[menu addItem:menuItem];
		[menuItem release];
	}
}


- (NSMenu *)encodingMenu
{
	NSMenu		*menu = [[NSMenu alloc] init];
	NSArray		*nameArray;
	NSString	*title;
	
	//We'll do custom enabling/disabling and not change it after then, so we don't want auto menuItem validation
	[menu setAutoenablesItems:NO];
	
	title = @"Unicode";
	nameArray = [NSArray arrayWithObjects:@"UTF-8", nil];
	[self addEncodingItemsWithNames:nameArray withTitle:title toMenu:menu];
	
	title = @"European languages";
	nameArray = [NSArray arrayWithObjects:
				 @"ASCII",
				 @"ISO-8859-1",
				 @"ISO-8859-2",
				 @"ISO-8859-3",
				 @"ISO-8859-4",
				 @"ISO-8859-5",
				 @"ISO-8859-7",
				 @"ISO-8859-9",
				 @"ISO-8859-10",
				 @"ISO-8859-13",
				 @"ISO-8859-14",
				 @"ISO-8859-15",
				 @"ISO-8859-16",
				 @"KOI8-R",
				 @"KOI8-U", 
				 @"KOI8-RU",
				 @"CP1250",
				 @"CP1251",
				 @"CP1252",
				 @"CP1253",
				 @"CP1254",
				 @"CP1257",
				 @"CP850",
				 @"CP866",
				 @"MacRoman",
				 @"MacCentralEurope",
				 @"MacIceland",
				 @"MacCroatian",
				 @"MacRomania",
				 @"MacCyrillic",
				 @"MacUkraine",
				 @"MacGreek",
				 @"MacTurkish",
				 @"Macintosh",
				 nil];
	[self addEncodingItemsWithNames:nameArray withTitle:title toMenu:menu];
	
	title = @"Semitic languages";
	nameArray = [NSArray arrayWithObjects:
				 @"ISO-8859-6",
				 @"ISO-8859-8",
				 @"CP1255",
				 @"CP1256",
				 @"CP862",
				 @"MacHebrew",
				 @"MacArabic",
				 nil];
	[self addEncodingItemsWithNames:nameArray withTitle:title toMenu:menu];
	
	title = @"Japanese";
	nameArray = [NSArray arrayWithObjects:
				 @"EUC-JP",
				 @"SHIFT_JIS",
				 @"CP932",
				 @"ISO-2022-JP",
				 @"ISO-2022-JP-2",
				 @"ISO-2022-JP-1",
				 nil];
	[self addEncodingItemsWithNames:nameArray withTitle:title toMenu:menu];
	
	title = @"Chinese";
	nameArray = [NSArray arrayWithObjects:
				 @"EUC-CN",
				 @"HZ",
				 @"GBK",
				 @"GB18030",
				 @"EUC-TW",
				 @"BIG5",
				 @"CP950",
				 @"BIG5-HKSCS",
				 @"ISO-2022-CN",
				 @"ISO-2022-CN-EXT",
				 nil];
	[self addEncodingItemsWithNames:nameArray withTitle:title toMenu:menu];
	
	title = @"Korean";
	nameArray = [NSArray arrayWithObjects:
				 @"EUC-KR",
				 @"CP949",
				 @"ISO-2022-KR",
				 @"JOHAB",
				 nil];
	[self addEncodingItemsWithNames:nameArray withTitle:title toMenu:menu];
	
	title = @"Armenian";
	nameArray = [NSArray arrayWithObjects:
				 @"ARMSCII-8",
				 nil];
	[self addEncodingItemsWithNames:nameArray withTitle:title toMenu:menu];
	
	title = @"Georgian";
	nameArray = [NSArray arrayWithObjects:
				 @"Georgian-Academy",
				 @"Georgian-PS",
				 nil];
	[self addEncodingItemsWithNames:nameArray withTitle:title toMenu:menu];
	
	title = @"Tajik";
	nameArray = [NSArray arrayWithObjects:
				 @"KOI8-T",
				 nil];
	[self addEncodingItemsWithNames:nameArray withTitle:title toMenu:menu];
	
	title = @"Thai";
	nameArray = [NSArray arrayWithObjects:
				 @"TIS-620",
				 @"CP874",
				 @"MacThai",
				 nil];
	[self addEncodingItemsWithNames:nameArray withTitle:title toMenu:menu];
	
	title = @"Laotian";
	nameArray = [NSArray arrayWithObjects:
				 @"MuleLao-1",
				 @"CP1133",
				 nil];
	[self addEncodingItemsWithNames:nameArray withTitle:title toMenu:menu];
	
	title = @"Vietnamese";
	nameArray = [NSArray arrayWithObjects:
				 @"VISCII",
				 @"TCVN",
				 @"CP1258",
				 nil];
	[self addEncodingItemsWithNames:nameArray withTitle:title toMenu:menu];
	
	/*
	 Platform specifics
	 HP-ROMAN8, NEXTSTEP
	 */
	
	return [menu autorelease];
}


/*!
 * @brief What this machine calls itself in another device's list of linked devices
 */
+ (NSString *)defaultDeviceName
{
	NSString *machine = [[NSHost currentHost] localizedName];
	if (![machine length])
		machine = [[NSProcessInfo processInfo] hostName];

	return [NSString stringWithFormat:AILocalizedString(@"Adium on %@", "Name this computer gives itself in another device's list of linked devices. %@ is the computer's name."), machine];
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
	return [NSString stringWithFormat:@"%s:%s", [(CBPurpleAccount *)account protocolPlugin], setting];
}

/*!
 * @brief Every purple service lays its fields out as rows
 *
 * A nib of its own used to mean its whole view was hosted, which is how five services kept hand
 * drawn fields for options their protocol had been declaring all along. The protocol is asked
 * instead, and it knows more than any of those nibs did.
 */
- (BOOL)usesSharedAccountViews
{
	return YES;
}

/*!
 * @brief What this option used to be stored under, if it was stored anywhere else
 *
 * Purely a move: read once, written where the option lives now, and the old key is left alone so
 * that going back a version loses nothing.
 */
- (id)legacyValueForSetting:(const char *)setting
{
	static NSDictionary *legacyKeys = nil;
	if (!legacyKeys) {
		NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"AIPurpleLegacyOptionKeys"
																		  ofType:@"plist"];
		legacyKeys = [[NSDictionary alloc] initWithContentsOfFile:path];
	}

	NSDictionary *forProtocol = [legacyKeys objectForKey:[NSString stringWithUTF8String:[(CBPurpleAccount *)account protocolPlugin]]];
	if (!forProtocol)
		return nil;

	NSString *wanted = [NSString stringWithUTF8String:setting];

	for (NSString *oldKey in forProtocol) {
		if (![[forProtocol objectForKey:oldKey] isEqualToString:wanted])
			continue;

		id value = [account preferenceForKey:oldKey group:GROUP_ACCOUNT_STATUS];
		if (value) {
			[account setPreference:value forKey:[self preferenceKeyForSetting:setting] group:GROUP_ACCOUNT_STATUS];
			return value;
		}
	}

	return nil;
}

- (BOOL)hasProtocolOptions
{
	PurplePlugin *prpl = purple_plugins_find_with_id([(CBPurpleAccount *)account protocolPlugin]);
	PurplePluginProtocolInfo *info = (prpl && prpl->info) ? PURPLE_PLUGIN_PROTOCOL_INFO(prpl) : NULL;

	return (info && info->protocol_options != NULL);
}

- (void)addOptionRowsToForm:(AISettingsFormView *)form
{
	PurplePlugin *prpl = purple_plugins_find_with_id([(CBPurpleAccount *)account protocolPlugin]);
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

		/* Not the ones Adium asks for itself. Server and port have their own shared fields, and
		 * CBPurpleAccount hands their values to the protocol under exactly these names, so a row
		 * built from the protocol would be a second field for one setting. */
		if (!strcmp(setting, "server") || !strcmp(setting, "port"))
			continue;

		const char *text = purple_account_option_get_text(option);

		/* Its own label if it has one. A protocol which names an option and nothing else gets the
		 * setting name, which is at least the truth. */
		NSString *label = (text && *text) ? [NSString stringWithUTF8String:text]
										  : [NSString stringWithUTF8String:setting];
		NSString *key = [self preferenceKeyForSetting:setting];
		id stored = [account preferenceForKey:key group:GROUP_ACCOUNT_STATUS];
		if (!stored)
			stored = [self legacyValueForSetting:setting];

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

				/* What the other side lists this link as. The plugins name themselves there, which
				 * is not what a person recognises in their list of linked devices. */
				if (!stored && !strcmp(setting, "device-name"))
					stored = [PurpleAccountViewController defaultDeviceName];

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
				NSString *fallbackValue = (fallback ? [NSString stringWithUTF8String:fallback] : nil);
				NSUInteger index = (stored ? [values indexOfObject:stored] : NSNotFound);

				/* A stored value the protocol no longer offers, or none at all, falls back to the
				 * protocol's own default rather than to whatever happens to be first in the menu:
				 * showing the first entry would claim a setting nobody chose. */
				if (index == NSNotFound && fallbackValue)
					index = [values indexOfObject:fallbackValue];

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
