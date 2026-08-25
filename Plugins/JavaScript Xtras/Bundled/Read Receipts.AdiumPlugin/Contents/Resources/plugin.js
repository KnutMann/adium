// Read Receipts - a bundled Adium JavaScript plugin.
//
// A message you sent is marked with a read tick once the other side's client
// reports having displayed it. Adium already sets a "tracked" class on such a
// message (XEP-0333 chat markers, the same thing the read marker rides on);
// this plugin is only the tick that class draws. It reads no message text,
// touches no network, and never marks a message the app has not marked itself.
//
// Only your own outgoing messages are ever tracked - a read receipt is about a
// message you sent - so the tick lands where it belongs and nowhere else.
// "Delivered but not yet read" is not surfaced by the app, so there is a single
// state to show, not the sent/delivered/read ladder of some messengers.

(function () {
	'use strict';

	var STYLE_ID = 'x-adium-read-receipts';

	// A small blue double-check trailing a read message, the shape modern
	// messengers settled on. It rides at the end of the message, a size down
	// and in the read-blue, out of the way of the text.
	var CSS =
		'.tracked::after {' +
		'  content: "\\00a0\\2713\\2713";' +   /* nbsp then two check marks */
		'  color: #34b7f1;' +
		'  font-size: 0.75em;' +
		'  letter-spacing: -0.18em;' +          /* draw the two ticks as one overlapping pair */
		'  vertical-align: baseline;' +
		'  white-space: nowrap;' +
		'  unicode-bidi: isolate;' +
		'}';

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
