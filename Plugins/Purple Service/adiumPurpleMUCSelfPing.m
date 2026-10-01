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

#import "adiumPurpleMUCSelfPing.h"
#import "AIMUCSelfPingRules.h"
#import "AMPurpleJabberSend.h"
#import "CBPurpleAccount.h"
#import <Adium/AIChat.h>
#import <libpurple/chat.h>

/*
 * MUC Self-Ping (XEP-0410) and MUC status code 333 for the jabber protocol.
 *
 * Two ways of noticing that a group chat we believe we are sitting in has let go of us,
 * and one way of getting back into it.
 *
 * A room can drop an occupant without the occupant hearing about it. The usual cause is a
 * server to server link that broke and came back: the room removed us, the removal notice
 * never arrived, and from here the window still looks like a room we are in. Messages are
 * typed into it and go nowhere.
 *
 * The loud case is XEP-0045's status code 333, which a service adds to the unavailable
 * presence when it removes an occupant over a technical problem. libpurple knows nothing
 * of 333, so the presence reads as an ordinary departure and the room quietly goes dead.
 * Here the code is recognised and answered with a rejoin. Some services put a kick code
 * next to it, which XEP-0045 says to ignore, so the 307 is taken off the stanza before
 * libpurple can print "You have been kicked" about a kick that never happened.
 *
 * The quiet case is what the self-ping is for. After a room has said nothing for a while,
 * a ping goes to our own occupant JID in it. The answer says whether we are still an
 * occupant, and only a clear no leads to a rejoin; anything inconclusive waits for the
 * next sweep. The rules for reading those answers are in AIMUCSelfPingRules.c, away from
 * all of this, so that they can be tested against the specification's own table.
 *
 * Silence is the trigger, and not a resumed stream, although a resumed stream is what
 * first made this look necessary. A resumption comes in on a brand new JabberStream: the
 * <resume/> goes out in place of the resource bind, from jabber_stream_features_parse, and
 * js->chats was made empty a moment earlier in jabber_login. So at the instant the server
 * says <resumed/> the protocol holds no rooms, there is nothing to ping, and a sweep there
 * would send nothing. What happens instead is that jabber_sm_resumed moves the stream to
 * CONNECTED, which reaches -[AIAbstractAccount didConnect], and that rejoins every open
 * group chat without asking anybody. The ping could not have changed that outcome. Where
 * it does change the outcome is in the middle of a long connection, which is where the
 * removals this is about actually happen and where the room is still ours to ask about.
 * XEP-0410 asks for exactly that, "after an adequate amount of silence from a given MUC
 * (e.g. 15 minutes)".
 *
 * Our occupant nickname in a room is taken from the room's own self-presence rather than
 * from libpurple's idea of it: purple_conv_chat_set_nick stores the nickname through
 * purple_normalize, and a ping sent to a case-folded nickname is a ping to an occupant JID
 * that does not exist. The resource of a presence carrying status code 110 is the
 * nickname spelled the way the service spells it, which is the only spelling worth
 * pinging.
 *
 * Everything is on the Adium side. The protocol offers the two xmlnode signals, the rejoin
 * is the one Adium already performs after a reconnection, and nothing here needs a
 * libpurple change.
 */

/*! How often the rooms of one connection are looked over */
#define SWEEP_INTERVAL_SECONDS	300
/*! How long a room may say nothing before it is asked whether we are still in it */
#define ROOM_SILENCE_SECONDS	900
/*! Marks the iq ids that are ours, so that another extension's ping is left alone */
#define SELF_PING_ID_PREFIX		"adium-muc-selfping-"

static int adium_purple_muc_selfping_handle;

/*! One room we believe we are in */
typedef struct {
	char	*roomJid;			//Bare room JID, the name the conversation goes by
	char	*ownNick;			//Our occupant nickname, as the service spelled it
	time_t	 lastHeard;			//When anything last arrived from this room
	char	*pendingPingId;		//The id of a ping still waiting for its answer, or NULL
	guint	 rejoinAttempts;	//Rejoins in a row without the room coming back
	time_t	 lastRejoinAt;
} AIMUCRoomWatch;

/*! The rooms of one connection, and the timer that looks them over */
typedef struct {
	guint		 sweepTimer;
	GHashTable	*rooms;			//char *roomJid -> AIMUCRoomWatch *
} AIMUCConnectionWatch;

//PurpleConnection * -> AIMUCConnectionWatch *
static GHashTable *selfping_connections = NULL;

#pragma mark Bookkeeping

