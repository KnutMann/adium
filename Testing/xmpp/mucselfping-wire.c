/* What does a real MUC service actually answer a self-ping, and does our reading of it hold?
 *
 * mucselfping-test.c puts XEP-0410's table to the rules file using stanzas the test itself
 * wrote. That proves the reading and nothing about the answers: a table copied correctly out of
 * a specification is still a guess about what comes down the wire. So this one joins a room on
 * the test server, pings its own occupant JID, walks out of the room without libpurple being
 * told, and pings again. Both answers are real, and both are handed to the very function the
 * application uses, AIMUCSelfPingVerdictForReply.
 *
 * The walking out is done by writing the unavailable presence directly rather than through
 * libpurple's chat machinery, because the point is to be out of the room while everything on
 * this side still believes otherwise. That is exactly the situation the self-ping exists for,
 * and it cannot be staged any other way.
 *
 * Needs the test server: Testing/xmpp/server.sh start. Skips cleanly when it is not there.
 */
#include <glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>

#include <libpurple/libpurple.h>
/* For JabberStream and jabber_send, so stanzas can be written without a conversation. */
#include <libpurple/jabber.h>

#include "AIMUCSelfPingRules.h"

#define UI_ID		"mucselfpingwire"
#define SERVICE		"conference.localhost"
#define NICK		"pingbot"

/* A room of this run's own. Prosody keeps a tombstone for a destroyed room and answers the
   next join of that name with <gone/>, so a fixed name would make this test work exactly
   once. Taking the room away at the end therefore has to be paired with never asking for the
   same one twice. */
static char *theRoom = NULL;
static char *theOccupant = NULL;

#define PURPLE_GLIB_READ_COND  (G_IO_IN | G_IO_HUP | G_IO_ERR)
#define PURPLE_GLIB_WRITE_COND (G_IO_OUT | G_IO_HUP | G_IO_ERR | G_IO_NVAL)

static int				 failures = 0;
static int				 checksRun = 0;
static PurpleAccount	*theAccount = NULL;
static GMainLoop		*theLoop = NULL;
static gboolean			 joined = FALSE;
static gboolean			 signedOn = FALSE;

static void check(const char *name, int ok, const char *detail)
{
	checksRun++;
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name,
	       (!ok && detail) ? "  " : "", (!ok && detail) ? detail : "");
	fflush(stdout);
	if (!ok) failures++;
}

static const char *verdictName(AIMUCSelfPingVerdict v)
{
	switch (v) {
		case AIMUCSelfPingVerdictJoined:    return "joined";
		case AIMUCSelfPingVerdictNotJoined: return "not joined";
		case AIMUCSelfPingVerdictUnknown:   return "unknown";
	}
	return "?";
}

/* --- The loop, as nullclient and smwire run one too -------------------------------------- */

typedef struct {
	PurpleInputFunction function;
	guint result;
	gpointer data;
} IoClosure;

static gboolean io_invoke(GIOChannel *source, GIOCondition condition, gpointer data)
{
	IoClosure			*closure = data;
	PurpleInputCondition purple_cond = 0;

	if (condition & PURPLE_GLIB_READ_COND)  purple_cond |= PURPLE_INPUT_READ;
	if (condition & PURPLE_GLIB_WRITE_COND) purple_cond |= PURPLE_INPUT_WRITE;

	closure->function(closure->data, g_io_channel_unix_get_fd(source), purple_cond);
	return TRUE;
}

static guint input_add(gint fd, PurpleInputCondition condition,
                       PurpleInputFunction function, gpointer data)
{
	IoClosure	*closure = g_new0(IoClosure, 1);
	GIOChannel	*channel;
	GIOCondition cond = 0;

	closure->function = function;
	closure->data = data;

	if (condition & PURPLE_INPUT_READ)  cond |= PURPLE_GLIB_READ_COND;
	if (condition & PURPLE_INPUT_WRITE) cond |= PURPLE_GLIB_WRITE_COND;

	channel = g_io_channel_unix_new(fd);
	closure->result = g_io_add_watch_full(channel, G_PRIORITY_DEFAULT, cond,
	                                      io_invoke, closure, g_free);
	g_io_channel_unref(channel);

	return closure->result;
}

