// Big Emoji - a bundled Adium JavaScript plugin.
//
// A message whose whole text is one to three emoji is shown enlarged, the way
// modern messengers do. Pure style change on the message body it is handed;
// nothing is inserted, no message text is ever read into HTML.

(function () {
	'use strict';

	var segmenter = (typeof Intl !== 'undefined' && Intl.Segmenter)
		? new Intl.Segmenter(undefined, { granularity: 'grapheme' })
		: null;

	function isAllEmoji(text) {
		var trimmed = text.trim();
		if (!trimmed) return false;

		var clusters;
		if (segmenter) {
			clusters = [];
			var it = segmenter.segment(trimmed)[Symbol.iterator]();
			for (var s = it.next(); !s.done; s = it.next()) clusters.push(s.value.segment);
		} else {
			clusters = Array.from(trimmed);
		}

		if (clusters.length < 1 || clusters.length > 3) return false;

		for (var i = 0; i < clusters.length; i++) {
			// The first code point of each grapheme must be a pictographic emoji
			if (!/^(\p{Extended_Pictographic}|\p{Emoji_Presentation})/u.test(clusters[i])) return false;
		}
		return true;
	}

	function hasOnlyTextAndBreaks(node) {
		for (var i = 0; i < node.childNodes.length; i++) {
			var c = node.childNodes[i];
			if (c.nodeType === 1 && c.tagName !== 'BR') return false;
		}
		return true;
	}

	function enlarge(node) {
		// An emoticon image, or any other embedded element, is not "just emoji"
		if (!hasOnlyTextAndBreaks(node)) return;
		if (!isAllEmoji(node.textContent)) return;

		node.style.fontSize = '2.6em';
		node.style.lineHeight = '1.25';
		node.style.display = 'inline-block';
	}

	adiumPlugin.onMessagesAdded(function (nodes) {
		nodes.forEach(enlarge);
	});
})();