static void selfping_room_free(gpointer r)
{
	AIMUCRoomWatch *room = r;

	g_free(room->roomJid);
	g_free(room->ownNick);
	g_free(room->pendingPingId);
	g_free(room);
}

static void selfping_connection_free(gpointer w)
{
	AIMUCConnectionWatch *watch = w;

	/* Adium never turns GLib's main context, so these are purple timers and have to be
	   removed through purple. One left behind would fire against a freed connection. */
	if (watch->sweepTimer != 0)
		purple_timeout_remove(watch->sweepTimer);

	g_hash_table_destroy(watch->rooms);
	g_free(watch);
}

static AIMUCConnectionWatch *selfping_watch_for(PurpleConnection *gc)
{
	return (selfping_connections ? g_hash_table_lookup(selfping_connections, gc) : NULL);
}

/*!
 * @brief The record for one room, made if this is the first we hear of it
 */
static AIMUCRoomWatch *selfping_room_for(AIMUCConnectionWatch *watch, const char *roomJid, gboolean create)
{
	AIMUCRoomWatch *room = g_hash_table_lookup(watch->rooms, roomJid);

	if (room == NULL && create) {
		room = g_new0(AIMUCRoomWatch, 1);
		room->roomJid = g_strdup(roomJid);
		room->lastHeard = time(NULL);
		g_hash_table_insert(watch->rooms, room->roomJid, room);
	}

	return room;
}

/*!
 * @brief The room waiting on this iq id, or NULL if the id is not one of ours
 */
static AIMUCRoomWatch *selfping_room_awaiting(AIMUCConnectionWatch *watch, const char *iqId)
{
	GHashTableIter	 iter;
	gpointer		 key, value;

	g_hash_table_iter_init(&iter, watch->rooms);
	while (g_hash_table_iter_next(&iter, &key, &value)) {
		AIMUCRoomWatch *room = value;

		if (room->pendingPingId && purple_strequal(room->pendingPingId, iqId))
			return room;
	}

	return NULL;
}

/*!
 * @brief The group chat conversation for one room on one connection, or NULL
 */
static PurpleConversation *selfping_conversation_for(PurpleConnection *gc, const char *roomJid)
{
	return purple_find_conversation_with_account(PURPLE_CONV_TYPE_CHAT, roomJid,
												 purple_connection_get_account(gc));
}

#pragma mark Rejoining

/*! What a deferred rejoin needs to know once the stanza that caused it is out of the way */
typedef struct {
	PurpleConnection	*gc;
	char				*roomJid;
} AIMUCRejoinRequest;

/*!
 * @brief Put one room back together, after the stanza that lost it has been processed
 *
 * Deferred for two reasons. A rejoin started from inside the receiving signal would run
 * before the protocol had seen the stanza, which in the 333 case is what tears the old
 * room down; and the teardown is the very thing that makes the rejoin possible, because
 * jabber_chat_new refuses to make a room that js->chats already holds and jabber_join_chat
 * then sends no presence at all.
 */
static gboolean selfping_rejoin_now(gpointer data)
{
	AIMUCRejoinRequest	*request = data;
	PurpleConnection	*gc = request->gc;
	PurpleConversation	*conv;
	JabberChat			*jabberChat;
	AIChat				*chat;

	/* The connection may have gone in the moment between. Its watch going away is how we
	   know, since it is dropped the instant the account signs off. */
	if (selfping_watch_for(gc) == NULL) {
		AILog(@"adiumPurpleMUCSelfPing: not rejoining %s, the connection is gone", request->roomJid);
		goto done;
	}

	conv = selfping_conversation_for(gc, request->roomJid);
	if (conv == NULL) {
		AILog(@"adiumPurpleMUCSelfPing: not rejoining %s, the conversation is gone", request->roomJid);
		goto done;
	}

	chat = (AIChat *)conv->ui_data;
	if (chat == nil || ![chat.account isKindOfClass:[CBPurpleAccount class]]) {
		AILog(@"adiumPurpleMUCSelfPing: not rejoining %s, no chat of ours behind it", request->roomJid);
		goto done;
	}

	/* A room the self-ping found us out of is one the protocol still believes in, because
	   it never saw us leave. It has to let go before a join presence will be sent. The
	   order is the protocol's own, from handle_presence_chat: tell the core we left, then
	   drop the room. After a 333 the protocol has already done both and there is nothing
	   left to find here. */
	jabberChat = jabber_chat_find_by_conv(conv);
	if (jabberChat != NULL) {
		serv_got_chat_left(gc, purple_conv_chat_get_id(PURPLE_CONV_CHAT(conv)));
		jabber_chat_destroy(jabberChat);
	}

	AILog(@"adiumPurpleMUCSelfPing: rejoining %s", request->roomJid);
	[(CBPurpleAccount *)chat.account rejoinChat:chat];

done:
	g_free(request->roomJid);
	g_free(request);

	return FALSE;
}

