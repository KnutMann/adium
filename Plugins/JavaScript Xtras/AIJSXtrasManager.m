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

#import "AIJSXtrasManager.h"
#import "AIJSXtraBundle.h"
#import <Adium/AICorePluginLoader.h>
#import <Adium/AISharedAdium.h>
#import <Adium/AIPreferenceControllerProtocol.h>

#import "AIJSXtrasPreamble.h"

/* The per-world preamble itself lives in AIJSXtrasPreamble.h, one source shared
 * with the transform harness in Tests/, so the harness always tests the preamble
 * the app injects. The isolation reasoning stays here, next to the injection:
 *
 * What the fences are, honestly: the content world separates JAVASCRIPT, not
 * the DOM. A plugin only receives message-body spans from here, but the DOM is
 * shared, so a plugin that walks it can read the whole displayed transcript,
 * senders and timestamps included, and can vandalize the display; installing a
 * plugin means trusting it with what is on screen. What a plugin cannot do is
 * leave or escalate: the rule list blocks every network egress, the navigation
 * policy pins the page to its file origin, other worlds' globals are out of
 * reach, and the page world holds no native handler; the app listens in its
 * own bridge world and only forwards real user gestures (event.isTrusted), so
 * even a script element written into the shared DOM, which runs in the page
 * world, finds nothing to drive. The isolation probe in Tests/ measures every
 * one of these claims.
 */

@interface AIJSXtrasManager ()
@property (readwrite, nonatomic) NSArray<AIJSXtraBundle *> *enabledBundles;
@property (readwrite, nonatomic) NSArray<AIJSXtraBundle *> *allBundles;
@end

@implementation AIJSXtrasManager

+ (instancetype)sharedManager
{
	static AIJSXtrasManager *shared = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shared = [[self alloc] init];
		[shared rescan];
	});
	return shared;
}

#pragma mark Discovery

- (void)rescan
{
	NSMutableArray *found = [NSMutableArray array];
	NSMutableSet *seenIdentifiers = [NSMutableSet set];

	//The plugins that ship with Adium, in their own folder outside Contents/PlugIns
	NSString *bundledDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"JavaScript Plugins"];
	for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundledDir error:NULL]) {
		if (![[name pathExtension] isEqualToString:@"AdiumPlugin"]) continue;
		[self addBundleAtPath:[bundledDir stringByAppendingPathComponent:name] to:found seen:seenIdentifiers];
	}

	/* User-installed plugins live beside the compiled ones; only the JS ones load
	 * here, and only after the same gates a native external plugin faces. This scan
	 * is what activates a JavaScript plugin, at startup and on live install alike,
	 * so the question has to be asked here: a confirmed plugin passes silently, an
	 * unknown one raises the loader's confirm dialog, and one the user disables is
	 * moved away by the gate before it was ever injected anywhere. */
	for (NSString *path in [adium allResourcesForName:@"PlugIns" withExtensions:@"AdiumPlugin"]) {
		if (![[[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:@"AIJavaScriptPlugin"] boolValue])
			continue;
		if (![AICorePluginLoader externalPluginPassesGatesAtPath:path])
			continue;
		[self addBundleAtPath:path to:found seen:seenIdentifiers];
	}

	self.allBundles = found;

	NSMutableArray *enabled = [NSMutableArray array];
	if ([self masterEnabled]) {
		for (AIJSXtraBundle *bundle in found) {
			if ([self isBundleEnabled:bundle]) [enabled addObject:bundle];
		}
	}
	self.enabledBundles = enabled;

	[[NSNotificationCenter defaultCenter] postNotificationName:AIJSXtrasDidChangeNotification object:self];
}

- (void)addBundleAtPath:(NSString *)path to:(NSMutableArray *)found seen:(NSMutableSet *)seenIdentifiers
{
	AIJSXtraBundle *bundle = [AIJSXtraBundle bundleWithPath:path];
	//nil means not a JavaScript plugin, or it failed validation; either way skip it
	if (!bundle) return;

	//First one found for an identifier wins (bundled shadows a user copy of the same id)
	if ([seenIdentifiers containsObject:bundle.bundleIdentifier]) return;
	[seenIdentifiers addObject:bundle.bundleIdentifier];

	[found addObject:bundle];
}

#pragma mark Enablement

- (BOOL)masterEnabled
{
	id value = [adium.preferenceController preferenceForKey:KEY_JSXTRAS_MASTER_ENABLED group:PREF_GROUP_JSXTRAS];
	return (value ? [value boolValue] : YES);
}

- (void)setMasterEnabled:(BOOL)enabled
{
	[adium.preferenceController setPreference:@(enabled) forKey:KEY_JSXTRAS_MASTER_ENABLED group:PREF_GROUP_JSXTRAS];
	[self rescan];
}

- (BOOL)isBundleEnabled:(AIJSXtraBundle *)bundle
{
	return [self isPluginEnabledWithIdentifier:bundle.bundleIdentifier];
}

