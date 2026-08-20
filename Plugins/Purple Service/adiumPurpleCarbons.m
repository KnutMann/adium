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

#import "adiumPurpleCarbons.h"

/*
 * Message Carbons (XEP-0280) for the jabber protocol.
 *
 * libpurple 2.x never learned carbons itself. The jabber protocol does expose the two
 * hooks this needs: "jabber-receiving-xmlnode" lets every incoming stanza be rewritten
 * or swallowed before the protocol parses it, and "jabber-sending-xmlnode" is both the
 * place to amend outgoing stanzas and, emitted by us, the sanctioned way to inject one
 * (the protocol's own sender hangs on that signal at highest priority, which runs last).
 *
 * On sign-on every jabber account asks the server to enable carbons; a server without
 * the feature answers with an iq error nobody handles, which is the polite no. A
 * received carbon replaces the wrapper with the forwarded message, so the protocol
 * processes what the other device saw. A sent carbon is written into the conversation
 * as an outgoing message from elsewhere - the same PURPLE_MESSAGE_REMOTE_SEND path the
 * WhatsApp echoes taught Adium. OTR never takes part: outgoing OTR messages carry the
 * private/no-copy hints (XEP-0334), and carbons of foreign OTR sessions are dropped,
 * because another device's ratchet only decrypts on that device.
 */

#define NS_CARBONS   "urn:xmpp:carbons:2"
#define NS_FORWARD   "urn:xmpp:forward:0"
#define NS_HINTS     "urn:xmpp:hints"

static int adium_purple_carbons_handle;

static PurplePlugin *carbons_jabber_prpl(void)
{
	return purple_find_prpl("prpl-jabber");
}

/*!
 * @brief The account's own bare JID, newly allocated
 */
static char *carbons_own_bare_jid(PurpleAccount *account)
{
	const char *username = purple_account_get_username(account);
	if (!username) return NULL;

	const char *slash = strchr(username, '/');
	return (slash ? g_strndup(username, (gsize)(slash - username)) : g_strdup(username));
}

/*!
 * @brief Does this text begin an OTR message?
 */
static gboolean carbons_is_otr(const char *text)
{
	return (text && strncmp(text, "?OTR", 4) == 0);
}

#pragma mark Receiving

/*!
 * @brief Unwrap incoming carbon copies before the protocol parses the stanza
 *
 * The caller of this signal frees whatever is left in *packet, so replacing the stanza
 * means freeing the old node ourselves, and swallowing means freeing it and leaving NULL.
 */
static void carbons_receiving_xmlnode_cb(PurpleConnection *gc, xmlnode **packet, gpointer data)
{
	xmlnode *node = (packet ? *packet : NULL);

	if (!node || !purple_strequal(node->name, "message"))
		return;

	gboolean was_sent = FALSE;
	xmlnode *carbon = xmlnode_get_child_with_namespace(node, "received", NS_CARBONS);
	if (!carbon) {
		carbon = xmlnode_get_child_with_namespace(node, "sent", NS_CARBONS);
		was_sent = TRUE;
	}
	if (!carbon)
		return;

	/* Carbons come from our own bare JID and nowhere else; anything else is somebody
	 * trying to put words into a conversation. Leave the stanza alone - without a body
	 * of its own it dies in the parser, and with one it is displayed as what it is, a
	 * message from the forger. */
	PurpleAccount	*account = purple_connection_get_account(gc);
	const char		*from = xmlnode_get_attrib(node, "from");
	char			*ownJid = carbons_own_bare_jid(account);
	gboolean		 genuine = (from && ownJid && !g_ascii_strcasecmp(from, ownJid));
	g_free(ownJid);

	if (!genuine)
		return;

	xmlnode *forwarded = xmlnode_get_child_with_namespace(carbon, "forwarded", NS_FORWARD);
	xmlnode *inner = (forwarded ? xmlnode_get_child(forwarded, "message") : NULL);
	if (!inner) {
		//A carbon with nothing forwarded inside carries nothing worth parsing
		xmlnode_free(node);
		*packet = NULL;
		return;
	}

	xmlnode	*body = xmlnode_get_child(inner, "body");
	char	*text = (body ? xmlnode_get_data(body) : NULL);

	/* An OTR message from another device's session cannot be decrypted here; showing
	 * it would print key exchange noise into the conversation. */
	if (carbons_is_otr(text)) {
		g_free(text);
		xmlnode_free(node);
		*packet = NULL;
		return;
	}

	if (!was_sent) {
		/* Received elsewhere: hand the protocol the forwarded message in place of the
		 * wrapper, and it is parsed like any other incoming message. */
		xmlnode *copy = xmlnode_copy(inner);
		xmlnode_free(node);
		*packet = copy;
		g_free(text);
		return;
	}

	/* Sent elsewhere: write it into the conversation as our own outgoing message from
	 * another device. Only messages with a body are worth showing; chat states and
	 * receipts from the other device are not. */
	const char *to = xmlnode_get_attrib(inner, "to");
	if (text && *text && to) {
		char *bareTo;
		const char *slash = strchr(to, '/');
		bareTo = (slash ? g_strndup(to, (gsize)(slash - to)) : g_strdup(to));

		PurpleConversation *conv = purple_find_conversation_with_account(PURPLE_CONV_TYPE_IM, bareTo, account);
		if (!conv)
			conv = purple_conversation_new(PURPLE_CONV_TYPE_IM, account, bareTo);

		char *html = g_markup_escape_text(text, -1);
		purple_conv_im_write(PURPLE_CONV_IM(conv), NULL, html,
							 (PURPLE_MESSAGE_SEND | PURPLE_MESSAGE_REMOTE_SEND),
							 time(NULL));
		g_free(html);
		g_free(bareTo);
	}

	g_free(text);
	xmlnode_free(node);
	*packet = NULL;
}

