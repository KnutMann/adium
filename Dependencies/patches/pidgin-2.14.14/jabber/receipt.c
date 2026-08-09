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