static PurpleEventLoopUiOps loop_ops = {
	g_timeout_add, g_source_remove, input_add, g_source_remove,
	NULL, g_timeout_add_seconds, NULL, NULL
};

/* --- Writing stanzas without a conversation ---------------------------------------------- */

static JabberStream *stream(void)
{
	PurpleConnection *gc = purple_account_get_connection(theAccount);

	return (gc ? purple_connection_get_protocol_data(gc) : NULL);
}

static void writeStanza(xmlnode *stanza)
{
	JabberStream *js = stream();

	if (js != NULL)
		jabber_send(js, stanza);
	xmlnode_free(stanza);
}

static void sendJoin(void)
{
	xmlnode *presence = xmlnode_new("presence");
	xmlnode *x;

	xmlnode_set_attrib(presence, "to", theOccupant);
	x = xmlnode_new_child(presence, "x");
	xmlnode_set_namespace(x, "http://jabber.org/protocol/muc");

	printf("\n== joining %s as %s\n", theRoom, NICK);
	writeStanza(presence);
}

/*! Leave the room without a word to anything on this side of the socket. */
static void sendSilentPart(void)
{
	xmlnode *presence = xmlnode_new("presence");

	xmlnode_set_attrib(presence, "to", theOccupant);
	xmlnode_set_attrib(presence, "type", "unavailable");

	printf("\n== leaving the room, telling nobody here about it\n");
	writeStanza(presence);
}

static void sendPingTo(const char *occupant, const char *iqId)
{
	xmlnode *iq = AIMUCSelfPingRequest(occupant, iqId);
	char	*wire = xmlnode_to_str(iq, NULL);

	printf("\n== self-ping %s: %s\n", iqId, wire);
	g_free(wire);

	//The very stanza the application builds, straight onto the wire
	writeStanza(iq);
}

static void sendSelfPing(const char *iqId)
{
	sendPingTo(theOccupant, iqId);
}

/*! Make the room outlast us.
 *
 * Without this the room is destroyed the moment we walk out, because we are its only
 * occupant, and the second self-ping then asks about a room that no longer exists. That is a
 * different question from the one the self-ping is for: the case worth staging is a room that
 * is still there, still has people in it, and no longer lists us. We are the room's owner,
 * having just created it, so the configuration is ours to set.
 */
static void makeRoomPersistent(void)
{
	xmlnode *iq = xmlnode_new("iq");
	xmlnode *query, *x, *field, *value;

	xmlnode_set_attrib(iq, "type", "set");
	xmlnode_set_attrib(iq, "to", theRoom);
	xmlnode_set_attrib(iq, "id", "wire-config");

	query = xmlnode_new_child(iq, "query");
	xmlnode_set_namespace(query, "http://jabber.org/protocol/muc#owner");

	x = xmlnode_new_child(query, "x");
	xmlnode_set_namespace(x, "jabber:x:data");
	xmlnode_set_attrib(x, "type", "submit");

	field = xmlnode_new_child(x, "field");
	xmlnode_set_attrib(field, "var", "FORM_TYPE");
	xmlnode_set_attrib(field, "type", "hidden");
	value = xmlnode_new_child(field, "value");
	xmlnode_insert_data(value, "http://jabber.org/protocol/muc#roomconfig", -1);

	field = xmlnode_new_child(x, "field");
	xmlnode_set_attrib(field, "var", "muc#roomconfig_persistentroom");
	value = xmlnode_new_child(field, "value");
	xmlnode_insert_data(value, "1", -1);

	printf("\n== making the room persistent, so that leaving it does not destroy it\n");
	writeStanza(iq);
}

