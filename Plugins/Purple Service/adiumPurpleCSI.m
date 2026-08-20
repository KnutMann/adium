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

#import "adiumPurpleCSI.h"
#import <AppKit/AppKit.h>

/*
 * Client State Indication (XEP-0352) for the jabber protocol.
 *
 * When Adium stops being the active application, every jabber server that offered
 * CSI in its stream features is told <inactive/>, and <active/> when Adium comes
 * back. An inactive client still gets every message; the server merely holds back
 * or thins out what nobody is looking at - presence changes, typing notifications -
 * and delivers the remainder in one batch on the next <active/>.
 *
 * Support is read off the stream features as they pass the receiving signal during
 * login, and the two state nonzas are injected the same way the carbons enable is:
 * by emitting jabber-sending-xmlnode, whose highest-priority handler is the
 * protocol's own sender. A server that never offered CSI is never told anything,
 * as the XEP demands.
 */

#define NS_CSI "urn:xmpp:csi:0"

static int adium_purple_csi_handle;

//Connections whose server advertised CSI; values are meaningless, presence is the point
static GHashTable *csi_supported = NULL;
static gboolean csi_app_active = TRUE;

static PurplePlugin *csi_jabber_prpl(void)
{
	return purple_find_prpl("prpl-jabber");
}

static void csi_send_state(PurpleConnection *gc, gboolean active)
{
	PurplePlugin *jabber = csi_jabber_prpl();
	if (!jabber)
		return;

	xmlnode *nonza = xmlnode_new(active ? "active" : "inactive");
	xmlnode_set_namespace(nonza, NS_CSI);

	purple_signal_emit(jabber, "jabber-sending-xmlnode", gc, &nonza);
	if (nonza)
		xmlnode_free(nonza);
}

/*!
 * @brief Note CSI in the stream features as they pass by during login
 */
static void csi_receiving_xmlnode_cb(PurpleConnection *gc, xmlnode **packet, gpointer data)
{
	xmlnode *node = (packet ? *packet : NULL);

	if (!node || !purple_strequal(node->name, "features"))
		return;

	if (xmlnode_get_child_with_namespace(node, "csi", NS_CSI))
		g_hash_table_insert(csi_supported, gc, GINT_TO_POINTER(TRUE));
}

/*!
 * @brief Push the current state to every connected server that understands it
 */
static void csi_broadcast_state(gboolean active)
{
	if (active == csi_app_active)
		return;
	csi_app_active = active;

	for (GList *l = purple_connections_get_all(); l; l = l->next) {
		PurpleConnection *gc = l->data;

		if (purple_connection_get_state(gc) != PURPLE_CONNECTED)
			continue;
		if (!g_hash_table_lookup(csi_supported, gc))
			continue;

		csi_send_state(gc, active);
	}
}

#pragma mark Connection lifecycle

/*!
 * @brief A jabber account starts connecting: make sure the features watcher is in place
 *
 * Bound lazily here rather than at ui-ops time, when the protocol may not be
 * registered yet. Signing-on is early enough; the stream features come later.
 */
static void csi_signing_on_cb(PurpleConnection *gc, gpointer data)
{
	PurpleAccount *account = purple_connection_get_account(gc);
	if (!purple_strequal(purple_account_get_protocol_id(account), "prpl-jabber"))
		return;

	PurplePlugin *jabber = csi_jabber_prpl();
	if (!jabber)
		return;

	static gboolean hooked = FALSE;
	if (!hooked) {
		hooked = TRUE;
		purple_signal_connect(jabber, "jabber-receiving-xmlnode", &adium_purple_csi_handle,
							  PURPLE_CALLBACK(csi_receiving_xmlnode_cb), NULL);
	}
}

/*!
 * @brief Freshly signed on: if nobody is looking right now, say so
 */
static void csi_signed_on_cb(PurpleConnection *gc, gpointer data)
{
	if (!csi_app_active && g_hash_table_lookup(csi_supported, gc))
		csi_send_state(gc, FALSE);
}

static void csi_signed_off_cb(PurpleConnection *gc, gpointer data)
{
	g_hash_table_remove(csi_supported, gc);
}

void configureAdiumPurpleCSI(void)
{
	csi_supported = g_hash_table_new(g_direct_hash, g_direct_equal);
	csi_app_active = (BOOL)[NSApp isActive];

	void *connections = purple_connections_get_handle();
	purple_signal_connect(connections, "signing-on", &adium_purple_csi_handle,
						  PURPLE_CALLBACK(csi_signing_on_cb), NULL);
	purple_signal_connect(connections, "signed-on", &adium_purple_csi_handle,
						  PURPLE_CALLBACK(csi_signed_on_cb), NULL);
	purple_signal_connect(connections, "signed-off", &adium_purple_csi_handle,
						  PURPLE_CALLBACK(csi_signed_off_cb), NULL);

	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserverForName:NSApplicationDidBecomeActiveNotification
						object:nil
						 queue:[NSOperationQueue mainQueue]
					usingBlock:^(NSNotification *notification) {
						csi_broadcast_state(TRUE);
					}];
	[center addObserverForName:NSApplicationDidResignActiveNotification
						object:nil
						 queue:[NSOperationQueue mainQueue]
					usingBlock:^(NSNotification *notification) {
						csi_broadcast_state(FALSE);
					}];
}
