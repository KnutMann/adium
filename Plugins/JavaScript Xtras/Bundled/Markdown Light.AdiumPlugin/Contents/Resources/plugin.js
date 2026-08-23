// Markdown Light - a bundled Adium JavaScript plugin.
//
// Renders *emphasis*, **strong** and ~strikethrough~ in the message body.
// Works only on text nodes and builds elements with textContent, so no markup
// from the message can ever be introduced; a pair must open and close within
// one text node, so markers split by an emoticon image are left alone.

(function () {
	'use strict';

	// One marker: opener, its element, and the run it wraps captured as group 1
	var patterns = [
		{ re: /\*\*([^*]+?)\*\*/, tag: 'strong' },
		{ re: /~([^~]+?)~/,       tag: 's' },
		{ re: /\*([^*\s][^*]*?)\*/, tag: 'em' }
	];

	function insideSkippedElement(node) {
		for (var p = node.parentNode; p && p.nodeType === 1; p = p.parentNode) {
			var t = p.tagName;
			if (t === 'A' || t === 'CODE' || t === 'PRE' || t === 'STRONG' || t === 'EM' || t === 'S') return true;
		}
		return false;
	}

	function transformTextNode(textNode) {
		for (var i = 0; i < patterns.length; i++) {
			var m = patterns[i].re.exec(textNode.nodeValue);
			if (!m) continue;

			// Split the run out: [before][match][after], replace the match with an element
			var after = textNode.splitText(m.index);
			after.nodeValue = after.nodeValue.substring(m[0].length);

			var el = document.createElement(patterns[i].tag);
			el.textContent = m[1];
			textNode.parentNode.insertBefore(el, after);

			// The inner run and the tail may hold more markers; let the walker reach them
			return true;
		}
		return false;
	}

	function walk(root) {
		var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
		var pending = [];
		var n;
		while ((n = walker.nextNode())) {
			if (!insideSkippedElement(n) && /[*~]/.test(n.nodeValue)) pending.push(n);
		}
		// Mutating during the walk is unsafe; collect first, then transform, re-queuing tails
		while (pending.length) {
			var node = pending.shift();
			if (transformTextNode(node)) {
				// The tail sibling may still carry markers
				var tail = node.nextSibling ? node.nextSibling.nextSibling : null;
				if (tail && tail.nodeType === 3 && /[*~]/.test(tail.nodeValue)) pending.push(tail);
				if (/[*~]/.test(node.nodeValue)) pending.push(node);
			}
		}
	}

	adiumPlugin.onMessagesAdded(function (nodes) {
		nodes.forEach(walk);
	});
})();