#pragma mark Sending

/*!
 * @brief Keep OTR messages out of everybody's carbons (XEP-0334 hints)
 *
 * Runs at default priority; the protocol's own sender runs at highest priority, which
 * is last, so the hints are on the stanza before it leaves.
 */
static void carbons_sending_xmlnode_cb(PurpleConnection *gc, xmlnode **packet, gpointer data)
{
	xmlnode *node = (packet ? *packet : NULL);

	if (!node || !purple_strequal(node->name, "message"))
		return;

	xmlnode	*body = xmlnode_get_child(node, "body");
	char	*text = (body ? xmlnode_get_data(body) : NULL);

	if (carbons_is_otr(text) && !xmlnode_get_child_with_namespace(node, "private", NS_CARBONS)) {
		xmlnode *private_node = xmlnode_new_child(node, "private");
		xmlnode_set_namespace(private_node, NS_CARBONS);

		xmlnode *no_copy = xmlnode_new_child(node, "no-copy");
		xmlnode_set_namespace(no_copy, NS_HINTS);
	}

	g_free(text);
}

#pragma mark Enabling

/*!
 * @brief Ask the server for carbons whenever a jabber account signs on
 *
 * Sent without asking disco first: a server without the feature answers the iq with an
 * error nobody handles, and that is the whole cost of asking.
 */
static void carbons_signed_on_cb(PurpleConnection *gc, gpointer data)
{
	PurpleAccount *account = purple_connection_get_account(gc);
	if (!purple_strequal(purple_account_get_protocol_id(account), "prpl-jabber"))
		return;

	PurplePlugin *jabber = carbons_jabber_prpl();
	if (!jabber)
		return;

	/* The stanza hooks bind lazily on the first jabber sign-on: by now the protocol is
	 * certainly registered, which is more than the ui-ops setup could say. */
	static gboolean hooked = FALSE;
	if (!hooked) {
		hooked = TRUE;
		purple_signal_connect(jabber, "jabber-receiving-xmlnode", &adium_purple_carbons_handle,
							  PURPLE_CALLBACK(carbons_receiving_xmlnode_cb), NULL);
		purple_signal_connect(jabber, "jabber-sending-xmlnode", &adium_purple_carbons_handle,
							  PURPLE_CALLBACK(carbons_sending_xmlnode_cb), NULL);
	}

	xmlnode *iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "set");
	xmlnode_set_attrib(iq, "id", "adium-carbons-enable");

	xmlnode *enable = xmlnode_new_child(iq, "enable");
	xmlnode_set_namespace(enable, NS_CARBONS);

	purple_signal_emit(jabber, "jabber-sending-xmlnode", gc, &iq);
	if (iq)
		xmlnode_free(iq);
}

void configureAdiumPurpleCarbons(void)
{
	purple_signal_connect(purple_connections_get_handle(), "signed-on", &adium_purple_carbons_handle,
						  PURPLE_CALLBACK(carbons_signed_on_cb), NULL);
}