/*! Take the room away again, so the test server is left as it was found. */
static void destroyRoom(void)
{
	xmlnode *iq = xmlnode_new("iq");
	xmlnode *query;

	xmlnode_set_attrib(iq, "type", "set");
	xmlnode_set_attrib(iq, "to", theRoom);
	xmlnode_set_attrib(iq, "id", "wire-destroy");

	query = xmlnode_new_child(iq, "query");
	xmlnode_set_namespace(query, "http://jabber.org/protocol/muc#owner");
	xmlnode_new_child(query, "destroy");

	printf("\n== taking the room away again\n");
	writeStanza(iq);
}

static void askRoomFeatures(void)
{
	xmlnode *iq = xmlnode_new("iq");
	xmlnode *query;

	xmlnode_set_attrib(iq, "type", "get");
	xmlnode_set_attrib(iq, "to", theRoom);
	xmlnode_set_attrib(iq, "id", "wire-disco");

	query = xmlnode_new_child(iq, "query");
	xmlnode_set_namespace(query, "http://jabber.org/protocol/disco#info");

	writeStanza(iq);
}

/* --- The run, driven by what comes back -------------------------------------------------- */

static gboolean pingAfterParting(gpointer data)
{
	sendSelfPing("wire-ping-2");
	return FALSE;
}

static gboolean pingTheVanishedRoom(gpointer data)
{
	char *nowhere = g_strdup_printf("adiumselfping-nosuchroom-%ld-%d@" SERVICE "/" NICK,
									(long)time(NULL), (int)getpid());

	sendPingTo(nowhere, "wire-ping-3");
	g_free(nowhere);
	return FALSE;
}

static gboolean stopNow(gpointer data)
{
	g_main_loop_quit(theLoop);
	return FALSE;
}

static gboolean giveUp(gpointer data)
{
	if (signedOn) {
		printf("\n== the server stopped answering before the run was finished\n");
		check("The whole exchange completed", 0, "timed out");
	}
	g_main_loop_quit(theLoop);
	return FALSE;
}

static void handleDisco(xmlnode *iq)
{
	xmlnode		*query = xmlnode_get_child_with_namespace(iq, "query",
												   "http://jabber.org/protocol/disco#info");
	xmlnode		*feature;
	gboolean	 optimised = FALSE;

	if (query == NULL)
		return;

	for (feature = xmlnode_get_child(query, "feature"); feature; feature = xmlnode_get_next_twin(feature)) {
		if (purple_strequal(xmlnode_get_attrib(feature, "var"),
							"http://jabber.org/protocol/muc#self-ping-optimization"))
			optimised = TRUE;
	}

	/* Not a requirement either way, only worth printing: with the optimisation the service
	   answers the ping itself, without it the ping is relayed to one of our own clients and
	   the <service-unavailable/> branch of the table is the one that matters. */
	printf("\n== this service %s the self-ping optimisation\n",
		   optimised ? "advertises" : "does not advertise");
}

