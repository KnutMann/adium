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

#import "adiumPurpleJingle.h"

/*
 * The stream side of calls: Jingle IQs in, Jingle IQs out.
 *
 * The same architecture as carbons and CSI: the jabber protocol's xmlnode signals
 * carry every stanza past us. A Jingle iq addressed to a registered handler is
 * ACKed the way XEP-0166 demands (an empty result, before anything else happens),
 * swallowed so the protocol's service-unavailable answer never fires, and handed
 * over as a string, which is the shape the session machinery speaks. Outgoing
 * elements take the sanctioned injection road: emitting the sending signal, whose
 * highest-priority listener is the protocol's own sender.
 */

#define NS_JINGLE "urn:xmpp:jingle:1"
#define NS_JINGLE_MESSAGE "urn:xmpp:jingle-message:0"
#define NS_JINGLE_RTP "urn:xmpp:jingle:apps:rtp:1"
#define NS_HINTS "urn:xmpp:hints"

static int adium_purple_jingle_handle;
static id<AdiumJingleStanzaHandler> jingleHandler = nil;

static PurplePlugin *jingle_jabber_prpl(void)
{
	return purple_find_prpl("prpl-jabber");
}

void adiumPurpleJingleSetHandler(id<AdiumJingleStanzaHandler> handler)
{
	if (jingleHandler != handler) {
		[jingleHandler release];
		jingleHandler = [handler retain];
	}
}

#pragma mark Receiving

/*! @brief The ringing language: propose, proceed, reject, retract and accept ride in messages */
static gboolean jingle_handle_message(PurpleConnection *gc, xmlnode *message)
{
	if (![jingleHandler respondsToSelector:@selector(handleJingleMessageOfKind:sid:from:offersVideo:onAccount:)])
		return FALSE;

	static const char *kinds[] = { "propose", "proceed", "reject", "retract", "accept", NULL };
	xmlnode *child = NULL;
	const char *kind = NULL;

	for (int index = 0; kinds[index] && !child; index++) {
		child = xmlnode_get_child_with_namespace(message, kinds[index], NS_JINGLE_MESSAGE);
		kind = kinds[index];
	}
	if (!child)
		return FALSE;

	const char *from = xmlnode_get_attrib(message, "from");
	const char *sid = xmlnode_get_attrib(child, "id");
	if (!from || !sid)
		return FALSE;

	//A propose says what it offers; anything with a video description rings as a video call
	BOOL offersVideo = NO;
	for (xmlnode *description = xmlnode_get_child_with_namespace(child, "description", NS_JINGLE_RTP);
		 description; description = xmlnode_get_next_twin(description)) {
		const char *media = xmlnode_get_attrib(description, "media");
		if (media && !strcmp(media, "video"))
			offersVideo = YES;
	}

	gboolean owned = FALSE;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	owned = [jingleHandler handleJingleMessageOfKind:[NSString stringWithUTF8String:kind]
												 sid:[NSString stringWithUTF8String:sid]
												from:[NSString stringWithUTF8String:from]
										 offersVideo:offersVideo
										   onAccount:accountLookup(purple_connection_get_account(gc))];
	[pool release];
	return owned;
}

static void jingle_receiving_xmlnode_cb(PurpleConnection *gc, xmlnode **packet, gpointer data)
{
	//Any handler on this signal may have consumed the stanza and left NULL behind
	if (!packet || !*packet || !jingleHandler)
		return;

	xmlnode *iq = *packet;

	if (!strcmp(iq->name, "message")) {
		if (jingle_handle_message(gc, iq)) {
			xmlnode_free(*packet);
			*packet = NULL;
		}
		return;
	}

	if (strcmp(iq->name, "iq"))
		return;

	const char *type = xmlnode_get_attrib(iq, "type");
	if (!type || strcmp(type, "set"))
		return;

	xmlnode *jingle = xmlnode_get_child_with_namespace(iq, "jingle", NS_JINGLE);
	if (!jingle)
		return;

	const char *from = xmlnode_get_attrib(iq, "from");
	const char *iqid = xmlnode_get_attrib(iq, "id");
	const char *action = xmlnode_get_attrib(jingle, "action");
	if (!from || !iqid || !action)
		return;

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	int length = 0;
	char *text = xmlnode_to_str(jingle, &length);
	BOOL owned = [jingleHandler handleJingleElement:[NSString stringWithUTF8String:text]
											   from:[NSString stringWithUTF8String:from]
											 action:[NSString stringWithUTF8String:action]
										  onAccount:accountLookup(purple_connection_get_account(gc))];
	g_free(text);

	if (owned) {
		/* The ACK first, as XEP-0166 orders the conversation: an empty result for the
		 * iq, before any answer of substance travels in an iq of its own. */
		xmlnode *ack = xmlnode_new("iq");
		xmlnode_set_attrib(ack, "type", "result");
		xmlnode_set_attrib(ack, "to", from);
		xmlnode_set_attrib(ack, "id", iqid);

		PurplePlugin *jabber = jingle_jabber_prpl();
		if (jabber)
			purple_signal_emit(jabber, "jabber-sending-xmlnode", gc, &ack);
		if (ack)
			xmlnode_free(ack);

		xmlnode_free(*packet);
		*packet = NULL;
	}

	[pool release];
}

