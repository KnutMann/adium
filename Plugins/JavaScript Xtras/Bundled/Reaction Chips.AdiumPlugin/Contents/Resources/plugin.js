// Reaction Chips - a bundled Adium JavaScript plugin.
//
// A softer look for the emoji reactions Adium already draws under a message.
// Adium learns reactions from the protocol (XEP-0444) and lays each one out as
// a small chip in a ".x-adium-reactions" strip, tagging every chip with whose
// it is; this plugin only restyles those chips: rounder pills with a quiet
// fill that brightens on hover, and your own reactions picked out in the same
// blue the read tick uses, so at a glance you can tell yours from everyone
// else's.
//
// It reads no message text, touches no network, and adds no reaction of its
// own. It is one <style> element and nothing more, so it colours whatever chips
// appear, now and later, without watching the page.

(function () {
	'use strict';

	var STYLE_ID = 'x-adium-reaction-chips';

	// Chips carry inline styles from the app, so each rule that means to change
	// their look is marked important to win over them. Neutral greys sit on
	// either theme; the accent is the read-blue, tying your reaction to the tick
	// that marks a read message.
	var CSS =
		'.x-adium-reactions {' +
		'  display: inline-flex !important;' +
		'  flex-wrap: wrap !important;' +
		'  gap: 3px !important;' +
		'  margin-inline-start: 0.4em !important;' +
		'  vertical-align: middle !important;' +
		'}' +
		'.x-adium-reaction {' +
		'  display: inline-block !important;' +
		'  font-size: 0.8em !important;' +
		'  line-height: 1.5 !important;' +
		'  padding: 0 0.5em !important;' +
		'  margin: 0 !important;' +
		'  border: 1px solid rgba(127,127,127,0.35) !important;' +
		'  border-radius: 1em !important;' +
		'  background-color: rgba(127,127,127,0.12) !important;' +
		'  cursor: default !important;' +
		'}' +
		'.x-adium-reaction:hover {' +
		'  background-color: rgba(127,127,127,0.22) !important;' +
		'}' +
		'.x-adium-reaction[data-sender="me"] {' +          /* your own reactions */
		'  border-color: rgba(52,183,241,0.6) !important;' +
		'  background-color: rgba(52,183,241,0.16) !important;' +
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
