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
 *
 */

#include "internal.h"

#include "chatmarker.h"

static jabber_chat_marker_cb chat_marker_cb = NULL;

void jabber_set_chat_marker_cb(jabber_chat_marker_cb cb)
{
	chat_marker_cb = cb;
}

gboolean jabber_chat_marker_parse(JabberStream *js, const char *from, xmlnode *child)
{
	const char *xmlns = xmlnode_get_namespace(child);

	if (!xmlns || !purple_strequal(xmlns, NS_CHAT_MARKERS))
		return FALSE;

	if (!purple_strequal(child->name, "displayed") &&
	    !purple_strequal(child->name, "acknowledged") &&
	    !purple_strequal(child->name, "received") &&
	    !purple_strequal(child->name, "active"))
		return FALSE;

	if (chat_marker_cb && js->gc) {
		const char *id = xmlnode_get_attrib(child, "id");
		chat_marker_cb(js->gc, from, id, child->name);
	}

	return TRUE;
}

void jabber_chat_marker_send(JabberStream *js, const char *to,
                             const char *message_id, const char *marker_type)
{
	xmlnode *marker_msg, *marker;

	marker_msg = xmlnode_new("message");
	xmlnode_set_attrib(marker_msg, "to", to);
	xmlnode_set_attrib(marker_msg, "id", jabber_get_next_id(js));

	marker = xmlnode_new_child(marker_msg, marker_type);
	xmlnode_set_namespace(marker, NS_CHAT_MARKERS);
	if (message_id != NULL)
		xmlnode_set_attrib(marker, "id", message_id);

	jabber_send(js, marker_msg);
	xmlnode_free(marker_msg);
}
