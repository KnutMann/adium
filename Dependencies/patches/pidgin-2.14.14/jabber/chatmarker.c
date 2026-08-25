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

#include "jutil.h"
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
	char *id;

	marker_msg = xmlnode_new("message");
	xmlnode_set_attrib(marker_msg, "to", to);
	id = jabber_get_next_id(js);
	xmlnode_set_attrib(marker_msg, "id", id);
	g_free(id);

	marker = xmlnode_new_child(marker_msg, marker_type);
	xmlnode_set_namespace(marker, NS_CHAT_MARKERS);
	if (message_id != NULL)
		xmlnode_set_attrib(marker, "id", message_id);

	jabber_send(js, marker_msg);
	xmlnode_free(marker_msg);
}

/* gc pointer + bare JID -> id of the newest markable message not yet marked displayed */
static GHashTable *pending_markables = NULL;

static char *jabber_chat_marker_key(PurpleConnection *gc, const char *jid)
{
	char *bare = jabber_get_bare_jid(jid);
	char *key = g_strdup_printf("%p|%s", (void *)gc, bare ? bare : jid);
	g_free(bare);
	return key;
}

void jabber_chat_marker_note_markable(PurpleConnection *gc, const char *from,
                                      const char *message_id)
{
	char *key;

	if (!gc || !from || !message_id)
		return;

	if (!pending_markables)
		pending_markables = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);

	key = jabber_chat_marker_key(gc, from);
	g_hash_table_replace(pending_markables, key, g_strdup(message_id));
}

gboolean jabber_chat_marker_send_displayed(PurpleConnection *gc, const char *who)
{
	JabberStream *js;
	char *key, *bare;
	const char *id;
	gboolean sent = FALSE;

	if (!gc || !who || !pending_markables)
		return FALSE;

	js = purple_connection_get_protocol_data(gc);
	if (!js)
		return FALSE;

	key = jabber_chat_marker_key(gc, who);
	id = g_hash_table_lookup(pending_markables, key);
	if (id) {
		bare = jabber_get_bare_jid(who);
		jabber_chat_marker_send(js, bare ? bare : who, id, "displayed");
		g_free(bare);
		g_hash_table_remove(pending_markables, key);
		sent = TRUE;
	}
	g_free(key);

	return sent;
}

void jabber_chat_marker_add_markable(xmlnode *message)
{
	xmlnode *markable;

	markable = xmlnode_new_child(message, "markable");
	xmlnode_set_namespace(markable, NS_CHAT_MARKERS);
}