static void receiving_cb(PurpleConnection *gc, xmlnode **packet, gpointer data)
{
	xmlnode		*node = (packet ? *packet : NULL);
	const char	*from, *iqId;

	if (node == NULL)
		return;

	from = xmlnode_get_attrib(node, "from");

	/* Anything at all from the room is printed. Without this a run that goes wrong says only
	   that it timed out, and the reason is on the wire nobody looked at. */
	if (from != NULL && g_str_has_prefix(from, theRoom)) {
		char *wire = xmlnode_to_str(node, NULL);
		printf("   <- %s\n", wire);
		g_free(wire);
	}

	if (purple_strequal(node->name, "presence")
		&& purple_strequal(xmlnode_get_attrib(node, "type"), "error")
		&& from != NULL && g_str_has_prefix(from, theRoom)) {
		check("The room let us in", 0, "it answered the join with an error");
		g_main_loop_quit(theLoop);
		return;
	}

	//The room confirming us: status code 110 on our own presence
	if (purple_strequal(node->name, "presence") && !joined
		&& AIMUCSelfPingPresenceHasStatusCode(node, AI_MUC_STATUS_SELF_PRESENCE)) {
		joined = TRUE;

		check("The room confirms us with status code 110",
			  purple_strequal(from, theOccupant), from);
		check("And the nickname we must ping is the resource of that presence",
			  purple_strequal(AIMUCSelfPingResourceOfJID(from), NICK),
			  AIMUCSelfPingResourceOfJID(from));

		makeRoomPersistent();
		askRoomFeatures();
		sendSelfPing("wire-ping-1");
		return;
	}

	if (!purple_strequal(node->name, "iq"))
		return;

	iqId = xmlnode_get_attrib(node, "id");
	if (iqId == NULL)
		return;

	if (purple_strequal(iqId, "wire-disco")) {
		handleDisco(node);
		return;
	}

	if (purple_strequal(iqId, "wire-ping-1")) {
		AIMUCSelfPingVerdict	 verdict = AIMUCSelfPingVerdictForReply(node);
		char					*wire = xmlnode_to_str(node, NULL);

		printf("\n== answer while joined: %s\n", wire);
		g_free(wire);

		check("A real service answers a self-ping from an occupant with \"joined\"",
			  verdict == AIMUCSelfPingVerdictJoined, verdictName(verdict));

		sendSilentPart();
		/* A moment for the service to finish removing the occupant. The part and the ping
		   are two stanzas on one stream, so ordering is guaranteed, but the removal is the
		   service's own work and the ping may otherwise overtake it. */
		g_timeout_add_seconds(1, pingAfterParting, NULL);
		return;
	}

	if (purple_strequal(iqId, "wire-ping-2")) {
		AIMUCSelfPingVerdict	 verdict = AIMUCSelfPingVerdictForReply(node);
		char					*wire = xmlnode_to_str(node, NULL);
		xmlnode					*error = xmlnode_get_child(node, "error");

		printf("\n== answer after leaving: %s\n", wire);
		g_free(wire);

		check("A self-ping from a non-occupant comes back as an error",
			  purple_strequal(xmlnode_get_attrib(node, "type"), "error"),
			  xmlnode_get_attrib(node, "type"));

		/* XEP-0410: "The recommended error code is <not-acceptable/>". Checked separately
		   from the verdict, because the verdict must come out as "not joined" whichever of
		   the three conditions the service picked. */
		if (error != NULL) {
			gboolean notAcceptable = (xmlnode_get_child_with_namespace(error, "not-acceptable",
													"urn:ietf:params:xml:ns:xmpp-stanzas") != NULL);
			printf("== the condition is%s the recommended not-acceptable\n",
				   notAcceptable ? "" : " NOT");
		}

		check("And our reading of that real answer is \"not joined\", which is what triggers a rejoin",
			  verdict == AIMUCSelfPingVerdictNotJoined, verdictName(verdict));

		destroyRoom();
		g_timeout_add_seconds(1, pingTheVanishedRoom, NULL);
		return;
	}

	if (purple_strequal(iqId, "wire-ping-3")) {
		AIMUCSelfPingVerdict	 verdict = AIMUCSelfPingVerdictForReply(node);
		xmlnode					*error = xmlnode_get_child(node, "error");
		gboolean				 itemNotFound = (error && xmlnode_get_child_with_namespace(error,
										"item-not-found", "urn:ietf:params:xml:ns:xmpp-stanzas"));
		char					*wire = xmlnode_to_str(node, NULL);

		printf("\n== answer from a room that was never created: %s\n", wire);
		g_free(wire);

		/* Worth pinning down, because it was a surprise and it is the one hole in the
		   scheme. Which condition a non-occupant gets depends on the room: while the room
		   exists it is <not-acceptable/>, and for a room that does not exist at all it is
		   <item-not-found/>. XEP-0410 reads <item-not-found/> as "joined, the occupant just
		   changed their name", so a room that evaporated after we were dropped from it is
		   never rejoined by the self-ping. That is the specification's own reading rather
		   than a fault in ours, and it costs little, since a room that is gone is one
		   nobody else is sitting in either. A room destroyed by its owner is a third case
		   again: Prosody leaves a tombstone and answers <gone/>, which falls under "any
		   other error" and does lead to a rejoin. */
		check("A room that was never created answers item-not-found", itemNotFound, NULL);
		check("Which XEP-0410 reads as \"joined\", so a vanished room is never rejoined",
			  verdict == AIMUCSelfPingVerdictJoined, verdictName(verdict));

		g_timeout_add_seconds(1, stopNow, NULL);
		return;
	}
}

