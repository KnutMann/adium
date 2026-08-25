// Read Receipts - a bundled Adium JavaScript plugin.
//
// A message you sent gains a tick once the other side confirms it: a grey
// double-check when the contact's client has received it (XEP-0184 delivery),
// and a blue one when it has been read (XEP-0333 chat markers). Adium already
// learns both from the protocol and marks such a message with an
// "x-adium-delivered" or "x-adium-read" class; this plugin is only the tick
// those classes draw.
//
// It reads no message text, touches no network, and never marks a message the
// app has not: the selectors are pinned to the app's own outgoing message
// wrapper and its namespaced classes, so a message style using a generic name
// like "delivered" for something of its own can never grow a tick. Read paints
// over delivered, so a read message shows one blue pair, not two.

(function () {
	'use strict';

	var STYLE_ID = 'x-adium-read-receipts';

	// A small double-check trailing a confirmed message, the shape modern
	// messengers settled on: grey for delivered, the read-blue for read. The
	// blue rule comes second so that on a message carrying both classes it wins.
	var OUTGOING = '[data-x-adium-msg][data-x-adium-dir="outgoing"]';
	var CSS =
		OUTGOING + '.x-adium-delivered::after, ' + OUTGOING + '.x-adium-read::after {' +
		'  content: "\\00a0\\2713\\2713";' +   /* nbsp then two check marks */
		'  font-size: 0.75em;' +
		'  letter-spacing: -0.18em;' +          /* draw the two ticks as one overlapping pair */
		'  vertical-align: baseline;' +
		'  white-space: nowrap;' +
		'  unicode-bidi: isolate;' +
		'}' +
		OUTGOING + '.x-adium-delivered::after { color: #8a949e; }' +   /* delivered - a quiet grey */
		OUTGOING + '.x-adium-read::after      { color: #34b7f1; }';    /* read - the read-blue, wins over grey */

	function install() {
		if (document.getElementById(STYLE_ID)) return;

		var style = document.createElement('style');
		style.id = STYLE_ID;
		style.textContent = CSS;
		(document.head || document.documentElement).appendChild(style);
	}

	if (document.readyState === 'loading')
		document.addEventListener('DOMContentLoaded', install);
	else
		install();
})();