/*!
 * @brief Ask for a rejoin of this room, unless it has had its chances
 */
static void selfping_request_rejoin(PurpleConnection *gc, AIMUCRoomWatch *room)
{
	AIMUCRejoinRequest	*request;
	time_t				 now = time(NULL);

	if (!AIMUCSelfPingRejoinAllowed(room->rejoinAttempts, room->lastRejoinAt, now)) {
		AILog(@"adiumPurpleMUCSelfPing: %s has refused %u rejoins, leaving it alone",
			  room->roomJid, room->rejoinAttempts);
		return;
	}

	room->rejoinAttempts++;
	room->lastRejoinAt = now;

	/* The room is being rebuilt, so what we knew about it is stale. Above all the ping
	   must not be answered against the new room with the old id. */
	g_free(room->pendingPingId);
	room->pendingPingId = NULL;
	room->lastHeard = now;

	request = g_new0(AIMUCRejoinRequest, 1);
	request->gc = gc;
	request->roomJid = g_strdup(room->roomJid);

	/* One millisecond rather than none: Adium's event loop turns a purple timeout into a
	   dispatch source timer, and a dispatch timer with an interval of zero is a repeating
	   timer that repeats as fast as it can. The callback returning FALSE cancels it either
	   way, but there is no reason to lean on that. */
	purple_timeout_add(1, selfping_rejoin_now, request);
}

#pragma mark Pinging

static void selfping_send_ping(PurpleConnection *gc, AIMUCRoomWatch *room)
{
	static guint	 counter = 0;
	char			*occupantJid;
	xmlnode			*iq;

	if (room->ownNick == NULL)
		return;

	g_free(room->pendingPingId);
	room->pendingPingId = g_strdup_printf(SELF_PING_ID_PREFIX "%u", ++counter);

	occupantJid = g_strdup_printf("%s/%s", room->roomJid, room->ownNick);
	iq = AIMUCSelfPingRequest(occupantJid, room->pendingPingId);

	AILog(@"adiumPurpleMUCSelfPing: pinging %s", occupantJid);

	//Takes the stanza, counts it for XEP-0198, and frees it
	AMPurpleJabberSend(gc, iq);

	g_free(occupantJid);
}

/*!
 * @brief Act on the answer to a ping
 */
static void selfping_apply_verdict(PurpleConnection *gc, AIMUCRoomWatch *room, AIMUCSelfPingVerdict verdict)
{
	g_free(room->pendingPingId);
	room->pendingPingId = NULL;

	switch (verdict) {
		case AIMUCSelfPingVerdictJoined:
			/* Still in the room, which is also the freshest thing we could have heard
			   from it. Nothing more is owed for another silence. */
			room->lastHeard = time(NULL);
			room->rejoinAttempts = 0;
			break;

		case AIMUCSelfPingVerdictNotJoined:
			AILog(@"adiumPurpleMUCSelfPing: %s says we are not an occupant", room->roomJid);
			selfping_request_rejoin(gc, room);
			break;

		case AIMUCSelfPingVerdictUnknown:
			/* A timeout, or an unreachable remote server, tells us nothing about the
			   room. XEP-0410 is explicit that no decision may be made on it, so the
			   silence is deliberately left standing and the next sweep asks again. A
			   rejoin here would throw away a perfectly good room every time a link
			   flickered. */
			AILog(@"adiumPurpleMUCSelfPing: %s gave no answer worth acting on", room->roomJid);
			break;
	}
}

/*!
 * @brief Look over one connection's rooms, and ask the silent ones where we stand
 */
