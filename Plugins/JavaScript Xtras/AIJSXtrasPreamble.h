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
@"  var api = { apiVersion: 1, onMessagesAdded: function (cb) { if (typeof cb === 'function') callbacks.push(cb); } };\n"
@"  Object.freeze(api);\n"
@"  Object.defineProperty(window, 'adiumPlugin', { value: api, writable: false, configurable: false });\n"
@"  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();\n"
@"})();\n";
