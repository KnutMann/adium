/*
 * Adium is the property of its developers, whose names are listed in the copyright file included
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

#import <Foundation/Foundation.h>

/*!
 * @brief The per-world preamble, injected before every plugin's own script
 *
 * Kept as a compile-time constant, not a loadable resource: it is the trusted
 * host every plugin talks to, and a file could be swapped where a constant
 * cannot. It installs a MutationObserver on the transcript and hands each
 * plugin the message-body spans as they appear, so a plugin never has to know
 * how a message style is built.
 *
 * This header is the single source for both AIJSXtrasManager and the transform
 * harness in Tests/, which drives every bundled plugin through a real WKWebView;
 * one copy is what keeps the harness testing the preamble the app actually
 * injects. The isolation reasoning lives at the top of AIJSXtrasManager.m.
 *
 * A plugin's settings arrive in a script of their own, injected into the same
 * world just before this one, as a temporary window.__adiumXtraSettings. Four
 * things happen to them here and each is deliberate:
 *
 *   - only strings are copied across. That is the manifest's one setting type
 *     enforced a second time, in the trusted host: if the Objective-C side ever
 *     regresses and lets a nested object through, it is dropped here, which is
 *     what keeps the Object.freeze below a complete freeze and not a shallow
 *     one. Add a type whose values are not scalars and that freeze must become
 *     recursive in the same commit.
 *   - the copy is made onto an object with no prototype, so a declared key can
 *     never resolve to something on Object.prototype.
 *   - it hangs under .settings rather than being spread onto adiumPlugin, so no
 *     manifest-declared key can shadow apiVersion or onMessagesAdded.
 *   - the temporary global is deleted before the plugin's own script runs, so a
 *     plugin sees only the frozen, filtered copy.
 *
 * Freezing is hygiene, not a security boundary: a plugin owns its world and can
 * shadow whatever it likes. What it buys is that the host's copy cannot be
 * swapped out and read back differently.
 */
__attribute__((unused)) static NSString * const AIJSXtrasPreamble =
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
@"  var raw = window.__adiumXtraSettings;\n"
@"  try { delete window.__adiumXtraSettings; } catch (e) { window.__adiumXtraSettings = undefined; }\n"
@"  var settings = Object.create(null);\n"
@"  if (raw && typeof raw === 'object') {\n"
@"    var names = Object.getOwnPropertyNames(raw);\n"
@"    for (var i = 0; i < names.length; i++) { if (typeof raw[names[i]] === 'string') settings[names[i]] = raw[names[i]]; }\n"
@"  }\n"
@"  Object.freeze(settings);\n"
@"  var api = { apiVersion: 1, settings: settings, onMessagesAdded: function (cb) { if (typeof cb === 'function') callbacks.push(cb); } };\n"
@"  Object.freeze(api);\n"
@"  Object.defineProperty(window, 'adiumPlugin', { value: api, writable: false, configurable: false });\n"
@"  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();\n"
@"})();\n";


/*!
 * @brief The one-line script that carries a plugin's settings into its own world
 *
 * The ONLY place in this feature where manifest or user data becomes source
 * text, and it has exactly one shape, forever:
 *
 *     window.__adiumXtraSettings = JSON.parse("...ascii...");
 *
 * A separate script rather than something spliced into the preamble, for two
 * reasons. The preamble is a compile-time constant so that it cannot be swapped
 * (see above), and building it at runtime out of a manifest would make the
 * trusted host a different string for every plugin and would take the harness
 * with it. And a malformed blob is then a SyntaxError in a script of its own,
 * which WebKit fails on its own, instead of taking window.adiumPlugin down with
 * it: one plugin's manifest silently disabling the host contract.
 *
 * JSON.parse rather than an inline object literal because JSON.parse gives
 * "__proto__" no special meaning where an object literal makes it the prototype
 * setter; the validator refuses such a key anyway, and this is the second fence.
 *
 * The escaping is NSJSONSerialization's twice over, once for the data and once
 * to wrap that text in a JavaScript string literal. The ASCII check afterwards
 * is the belt: every key and every value has been validated to a plain ASCII
 * token, so anything else appearing here means a rule upstream was loosened, and
 * the honest answer to that is to refuse to inject rather than to emit it. It
 * also closes, without anyone having to think about it, the one thing
 * NSJSONSerialization does not escape: U+2028 and U+2029, legal inside JSON and
 * illegal in JavaScript source before ES2019.
 *
 * Returns nil for anything it cannot express, and the caller must fail closed.
 */
__attribute__((unused)) static NSString *AIJSXtrasSettingsScript(NSDictionary *values)
{
	if (![values count]) return nil;

	/* Strings only, which is the manifest's one setting type stated a third time. The preamble
	 * drops anything else on the way in, but a generator which would emit it is a generator whose
	 * output no longer matches what this file says it emits, and the next type added here would
	 * inherit that quietly. */
	for (id key in values) {
		if (![key isKindOfClass:[NSString class]] || ![values[key] isKindOfClass:[NSString class]]) return nil;
	}

	if (![NSJSONSerialization isValidJSONObject:values]) return nil;

	NSData		*data = [NSJSONSerialization dataWithJSONObject:values options:0 error:NULL];
	NSString	*json = (data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil);

	if (![json length]) return nil;

	//Wrap that text in a JS string literal by letting NSJSONSerialization escape it a second time
	NSData		*quoted = [NSJSONSerialization dataWithJSONObject:@[json] options:0 error:NULL];
	NSString	*array = (quoted ? [[NSString alloc] initWithData:quoted encoding:NSUTF8StringEncoding] : nil);

	if ([array length] < 3) return nil;

	NSString	*literal = [array substringWithRange:NSMakeRange(1, [array length] - 2)];	//strip the [ ]

	for (NSUInteger i = 0; i < [literal length]; i++) {
		unichar c = [literal characterAtIndex:i];

		if (c < 0x20 || c > 0x7E) return nil;
	}

	return [NSString stringWithFormat:@"window.__adiumXtraSettings = JSON.parse(%@);\n", literal];
}
