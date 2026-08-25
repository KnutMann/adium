// Read Receipts - a bundled Adium JavaScript plugin.
//
// A message you sent gains a tick once the other side confirms it: a grey
// double-check when the contact's client has received it (XEP-0184 delivery),
// and a blue one when it has been read (XEP-0333 chat markers). Adium already
// learns both from the protocol and marks such a message with an
// "x-adium-delivered" or "x-adium-read" class; this plugin is only the tick
// those classes draw.
//
// WHERE the tick sits is a taste question each message style answers
// differently, so it is a setting right here:
//
//   PLACEMENT = 'time-before'  the tick sits just left of the timestamp
//               'time-after'   just right of the timestamp
//               'message'      trailing the message text itself
//
// The timestamp is found by the class names the styles conventionally use
// (.time and friends; the bundled Smooth Operator and Mockie both match). A
// style that names its timestamp differently can be added to TIME_CLASSES, or
// set PLACEMENT to 'message', which needs no timestamp at all.
//
// The ticks keep a fixed pixel size on purpose: Big Emoji scales a short
// emoji message up with an em-based font size, and an em-sized tick would
// balloon along with it. Only the emoji should be big.
//
// It reads no message text, touches no network, and never marks a message the
// app has not: every rule is pinned to the app's own outgoing message wrapper
// and its namespaced classes, so a message style using a generic name like
// "delivered" for something of its own can never grow a tick. Read paints
// over delivered, so a read message shows one blue pair, not two.

(function () {
	'use strict';

	var PLACEMENT = 'time-before';   // 'time-before' | 'time-after' | 'message'

	var STYLE_ID = 'x-adium-read-receipts';
	var OUTGOING = '[data-x-adium-msg][data-x-adium-dir="outgoing"]';
	var TIME_CLASSES = ['.time', '.timestamp', '.x-time', '.x-rtime', '.x-ltime'];

	var GREY = '#8a949e';    /* delivered - a quiet grey */
	var BLUE = '#34b7f1';    /* read - the read-blue, wins over grey */

	// The shared look of the pair: fixed pixel size (see header), the two ticks
	// overlapped into one glyph pair, kept out of bidi reordering.
	var TICK_STYLE =
		'  font-size: 11px;' +
		'  letter-spacing: -2px;' +
		'  vertical-align: baseline;' +
		'  white-space: nowrap;' +
		'  unicode-bidi: isolate;';

	// For a given state class, every way a timestamp can relate to the marked
	// message inside one message block: the time element before the message in
	// the DOM (it then needs :has to look ahead), or after it (plain sibling
	// combinators). Both directions feed the same pseudo-element, so the visual
	// side is chosen by PLACEMENT alone, not by the style's DOM order.
	function timeSelectors(stateClass) {
		var marked = OUTGOING + '.' + stateClass;
		var out = [];
		TIME_CLASSES.forEach(function (t) {
			out.push(t + ':has(~ ' + marked + ')');            // time first, wrapper is a later sibling
			out.push(t + ':has(~ * ' + marked + ')');          // time first, wrapper nested in a later sibling
			out.push(marked + ' ~ ' + t);                      // wrapper first, time is a later sibling
			out.push('*:has(> ' + marked + ') ~ ' + t);        // wrapper nested, its parent precedes the time
		});
		return out;
	}

	function buildCSS() {
		var ticks = '\\2713\\2713';
		if (PLACEMENT === 'message') {
			var content = '"\\00a0' + ticks + '"';
			return OUTGOING + '.x-adium-delivered::after, ' + OUTGOING + '.x-adium-read::after {' +
				'  content: ' + content + ';' + TICK_STYLE + '}' +
				OUTGOING + '.x-adium-delivered::after { color: ' + GREY + '; }' +
				OUTGOING + '.x-adium-read::after      { color: ' + BLUE + '; }';
		}

		var side = (PLACEMENT === 'time-after') ? 'after' : 'before';
		var content = (side === 'before') ? '"' + ticks + '\\00a0"' : '"\\00a0' + ticks + '"';
		var delivered = timeSelectors('x-adium-delivered').map(function (s) { return s + '::' + side; });
		var read = timeSelectors('x-adium-read').map(function (s) { return s + '::' + side; });
		return delivered.concat(read).join(', ') + ' {' +
			'  content: ' + content + ';' + TICK_STYLE + '}' +
			delivered.join(', ') + ' { color: ' + GREY + '; }' +
			read.join(', ') + ' { color: ' + BLUE + '; }';
	}

	function install() {
		if (document.getElementById(STYLE_ID)) return;

		var style = document.createElement('style');
		style.id = STYLE_ID;
		style.textContent = buildCSS();
		(document.head || document.documentElement).appendChild(style);
	}

	if (document.readyState === 'loading')
		document.addEventListener('DOMContentLoaded', install);
	else
		install();
})();
