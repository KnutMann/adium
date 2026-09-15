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

#import <AdiumLibpurple/SLPurpleCocoaAdapter.h>

/*
 * The one way out for a jabber stanza written on this side of the bridge.
 *
 * It matters which way a stanza leaves, and the reason is not tidiness. The protocol counts
 * what it sends for XEP-0198, and it does that counting in the default handler of the
 * "jabber-sending-xmlnode" signal. A stanza handed straight to the protocol's send_raw skips
 * that handler, so the server counts it and we do not, and the two numbers drift apart for the
 * rest of the connection. Nothing complains; the count is simply wrong, and it is the number
 * that decides which stanzas get sent again after a resumed session.
 */

/*!
 * @brief Send a stanza the way the protocol expects, and free it
 *
 * The stanza is freed whether or not it could be sent, so the caller need not think about it.
 */
void AMPurpleJabberSend(PurpleConnection *gc, xmlnode *stanza);

/*!
 * @brief Send already written out XML, parsing it back so that it can be counted
 *
 * For the places that hold text rather than a tree. Anything that does not parse, or is not a
 * stanza, still goes out as it was written: the XML console exists precisely to send things
 * the rest of this code would not.
 */
void AMPurpleJabberSendText(PurpleConnection *gc, const char *text, int length);
