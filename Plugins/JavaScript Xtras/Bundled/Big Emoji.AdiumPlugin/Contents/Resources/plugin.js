// Big Emoji - a bundled Adium JavaScript plugin.
//
// A message whose whole body is one to three emoji or emoticons is shown
// enlarged, the way modern messengers do. Pure style change on the message
// body it is handed; nothing is inserted, no message text is ever read into
// HTML. Text emoji grow with the font size; emoticon images grow by height.

(function () {
	'use strict';

	var GLYPH_SIZE = '2.6em';
	var MAX_GLYPHS = 3;

	var segmenter = (typeof Intl !== 'undefined' && Intl.Segmenter)
		? new Intl.Segmenter(undefined, { granularity: 'grapheme' })
		: null;

	function graphemes(text) {
		if (segmenter) {
			var out = [];
			var it = segmenter.segment(text)[Symbol.iterator]();
			for (var s = it.next(); !s.done; s = it.next()) out.push(s.value.segment);
			return out;
		}
		return Array.from(text);
	}

	// Every grapheme of the text must be a pictographic emoji; returns the count, or -1
	function emojiCount(text) {
		var trimmed = text.trim();
		if (!trimmed) return 0;   // whitespace contributes no glyphs
		var clusters = graphemes(trimmed);
		for (var i = 0; i < clusters.length; i++) {
			if (!/^(\p{Extended_Pictographic}|\p{Emoji_Presentation})/u.test(clusters[i])) return -1;
		}
		return clusters.length;
	}

	function isEmoticonImage(node) {
		return node.nodeType === 1 && node.tagName === 'IMG' &&
			node.classList && node.classList.contains('emoticon');
	}

	// Walk the body's children: count emoji graphemes and emoticon images, and
	// bail on anything else. Returns {glyphs, emoticons:[...]} or null.
	function inspect(body) {
		var glyphs = 0;
		var emoticons = [];

		for (var i = 0; i < body.childNodes.length; i++) {
			var node = body.childNodes[i];

			if (node.nodeType === 3) {                       // text
				var n = emojiCount(node.nodeValue);
				if (n < 0) return null;
				glyphs += n;
			} else if (isEmoticonImage(node)) {              // an emoticon
				emoticons.push(node);
				glyphs += 1;
			} else if (node.nodeType === 1 && node.tagName === 'BR') {
				// harmless
			} else {
				return null;                                  // a link, formatting, anything else
			}

			if (glyphs > MAX_GLYPHS) return null;
		}

		return (glyphs >= 1) ? { glyphs: glyphs, emoticons: emoticons } : null;
	}

	function enlarge(body) {
		var found = inspect(body);
		if (!found) return;

		// Text emoji grow with the font size on the body
		body.style.fontSize = GLYPH_SIZE;
		body.style.lineHeight = '1.25';
		body.style.display = 'inline-block';

		// Emoticon images do not follow font-size, so grow them by height
		found.emoticons.forEach(function (img) {
			img.style.height = GLYPH_SIZE;
			img.style.width = 'auto';
		});
	}

	adiumPlugin.onMessagesAdded(function (nodes) {
		nodes.forEach(enlarge);
	});
})();
