/*
 * purple - Jabber Protocol Plugin
 *
 * purple
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
#ifndef PURPLE_JABBER_CHATMARKER_H_
#define PURPLE_JABBER_CHATMARKER_H_

#include "jabber.h"
#include "xmlnode.h"

/* XEP-0333: Chat Markers */

typedef void (*jabber_chat_marker_cb)(PurpleConnection *gc, const char *from, const char *message_id, const char *marker_type);

void jabber_set_chat_marker_cb(jabber_chat_marker_cb cb);

gboolean jabber_chat_marker_parse(JabberStream *js, const char *from, xmlnode *child);

void jabber_chat_marker_send(JabberStream *js, const char *to, const char *message_id, const char *marker_type);

#endif /* PURPLE_JABBER_CHATMARKER_H_ */