static void signed_on_cb(PurpleConnection *gc, gpointer data)
{
	signedOn = TRUE;
	sendJoin();
}

static void connection_report(PurpleConnection *gc, PurpleConnectionError reason,
                              const char *description)
{
	printf("\n== the connection went down: %s\n", description ? description : "no reason given");
	fflush(stdout);
	g_main_loop_quit(theLoop);
}

static PurpleConnectionUiOps connection_ops = {
	NULL, NULL, NULL, NULL, NULL, NULL, NULL, connection_report, NULL, NULL, NULL
};

static void ui_init(void)
{
	purple_connections_set_ui_ops(&connection_ops);
}

static PurpleCoreUiOps core_ops = { NULL, NULL, ui_init, NULL, NULL, NULL, NULL, NULL };

int main(int argc, char *argv[])
{
	static int		 handle;
	PurplePlugin	*jabber;
	char			*dir;

	signal(SIGPIPE, SIG_IGN);

	printf("MUC Self-Ping against the test server\n");

	theRoom = g_strdup_printf("adiumselfping-%ld-%d@" SERVICE, (long)time(NULL), (int)getpid());
	theOccupant = g_strdup_printf("%s/%s", theRoom, NICK);

	dir = g_strdup_printf("%s/adium-mucselfping-wire", g_get_tmp_dir());
	purple_util_set_user_dir(dir);
	g_free(dir);

	purple_debug_set_enabled(FALSE);
	purple_eventloop_set_ui_ops(&loop_ops);
	purple_core_set_ui_ops(&core_ops);

	if (!purple_core_init(UI_ID)) {
		printf("purple_core_init failed\n");
		return 1;
	}

	purple_set_blist(purple_blist_new());
	purple_blist_load();

	jabber = purple_find_prpl("prpl-jabber");
	if (jabber == NULL) {
		printf("the jabber protocol is not loaded\n");
		return 1;
	}
	purple_signal_connect(jabber, "jabber-receiving-xmlnode", &handle,
						  PURPLE_CALLBACK(receiving_cb), NULL);
	purple_signal_connect(purple_connections_get_handle(), "signed-on", &handle,
						  PURPLE_CALLBACK(signed_on_cb), NULL);

	theAccount = purple_account_new("adium@localhost", "prpl-jabber");
	purple_account_set_password(theAccount, "adium-pw");
	purple_account_set_string(theAccount, "connect_server", "127.0.0.1");
	purple_account_set_int(theAccount, "port", 5222);
	//Without encryption, which the test server allows and a real server should not
	purple_account_set_string(theAccount, "connection_security", "none");
	purple_account_set_bool(theAccount, "auth_plain_in_clear", TRUE);

	purple_accounts_add(theAccount);
	purple_account_set_enabled(theAccount, UI_ID, TRUE);

	theLoop = g_main_loop_new(NULL, FALSE);
	g_timeout_add_seconds(20, giveUp, NULL);
	g_main_loop_run(theLoop);

	if (!signedOn) {
		printf("\nSKIPPED: could not sign on to the test server. "
		       "Start it with Testing/xmpp/server.sh start\n");
		return 0;
	}

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
}
