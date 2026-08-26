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

/* The gesture bridge: the app's only path from the page to the native side.
 *
 * The "adium" script message handler is registered solely in the content world named
 * below, so the page world never sees window.webkit.messageHandlers.adium; no script
 * that ends up running there, whatever put it there, has a native side to reach. The
 * bridge script is installed into that world and forwards exactly three signals:
 *
 * - "ready", once the document's own scripts have run (DOMContentLoaded; the template
 *   script is deferred, so announcing at injection time would be too early and the app
 *   would draw into a page whose display machinery does not exist yet). Posted from
 *   here rather than the template, so a third-party style shipping its own
 *   Template.html signals readiness too. It carries the page generation the app
 *   stamped into the document, so a ready from a page a newer load already doomed
 *   is recognizable and ignored instead of triggering a draw against the wrong page.
 * - "zoomImage" for a genuine click on a content-sized image; window.client.zoomImage
 *   in the page keeps only the size arithmetic the styles' click handlers consult.
 * - "fileTransfer" for a genuine click on a transfer button. The styles wire those as
 *   onclick="client.handleFileTransfer('Save', 'id')" through our own keyword
 *   substitution; the parameters are read back out of that attribute (attributes are
 *   shared DOM), while the page-side client.handleFileTransfer does nothing.
 *
 * Every event path checks isTrusted, so nothing here can be driven by script: a click
 * or contextmenu synthesized in the page world or in a plugin's world is ignored.
 *
 * This header is the single source for both the message view controller and the
 * isolation probe in Plugins/JavaScript Xtras/Tests, which mirrors the production
 * configuration; keeping one copy is what keeps the probe honest.
 */

__attribute__((unused)) static NSString *const AIWKBridgeWorldName = @"adium.bridge";

__attribute__((unused)) static NSString *const AIWKGestureBridgeScript =
	@""
	@"(function() {\n"
	@"    'use strict';\n"
	@"    var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.adium;\n"
	@"    if (!bridge) return;\n"
	@"\n"
	@"    var announced = false;\n"
	@"    function announceReady() {\n"
	@"        if (announced) return;\n"
	@"        announced = true;\n"
	@"        var marker = document.getElementById('x-adium-generation');\n"
	@"        bridge.postMessage({type: 'ready', generation: marker ? (marker.getAttribute('data-generation') || '') : ''});\n"
	@"    }\n"
	@"    /* Not before DOMContentLoaded: the template's script is deferred, and ready must\n"
	@"       mean its functions exist. The load fallback covers a late injection. */\n"
	@"    if (document.readyState === 'complete')\n"
	@"        announceReady();\n"
	@"    else {\n"
	@"        document.addEventListener('DOMContentLoaded', announceReady);\n"
	@"        window.addEventListener('load', announceReady);\n"
	@"    }\n"
	@"\n"
	@"    var transferPattern = /client\\.handleFileTransfer\\('(Save|SaveAs|Cancel)', '([^']*)'\\)/;\n"
	@"    document.addEventListener('click', function(event) {\n"
	@"        if (!event.isTrusted) return;\n"
	@"        var node = event.target;\n"
	@"        if (node && node.tagName === 'IMG' && (node.width > 64 || node.height > 64)) {\n"
	@"            bridge.postMessage({type: 'zoomImage', imageURL: node.currentSrc || node.getAttribute('src') || ''});\n"
	@"            return;\n"
	@"        }\n"
	@"        for (var el = node; el && el.getAttribute; el = el.parentNode) {\n"
	@"            var wired = (el.getAttribute('onclick') || '') + ' ' + (el.getAttribute('href') || '');\n"
	@"            var match = transferPattern.exec(wired);\n"
	@"            if (match) {\n"
	@"                bridge.postMessage({type: 'fileTransfer', action: match[1], fileTransferID: match[2]});\n"
	@"                return;\n"
	@"            }\n"
	@"        }\n"
	@"    }, true);\n"
	@"})();\n";
