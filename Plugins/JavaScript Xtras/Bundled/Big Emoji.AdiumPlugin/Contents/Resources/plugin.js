// Big Emoji - a bundled Adium JavaScript plugin.
//
// A message whose whole body is one to three emoji or emoticons is shown
// enlarged, the way modern messengers do. Pure style change on the message
// body it is handed; nothing is inserted, no message text is ever read into
// HTML.
//
// Emoji are font glyphs and scale cleanly, so they grow to triple size.
// Emoticons are small raster images that would blur if pushed that far, so
// they grow to double their own edge length, no more.
//
// How far the emoji grow, and how many of them still count as "a short
// message", are settings on this extension's page in Adium's Xtras settings.
// The floor and the emoticon factor are not: the floor is what keeps a small
// chat font jumbo, the factor is where raster pictures start to blur, and
// neither of them is taste.

(function () {
	'use strict';

	var SETTINGS = (window.adiumPlugin && adiumPlugin.settings) || {};

	// A setting arrives as one of the strings the manifest listed; map it to the
	// number that string names. Guarded rather than trusting the host: an
	// unexpected token must not become NaN in a font size, and a plain
	// SCALES[token] would hand back a function for a token like "constructor".
	function pick(map, value, fallback) {
		return Object.prototype.hasOwnProperty.call(map, value) ? map[value] : fallback;
	}

	var EMOJI_SCALE = pick({ '2': 2, '3': 3, '4': 4 }, SETTINGS.emojiScale, 3);   // the emoji's own edge length, times this
	var EMOJI_FLOOR = 48;          // not a setting: at least this, so a small chat font still reads as jumbo
	var EMOTICON_SCALE = 2;        // not a setting: raster emoticons blur past double their own pixels
	var MAX_GLYPHS = pick({ '1': 1, '2': 2, '3': 3 }, SETTINGS.maxGlyphs, 3);

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

	// Walk the body's children, counting emoji graphemes and emoticon images and
	// bailing on anything else. Returns {emoji, emoticons:[...]} or null.
	function inspect(body) {
		var emoji = 0;
		var emoticons = [];

		for (var i = 0; i < body.childNodes.length; i++) {
			var node = body.childNodes[i];

			if (node.nodeType === 3) {                       // text
				var n = emojiCount(node.nodeValue);
				if (n < 0) return null;
				emoji += n;
			} else if (isEmoticonImage(node)) {              // an emoticon
				emoticons.push(node);
			} else if (node.nodeType === 1 && node.tagName === 'BR') {
				// harmless
			} else {
				return null;                                  // a link, formatting, anything else
			}

			if (emoji + emoticons.length > MAX_GLYPHS) return null;
		}

		return (emoji + emoticons.length >= 1) ? { emoji: emoji, emoticons: emoticons } : null;
	}

	// Double an emoticon's own edge length; wait for the image if it has not loaded yet
	function scaleEmoticon(img) {
		function apply() {
			if (!img.naturalWidth) return;
			img.style.width = (img.naturalWidth * EMOTICON_SCALE) + 'px';
			img.style.height = (img.naturalHeight * EMOTICON_SCALE) + 'px';
		}
		if (img.complete && img.naturalWidth) apply();
		else img.addEventListener('load', apply, { once: true });
	}

	function enlarge(body) {
		var found = inspect(body);
		if (!found) return;

		// Emoji are text: triple the font size actually in effect (an em would only
		// triple whatever the style already shrank it to), with a floor so a small
		// chat font still lands somewhere jumbo and clear of the doubled emoticons.
		if (found.emoji > 0) {
			var base = parseFloat(getComputedStyle(body).fontSize) || 16;
			body.style.fontSize = Math.max(base * EMOJI_SCALE, EMOJI_FLOOR) + 'px';
			body.style.lineHeight = '1.25';
		}
		body.style.display = 'inline-block';

		found.emoticons.forEach(scaleEmoticon);
	}

	adiumPlugin.onMessagesAdded(function (nodes) {
		nodes.forEach(enlarge);
	});
})();