- (void)setBundle:(AIJSXtraBundle *)bundle enabled:(BOOL)enabled
{
	[self setPluginWithIdentifier:bundle.bundleIdentifier enabled:enabled];
}

- (BOOL)isPluginEnabledWithIdentifier:(NSString *)identifier
{
	if (![identifier length]) return YES;

	NSDictionary *enabledPlugins = [adium.preferenceController preferenceForKey:KEY_JSXTRAS_ENABLED_PLUGINS
																		 group:PREF_GROUP_JSXTRAS];
	id value = enabledPlugins[identifier];
	return (value ? [value boolValue] : YES);
}

- (void)setPluginWithIdentifier:(NSString *)identifier enabled:(BOOL)enabled
{
	if (![identifier length]) return;

	NSDictionary *stored = [adium.preferenceController preferenceForKey:KEY_JSXTRAS_ENABLED_PLUGINS
																 group:PREF_GROUP_JSXTRAS];
	NSMutableDictionary *enabledPlugins = [stored mutableCopy] ?: [NSMutableDictionary dictionary];
	enabledPlugins[identifier] = @(enabled);
	[adium.preferenceController setPreference:enabledPlugins forKey:KEY_JSXTRAS_ENABLED_PLUGINS group:PREF_GROUP_JSXTRAS];
	[self rescan];
}

#pragma mark Settings

- (AIJSXtraBundle *)bundleWithIdentifier:(NSString *)identifier
{
	if (![identifier length]) return nil;

	for (AIJSXtraBundle *bundle in self.allBundles) {
		if ([bundle.bundleIdentifier isEqualToString:identifier]) return bundle;
	}

	return nil;
}

- (NSArray *)settingsForPluginWithIdentifier:(NSString *)identifier
{
	return [[self bundleWithIdentifier:identifier] settings] ?: @[];
}

- (AIJSXtraSetting *)settingWithKey:(NSString *)settingKey pluginWithIdentifier:(NSString *)identifier
{
	for (AIJSXtraSetting *setting in [self settingsForPluginWithIdentifier:identifier]) {
		if ([setting.key isEqualToString:settingKey]) return setting;
	}

	return nil;
}

/*!
 * @brief The value in force for one setting, or nil for a setting nobody declares
 *
 * Never the stored object as it was found. What was written is re-checked against what is declared
 * NOW, every time, and anything that no longer fits falls back to the manifest default. Three
 * reasons, all real: the preference file is one the user can edit; a plugin update can drop an
 * option from under a value the version before it stored; and two installed bundles can claim one
 * CFBundleIdentifier, where the first one found wins and inherits the loser's stored values.
 *
 * The invariant is worth stating plainly, because everything downstream leans on it: the value
 * handed to a plugin is always either a declared default or a value the current manifest still
 * offers, and never anything read straight out of the preference file.
 */
- (NSString *)valueForSettingKey:(NSString *)settingKey pluginWithIdentifier:(NSString *)identifier
{
	AIJSXtraSetting *setting = [self settingWithKey:settingKey pluginWithIdentifier:identifier];

	if (!setting) return nil;

	NSDictionary	*stored = [adium.preferenceController preferenceForKey:KEY_JSXTRAS_PLUGIN_SETTINGS
																	 group:PREF_GROUP_JSXTRAS];
	id				 forPlugin = stored[identifier];
	id				 value = ([forPlugin isKindOfClass:[NSDictionary class]] ? forPlugin[settingKey] : nil);

	return [setting coercedValue:value];
}

/*!
 * @brief Choose a value for one setting
 *
 * Refuses a key the current manifest does not declare and a value it does not offer, so the
 * settings store cannot be used as general-purpose persistence by a plugin that would like some.
 *
 * A value equal to the default is removed rather than written, and a plugin left with nothing to
 * say drops out of the dictionary altogether: what is stored is only ever the deviations. That also
 * means a key an update renamed away simply stops being written, and one left behind is never read,
 * since only declared keys are ever looked up. Nothing is pruned on read, because that would throw
 * away the settings of a plugin which is merely switched off or temporarily missing.
 *
 * Nothing is registered with +registerDefaults:forGroup: either, though the master switch uses it.
 * Registering defaults derived from a manifest would let a downloaded bundle put keys of its own
 * choosing into Adium's registered defaults, where they would outlive the bundle being deleted. The
 * defaults stay in memory, derived from the validated declaration, recomputed on every read.
 */
