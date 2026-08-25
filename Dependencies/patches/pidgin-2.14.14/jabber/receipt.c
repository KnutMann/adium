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

#include "privacy.h"

#include "buddy.h"
#include "jutil.h"
#include "receipt.h"

static jabber_receipt_cb receipt_cb = NULL;

void jabber_set_receipt_cb(jabber_receipt_cb cb)
{
	receipt_cb = cb;
}

gboolean jabber_receipt_parse(JabberStream *js, const char *from, xmlnode *child)
{
	const char *xmlns = xmlnode_get_namespace(child);

	if (!xmlns || !purple_strequal(xmlns, NS_RECEIPTS))
		return FALSE;

	if (!purple_strequal(child->name, "received"))
		return FALSE;

	if (receipt_cb && js->gc) {
		const char *id = xmlnode_get_attrib(child, "id");
		receipt_cb(js->gc, from, id);
	}

	return TRUE;
}

void jabber_receipt_add_request(xmlnode *message)
{
	xmlnode *request;

	request = xmlnode_new_child(message, "request");
	xmlnode_set_namespace(request, NS_RECEIPTS);
}

void jabber_receipt_send_received(JabberStream *js, const char *from,
                                  const char *message_id)
{
	xmlnode *recv_msg, *recv;
	JabberBuddy *jb;
	char *bare, *id;

	if (!from || !message_id)
		return;

	/* A receipt tells the sender we are online right now, so it is not for everyone
	 * who asks: the XEP's Security Considerations restrict it to senders that may see
	 * our presence anyway. That means a subscription of "from" or "both", and nobody
	 * the account's privacy settings block. */
	bare = jabber_get_bare_jid(from);
	if (!bare)
		return;

	jb = jabber_buddy_find(js, bare, FALSE);
	if (!jb || !(jb->subscription & JABBER_SUB_FROM) ||
	    !purple_privacy_check(purple_connection_get_account(js->gc), bare)) {
		g_free(bare);
		return;
	}
	g_free(bare);

	recv_msg = xmlnode_new("message");
	xmlnode_set_attrib(recv_msg, "to", from);
	id = jabber_get_next_id(js);
	xmlnode_set_attrib(recv_msg, "id", id);
	g_free(id);

	recv = xmlnode_new_child(recv_msg, "received");
	xmlnode_set_namespace(recv, NS_RECEIPTS);
	xmlnode_set_attrib(recv, "id", message_id);

	jabber_send(js, recv_msg);
	xmlnode_free(recv_msg);
}