#pragma mark Sending

void adiumPurpleJingleSendElement(CBPurpleAccount *adiumAccount, NSString *toJid, NSString *jingleXML)
{
	PurpleAccount *account = accountLookupFromAdiumAccount(adiumAccount);
	PurpleConnection *gc = (account ? purple_account_get_connection(account) : NULL);
	PurplePlugin *jabber = jingle_jabber_prpl();

	if (!gc || !jabber)
		return;

	xmlnode *jingle = xmlnode_from_str([jingleXML UTF8String], -1);
	if (!jingle)
		return;

	static unsigned long sequence = 0;
	char *iqid = g_strdup_printf("adium-jingle-%lu", sequence++);

	xmlnode *iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "set");
	xmlnode_set_attrib(iq, "to", [toJid UTF8String]);
	xmlnode_set_attrib(iq, "id", iqid);
	g_free(iqid);
	xmlnode_insert_child(iq, jingle);

	purple_signal_emit(jabber, "jabber-sending-xmlnode", gc, &iq);
	if (iq)
		xmlnode_free(iq);
}

void adiumPurpleJingleSendMessage(CBPurpleAccount *adiumAccount, NSString *toJid, NSString *kind,
								  NSString *sid, BOOL audio, BOOL video)
{
	PurpleAccount *account = accountLookupFromAdiumAccount(adiumAccount);
	PurpleConnection *gc = (account ? purple_account_get_connection(account) : NULL);
	PurplePlugin *jabber = jingle_jabber_prpl();

	if (!gc || !jabber)
		return;

	xmlnode *message = xmlnode_new("message");
	xmlnode_set_attrib(message, "to", [toJid UTF8String]);
	xmlnode_set_attrib(message, "type", "chat");

	xmlnode *child = xmlnode_new_child(message, [kind UTF8String]);
	xmlnode_set_namespace(child, NS_JINGLE_MESSAGE);
	xmlnode_set_attrib(child, "id", [sid UTF8String]);

	if ([kind isEqualToString:@"propose"]) {
		if (audio) {
			xmlnode *description = xmlnode_new_child(child, "description");
			xmlnode_set_namespace(description, NS_JINGLE_RTP);
			xmlnode_set_attrib(description, "media", "audio");
		}
		if (video) {
			xmlnode *description = xmlnode_new_child(child, "description");
			xmlnode_set_namespace(description, NS_JINGLE_RTP);
			xmlnode_set_attrib(description, "media", "video");
		}
	}

	//Worth keeping for devices that are asleep right now
	xmlnode_set_namespace(xmlnode_new_child(message, "store"), NS_HINTS);

	purple_signal_emit(jabber, "jabber-sending-xmlnode", gc, &message);
	if (message)
		xmlnode_free(message);
}

#pragma mark Enabling

static void jingle_signed_on_cb(PurpleConnection *gc, gpointer data)
{
	PurpleAccount *account = purple_connection_get_account(gc);
	if (!purple_strequal(purple_account_get_protocol_id(account), "prpl-jabber"))
		return;

	PurplePlugin *jabber = jingle_jabber_prpl();
	if (!jabber)
		return;

	//The stanza hook binds lazily on the first jabber sign-on, like the carbons one
	static gboolean hooked = FALSE;
	if (!hooked) {
		hooked = TRUE;
		purple_signal_connect(jabber, "jabber-receiving-xmlnode", &adium_purple_jingle_handle,
							  PURPLE_CALLBACK(jingle_receiving_xmlnode_cb), NULL);
	}
}

void configureAdiumPurpleJingle(void)
{
	purple_signal_connect(purple_connections_get_handle(), "signed-on", &adium_purple_jingle_handle,
						  PURPLE_CALLBACK(jingle_signed_on_cb), NULL);
}