- (void)setValue:(NSString *)value forSettingKey:(NSString *)settingKey pluginWithIdentifier:(NSString *)identifier
{
	AIJSXtraSetting *setting = [self settingWithKey:settingKey pluginWithIdentifier:identifier];

	if (!setting) return;
	if (![value isKindOfClass:[NSString class]] || ![setting.optionValues containsObject:value]) return;

	NSDictionary		*stored = [adium.preferenceController preferenceForKey:KEY_JSXTRAS_PLUGIN_SETTINGS
																		 group:PREF_GROUP_JSXTRAS];
	NSMutableDictionary	*allSettings = [stored mutableCopy] ?: [NSMutableDictionary dictionary];
	id					 storedForPlugin = allSettings[identifier];
	NSMutableDictionary	*forPlugin = ([storedForPlugin isKindOfClass:[NSDictionary class]] ?
									  [storedForPlugin mutableCopy] :
									  [NSMutableDictionary dictionary]);

	if ([value isEqualToString:setting.defaultValue])
		[forPlugin removeObjectForKey:settingKey];
	else
		forPlugin[settingKey] = value;

	if ([forPlugin count]) allSettings[identifier] = forPlugin;
	else [allSettings removeObjectForKey:identifier];

	[adium.preferenceController setPreference:allSettings forKey:KEY_JSXTRAS_PLUGIN_SETTINGS group:PREF_GROUP_JSXTRAS];

	[self notePluginSettingsChanged];
}

/*!
 * @brief Every declared key of one plugin with the value in force, ready to serialize
 *
 * Every declared key, always, not only the ones the user has touched, so a plugin running under
 * this Adium never has to test whether a key it declared is there. What it does have to test is
 * whether adiumPlugin.settings exists at all, which is how it stays runnable under an older Adium
 * and under the transform harness.
 */
- (NSDictionary *)effectiveValuesForBundle:(AIJSXtraBundle *)bundle
{
	NSMutableDictionary *values = [NSMutableDictionary dictionary];

	for (AIJSXtraSetting *setting in bundle.settings) {
		NSString *value = [self valueForSettingKey:setting.key pluginWithIdentifier:bundle.bundleIdentifier];

		if (value) values[setting.key] = value;
	}

	return values;
}

/*!
 * @brief Tell every open message view that a value changed
 *
 * The same notification the switch posts, taking the path that already exists and is already
 * exercised: AIWebKitMessageViewWKController observes it and answers by dropping every user script,
 * asking for them again - which is where the new value is built into a script - and replaying the
 * conversation. User scripts are fixed once injected, so a rebuild is the only way an open view can
 * see a new value.
 *
 * Deliberately NOT through -rescan, which is where the switch ends: -rescan re-reads and
 * re-validates every bundle off disk, and choosing a menu item changed nothing on disk. It would
 * also replace every AIJSXtraBundle, and the page the user is standing on is holding that plugin's
 * declarations.
 *
 * Nor does anything post AIXtrasDidChangeNotification here. That one makes the Xtras pane rebuild
 * its list, which pops the open page: the page would be pulled out from under the menu that was
 * just used.
 *
 * Coalesced onto the next runloop turn because the views' answer is a visible redraw of the whole
 * transcript, and a card may write more than one value at once.
 */
- (void)notePluginSettingsChanged
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(postSettingsChange) object:nil];
	[self performSelector:@selector(postSettingsChange) withObject:nil afterDelay:0.0];
}

- (void)postSettingsChange
{
	[[NSNotificationCenter defaultCenter] postNotificationName:AIJSXtrasDidChangeNotification object:self];
}

#pragma mark Injection

- (void)installIntoUserContentController:(WKUserContentController *)userContentController
{
	for (AIJSXtraBundle *bundle in self.enabledBundles) {
		WKContentWorld *world = [WKContentWorld worldWithName:bundle.contentWorldName];

		/* The plugin's settings as data, before the trusted host reads them. A plugin declaring
		 * none gets no script and no global at all. */
		if ([bundle.settings count]) {
			NSString *settingsScript = AIJSXtrasSettingsScript([self effectiveValuesForBundle:bundle]);

			/* Fail closed. Injecting the plugin without the settings it declared would run it
			 * against nothing at all: for one whose only sane behaviour depends on a value, that is
			 * a silent behaviour change caused by a serialization failure, which is the class of
			 * thing "never partially trusted" exists to prevent. */
			if (!settingsScript) {
				NSLog(@"JSXtra: %@ settings could not be serialized; not injecting it", bundle.bundleIdentifier);
				continue;
			}

			[userContentController addUserScript:[[WKUserScript alloc] initWithSource:settingsScript
																		injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
																	 forMainFrameOnly:YES
																	   inContentWorld:world]];
		}

		/* Then the preamble, then the plugin's own script, all at document end in that world. Order
		 * within one world and one injection time is the order they were added, which is what
		 * already guarantees the preamble beats the plugin: every bundled plugin reads adiumPlugin
		 * at top level. The settings script before the preamble is the same guarantee. */
		[userContentController addUserScript:[[WKUserScript alloc] initWithSource:AIJSXtrasPreamble
																   injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
																forMainFrameOnly:YES
																  inContentWorld:world]];

		[userContentController addUserScript:[[WKUserScript alloc] initWithSource:bundle.source
																   injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
																forMainFrameOnly:YES
																  inContentWorld:world]];
	}
}

@end