static gboolean selfping_sweep(gpointer data)
{
	PurpleConnection		*gc = data;
	AIMUCConnectionWatch	*watch = selfping_watch_for(gc);
	GHashTableIter			 iter;
	gpointer				 key, value;
	time_t					 now = time(NULL);

	if (watch == NULL)
		return FALSE;

	g_hash_table_iter_init(&iter, watch->rooms);
	while (g_hash_table_iter_next(&iter, &key, &value)) {
		AIMUCRoomWatch		*room = value;
		PurpleConversation	*conv = selfping_conversation_for(gc, room->roomJid);

		//A room whose window has closed is nobody's business any more
		if (conv == NULL) {
			g_hash_table_iter_remove(&iter);
			continue;
		}

		/* Marked as left means either we walked out, or a rejoin is on its way and the
		   room has not confirmed us yet. Neither is a case for a ping. */
		if (purple_conv_chat_has_left(PURPLE_CONV_CHAT(conv)))
			continue;

		if (room->pendingPingId != NULL) {
			/* The last ping was never answered. That is the timeout XEP-0410 describes,
			   and its reading is "unreachable", not "removed": the client may say so to
			   the user and try the ping again, which is what happens next. */
			AILog(@"adiumPurpleMUCSelfPing: %s never answered the last ping; asking again",
				  room->roomJid);
			selfping_send_ping(gc, room);
			continue;
		}

		if ((now - room->lastHeard) >= ROOM_SILENCE_SECONDS)
			selfping_send_ping(gc, room);
	}

	return TRUE;
}

#pragma mark Receiving

static void selfping_handle_presence(PurpleConnection *gc, AIMUCConnectionWatch *watch, xmlnode *node)
{
	const char	*from = xmlnode_get_attrib(node, "from");
	const char	*type = xmlnode_get_attrib(node, "type");
	const char	*nick = AIMUCSelfPingResourceOfJID(from);
	char		*roomJid;

	if (from == NULL || nick == NULL)
		return;

	roomJid = AIMUCSelfPingBareJID(from);

	if (type == NULL || purple_strequal(type, "available")) {
		/* Our own presence coming back out of a room is the room confirming us, and its
		   resource is our occupant nickname in the spelling the service uses. That is
		   both the moment we learn there is a room to watch and the moment a run of
		   failed rejoins is over. */
		if (AIMUCSelfPingPresenceHasStatusCode(node, AI_MUC_STATUS_SELF_PRESENCE)) {
			AIMUCRoomWatch *room = selfping_room_for(watch, roomJid, TRUE);

			if (!purple_strequal(room->ownNick, nick)) {
				g_free(room->ownNick);
				room->ownNick = g_strdup(nick);
			}
			room->lastHeard = time(NULL);
			room->rejoinAttempts = 0;
			g_free(room->pendingPingId);
			room->pendingPingId = NULL;

			AILog(@"adiumPurpleMUCSelfPing: %s has us as %s", roomJid, nick);
		}

		g_free(roomJid);
		return;
	}

	if (AIMUCSelfPingPresenceIsTechnicalRemoval(node)) {
		AIMUCRoomWatch	*room = selfping_room_for(watch, roomJid, FALSE);
		gboolean		 isSelf = AIMUCSelfPingPresenceIsSelf(node, (room ? room->ownNick : NULL));

		if (isSelf) {
			xmlnode *kick = AIMUCSelfPingPresenceKickStatus(node);

			/* Some services send 307 alongside 333. XEP-0045 says to ignore the kick code
			   when a 333 is there, because the removal was not anybody's doing, and
			   libpurple would otherwise write "You have been kicked" into the room.
			   Taking the child off is enough; the stanza itself is left to the protocol,
			   which is what frees it. */
			if (kick != NULL)
				xmlnode_free(kick);

			if (room == NULL) {
				//A room we never saw ourselves join. Watch it from here so the guard counts.
				room = selfping_room_for(watch, roomJid, TRUE);
				room->ownNick = g_strdup(nick);
			}

			AILog(@"adiumPurpleMUCSelfPing: %s removed us over a technical problem", roomJid);
			selfping_request_rejoin(gc, room);
		}
	}

	g_free(roomJid);
}

/*!
 * @brief Watch the stream for ping answers, room presence and signs of life
 *
 * The receiving signal hands the stanza over: a handler that consumes one has to free it
 * and leave NULL behind, because jabber_process_packet goes on with whatever is left.
 * Only our own ping answers are consumed here. Everything else is read and handed on, and
 * the one change made in place, taking a stray 307 off a 333, leaves the stanza for the
 * protocol to free as usual.
 */
