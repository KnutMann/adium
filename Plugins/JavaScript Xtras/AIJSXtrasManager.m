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

/*!
 * @brief The per-world preamble, injected before every plugin's own script
 *
 * Kept as a compile-time constant, not a loadable resource: it is the trusted
 * host every plugin talks to, and a file could be swapped where a constant
 * cannot. It installs a MutationObserver on the transcript and hands each
 * plugin the message-body spans as they appear, so a plugin never has to know
 * how a message style is built.
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
static NSString * const AIJSXtrasPreamble =
@"(function () {\n"
@"  'use strict';\n"
@"  var callbacks = [];\n"
@"  var seen = new WeakSet();\n"
@"  function collect(root) {\n"
@"    var out = [];\n"
@"    if (!root || root.nodeType !== 1) return out;\n"
@"    if (root.matches && root.matches('span[data-x-adium-msg]')) out.push(root);\n"
@"    if (root.querySelectorAll) { var q = root.querySelectorAll('span[data-x-adium-msg]'); for (var i = 0; i < q.length; i++) out.push(q[i]); }\n"
@"    return out;\n"
@"  }\n"
@"  function deliver(nodes) {\n"
@"    var fresh = [];\n"
@"    for (var i = 0; i < nodes.length; i++) { if (!seen.has(nodes[i])) { seen.add(nodes[i]); fresh.push(nodes[i]); } }\n"
@"    if (!fresh.length) return;\n"
@"    for (var c = 0; c < callbacks.length; c++) { try { callbacks[c](fresh); } catch (e) { if (window.console) console.error('[adiumPlugin]', e); } }\n"
@"  }\n"
@"  function start() {\n"
@"    var target = document.getElementById('Chat') || document.body;\n"
@"    if (!target) return;\n"
@"    new MutationObserver(function (muts) {\n"
@"      var batch = [];\n"
@"      for (var m = 0; m < muts.length; m++) { var added = muts[m].addedNodes; for (var n = 0; n < added.length; n++) { var c = collect(added[n]); for (var k = 0; k < c.length; k++) batch.push(c[k]); } }\n"
@"      if (batch.length) deliver(batch);\n"
@"    }).observe(target, { childList: true, subtree: true });\n"
@"    deliver(collect(target));\n"
@"  }\n"
@"  var api = { apiVersion: 1, onMessagesAdded: function (cb) { if (typeof cb === 'function') callbacks.push(cb); } };\n"
@"  Object.freeze(api);\n"
@"  Object.defineProperty(window, 'adiumPlugin', { value: api, writable: false, configurable: false });\n"
@"  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();\n"
@"})();\n";

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

#pragma mark Injection

- (void)installIntoUserContentController:(WKUserContentController *)userContentController
{
	for (AIJSXtraBundle *bundle in self.enabledBundles) {
		WKContentWorld *world = [WKContentWorld worldWithName:bundle.contentWorldName];

		//Preamble first, then the plugin's own script, both at document end in that world
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
