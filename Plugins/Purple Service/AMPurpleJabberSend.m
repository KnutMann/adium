/*
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
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

#import "AMPurpleJabberSend.h"

void AMPurpleJabberSend(PurpleConnection *gc, xmlnode *stanza)
{
	if (!stanza) return;

	PurplePlugin *jabber = purple_find_prpl("prpl-jabber");
	if (!gc || !jabber) {
		xmlnode_free(stanza);
		return;
	}

	/* The protocol's own sender sits on this signal at the lowest priority and therefore runs
	 * last, which makes emitting it the sanctioned way in rather than a trick. It also frees
	 * the stanza, or rather leaves it to us, hence the free below. */
	/* Our own pointer, because a handler may set the signal's to nothing in order to stop the
	 * stanza going out, and it is still ours to free. This is what libpurple's own senders do,
	 * and doing it the other way round leaks a stanza every time one is held back. */
	xmlnode *ours = stanza;
	purple_signal_emit(jabber, "jabber-sending-xmlnode", gc, &stanza);
	xmlnode_free(ours);
}

void AMPurpleJabberSendText(PurpleConnection *gc, const char *text, int length)
{
	if (!gc || !text) return;

	xmlnode *parsed = xmlnode_from_str(text, length);

	if (parsed) {
		AMPurpleJabberSend(gc, parsed);
		return;
	}

	/* Not well formed, or a fragment. Sent as written, because the one caller that reaches this
	 * is the XML console, whose whole purpose is to put things on the wire that the rest of this
	 * code would refuse to build. */
	PurplePluginProtocolInfo *info = PURPLE_PLUGIN_PROTOCOL_INFO(gc->prpl);
	if (info && info->send_raw)
		info->send_raw(gc, text, length);
}
