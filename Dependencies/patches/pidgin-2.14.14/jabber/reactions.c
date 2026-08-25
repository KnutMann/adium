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
#include "reactions.h"

static jabber_reactions_cb reactions_cb = NULL;

void jabber_set_reactions_cb(jabber_reactions_cb cb)
{
	reactions_cb = cb;
}

gboolean jabber_reactions_parse(JabberStream *js, const char *from, xmlnode *child)
{
	const char *xmlns = xmlnode_get_namespace(child);
	const char *target_id;
	xmlnode *reaction;
	GList *emojis = NULL;

	if (!xmlns || !purple_strequal(xmlns, NS_REACTIONS))
		return FALSE;

	if (!purple_strequal(child->name, "reactions"))
		return FALSE;

	target_id = xmlnode_get_attrib(child, "id");

	/* Every <reaction> child is one emoji of the sender's current set. XEP-0444
	 * sends the whole set each time (replace, not add), so the list is complete
	 * as it stands; an empty list means the sender took their reactions back. */
	for (reaction = xmlnode_get_child(child, "reaction");
	     reaction;
	     reaction = xmlnode_get_next_twin(reaction)) {
		char *data = xmlnode_get_data(reaction);
		if (data)
			emojis = g_list_append(emojis, data);
	}

	if (reactions_cb && js->gc)
		reactions_cb(js->gc, from, target_id, emojis);

	g_list_free_full(emojis, g_free);

	return TRUE;
}

void jabber_reactions_send(JabberStream *js, const char *to,
                           const char *target_id, GList *emojis)
{
	xmlnode *msg, *reactions, *reaction;
	GList *l;

	msg = xmlnode_new("message");
	xmlnode_set_attrib(msg, "to", to);
	xmlnode_set_attrib(msg, "type", "chat");
	xmlnode_set_attrib(msg, "id", jabber_get_next_id(js));

	reactions = xmlnode_new_child(msg, "reactions");
	xmlnode_set_namespace(reactions, NS_REACTIONS);
	if (target_id)
		xmlnode_set_attrib(reactions, "id", target_id);

	for (l = emojis; l; l = l->next) {
		reaction = xmlnode_new_child(reactions, "reaction");
		xmlnode_insert_data(reaction, (const char *)l->data, -1);
	}

	jabber_send(js, msg);
	xmlnode_free(msg);
}
