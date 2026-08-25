/*
 * purple - Jabber Protocol Plugin
 *
 * Purple is the legal property of its developers, whose names are too numerous
 * to list here.  Please refer to the COPYRIGHT file distributed with this
 * source distribution.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02111-1301  USA
 */
#ifndef PURPLE_JABBER_REACTIONS_H_
#define PURPLE_JABBER_REACTIONS_H_

#include "jabber.h"
#include "xmlnode.h"

/* XEP-0444: Message Reactions */

/* Called for an incoming <reactions>. target_id is the id of the message being
 * reacted to; emojis is a GList of char* holding the sender's full current set
 * of reactions (empty when the sender cleared them). Both are owned by the
 * caller and valid only for the duration of the call. */
typedef void (*jabber_reactions_cb)(PurpleConnection *gc, const char *from,
                                    const char *target_id, GList *emojis);

void jabber_set_reactions_cb(jabber_reactions_cb cb);

/* Parse an incoming <reactions> child of a message. Returns TRUE when it was a
 * reactions element and has been handled. */
gboolean jabber_reactions_parse(JabberStream *js, const char *from, xmlnode *child);

/* Send our full current set of reactions to a message. An empty or NULL list
 * clears them, which is how XEP-0444 removes a reaction. */
void jabber_reactions_send(JabberStream *js, const char *to,
                           const char *target_id, GList *emojis);

#endif /* PURPLE_JABBER_REACTIONS_H_ */