static void selfping_receiving_xmlnode_cb(PurpleConnection *gc, xmlnode **packet, gpointer data)
{
	xmlnode					*node = (packet ? *packet : NULL);
	AIMUCConnectionWatch	*watch = selfping_watch_for(gc);
	const char				*from;
	char					*roomJid;
	AIMUCRoomWatch			*room;

	if (node == NULL || watch == NULL)
		return;

	if (purple_strequal(node->name, "iq")) {
		const char	*iqId = xmlnode_get_attrib(node, "id");
		const char	*iqType = xmlnode_get_attrib(node, "type");
		gboolean	 isAnswer = (purple_strequal(iqType, "result") || purple_strequal(iqType, "error"));

		/* Only an answer may be claimed. A service without the self-ping optimization
		   relays the ping to one of our own clients, and if it relays the id along with
		   it, our own ping arrives back here as an iq get. Swallowing that would leave
		   the room waiting for a result nobody will ever send, forever. Handed on, it is
		   answered by the protocol's own XEP-0199 handler, which is the right answer and
		   the one the ping was sent to collect. */
		if (iqId && isAnswer && g_str_has_prefix(iqId, SELF_PING_ID_PREFIX)) {
			room = selfping_room_awaiting(watch, iqId);

			if (room != NULL) {
				selfping_apply_verdict(gc, room, AIMUCSelfPingVerdictForReply(node));

				/* Nobody else asked for this. The protocol has no callback waiting on the
				   id, so passing it on would only earn an "unhandled iq" line. */
				xmlnode_free(node);
				*packet = NULL;
				return;
			}
		}
	}

	from = xmlnode_get_attrib(node, "from");
	if (from == NULL)
		return;

	//Anything at all out of a room counts as the room still talking to us
	roomJid = AIMUCSelfPingBareJID(from);
	room = (roomJid ? selfping_room_for(watch, roomJid, FALSE) : NULL);
	if (room != NULL)
		room->lastHeard = time(NULL);
	g_free(roomJid);

	if (purple_strequal(node->name, "presence"))
		selfping_handle_presence(gc, watch, node);
}

#pragma mark Connection lifecycle

static void selfping_signing_on_cb(PurpleConnection *gc, gpointer data)
{
	PurpleAccount	*account = purple_connection_get_account(gc);
	PurplePlugin	*jabber;

	if (!purple_strequal(purple_account_get_protocol_id(account), "prpl-jabber"))
		return;

	jabber = purple_find_prpl("prpl-jabber");
	if (!jabber)
		return;

	/* Bound on the first jabber sign-on, where the protocol is certainly registered,
	   which is more than could be said at ui-ops time. Early enough either way: a room is
	   joined after signing on, so no self-presence can have passed by already. */
	static gboolean hooked = FALSE;
	if (!hooked) {
		hooked = TRUE;
		purple_signal_connect(jabber, "jabber-receiving-xmlnode", &adium_purple_muc_selfping_handle,
							  PURPLE_CALLBACK(selfping_receiving_xmlnode_cb), NULL);
	}
}

static void selfping_signed_on_cb(PurpleConnection *gc, gpointer data)
{
	PurpleAccount			*account = purple_connection_get_account(gc);
	AIMUCConnectionWatch	*watch;

	if (!purple_strequal(purple_account_get_protocol_id(account), "prpl-jabber"))
		return;

	//A connection signing on twice without signing off would otherwise leak its timer
	g_hash_table_remove(selfping_connections, gc);

	watch = g_new0(AIMUCConnectionWatch, 1);
	watch->rooms = g_hash_table_new_full(g_str_hash, g_str_equal, NULL, selfping_room_free);
	watch->sweepTimer = purple_timeout_add_seconds(SWEEP_INTERVAL_SECONDS, selfping_sweep, gc);

	g_hash_table_insert(selfping_connections, gc, watch);
}

static void selfping_signed_off_cb(PurpleConnection *gc, gpointer data)
{
	//Takes the sweep timer with it, which is the whole reason this is not left to chance
	g_hash_table_remove(selfping_connections, gc);
}

void configureAdiumPurpleMUCSelfPing(void)
{
	void *connections = purple_connections_get_handle();

	selfping_connections = g_hash_table_new_full(g_direct_hash, g_direct_equal,
												 NULL, selfping_connection_free);

	purple_signal_connect(connections, "signing-on", &adium_purple_muc_selfping_handle,
						  PURPLE_CALLBACK(selfping_signing_on_cb), NULL);
	purple_signal_connect(connections, "signed-on", &adium_purple_muc_selfping_handle,
						  PURPLE_CALLBACK(selfping_signed_on_cb), NULL);
	purple_signal_connect(connections, "signed-off", &adium_purple_muc_selfping_handle,
						  PURPLE_CALLBACK(selfping_signed_off_cb), NULL);
}
