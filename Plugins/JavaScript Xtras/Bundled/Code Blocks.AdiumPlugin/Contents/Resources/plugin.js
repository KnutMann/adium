// Code Blocks - a bundled Adium JavaScript plugin.
//
// Sets `inline code` in monospace, and turns a message that is one fenced
// block (```...```) into a <pre>. Builds every element with textContent, so
// message text is never interpreted as markup.

(function () {
	'use strict';

	var STYLE_ID = 'x-adium-codeblocks-style';

	function ensureStyle() {
		if (document.getElementById(STYLE_ID)) return;
		var style = document.createElement('style');
		style.id = STYLE_ID;
		style.textContent =
			'.x-adium-code{font-family:ui-monospace,Menlo,monospace;' +
			'background:rgba(127,127,127,0.16);border-radius:3px;padding:0 3px;}' +
			'.x-adium-pre{font-family:ui-monospace,Menlo,monospace;white-space:pre-wrap;' +
			'background:rgba(127,127,127,0.14);border-radius:5px;padding:6px 8px;margin:2px 0;}';
		(document.head || document.body).appendChild(style);
	}

	function insideSkipped(node) {
		for (var p = node.parentNode; p && p.nodeType === 1; p = p.parentNode) {
			var t = p.tagName;
			if (t === 'A' || t === 'CODE' || t === 'PRE') return true;
		}
		return false;
	}

	// Inline `code`: split the run and wrap it in a styled <code>
	function inlinePass(root) {
		var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
		var pending = [];
		var n;
		while ((n = walker.nextNode())) {
			if (!insideSkipped(n) && n.nodeValue.indexOf('`') !== -1) pending.push(n);
		}
		while (pending.length) {
			var node = pending.shift();
			var m = /`([^`]+?)`/.exec(node.nodeValue);
			if (!m) continue;

			var after = node.splitText(m.index);
			after.nodeValue = after.nodeValue.substring(m[0].length);

			var code = document.createElement('code');
			code.className = 'x-adium-code';
			code.textContent = m[1];
			node.parentNode.insertBefore(code, after);

			if (after.nodeValue.indexOf('`') !== -1) pending.push(after);
		}
	}

	function hasOnlyTextAndBreaks(node) {
		for (var i = 0; i < node.childNodes.length; i++) {
			var c = node.childNodes[i];
			if (c.nodeType === 1 && c.tagName !== 'BR') return false;
		}
		return true;
	}

	// A whole-message fenced block: replace the wrapper's contents with a <pre>
	function fencedPass(wrapper) {
		if (!hasOnlyTextAndBreaks(wrapper)) return false;

		// Reconstruct the text with <br> as newlines
		var text = '';
		for (var i = 0; i < wrapper.childNodes.length; i++) {
			var c = wrapper.childNodes[i];
			if (c.nodeType === 3) text += c.nodeValue;
			else if (c.nodeType === 1 && c.tagName === 'BR') text += '\n';
		}

		var lines = text.split('\n');
		if (lines.length < 2) return false;
		if (!/^```/.test(lines[0].trim())) return false;

		// Find the closing fence
		var close = -1;
		for (var j = 1; j < lines.length; j++) {
			if (lines[j].trim() === '```') { close = j; break; }
		}
		if (close === -1) return false;

		// Only a message that IS one fenced block becomes a <pre>. Text after the
		// closing fence means there was more to say, and replacing the wrapper
		// would silently delete it, so such a message keeps the inline pass.
		for (var k = close + 1; k < lines.length; k++) {
			if (lines[k].trim() !== '') return false;
		}

		var body = lines.slice(1, close).join('\n');
		var pre = document.createElement('pre');
		pre.className = 'x-adium-pre';
		pre.textContent = body;

		while (wrapper.firstChild) wrapper.removeChild(wrapper.firstChild);
		wrapper.appendChild(pre);
		return true;
	}

	adiumPlugin.onMessagesAdded(function (nodes) {
		ensureStyle();
		nodes.forEach(function (wrapper) {
			if (!fencedPass(wrapper)) inlinePass(wrapper);
		});
	});
})();
