/* Shows what goes over the wire while signing on, stanza by stanza.
 *
 * Work on XEP-0198 ends at every step with the same question: what did we send and what came
 * back. The answers so far were guesses read out of the source, and at least one of them was
 * wrong, because the fact that the test server did not offer stream management at all was only
 * noticed once somebody looked.
 *
 * libpurple's own nullclient cannot do this: it asks for its account at a terminal and will not
 * be fed from a script. Hence this one, which loads the same libpurple the application does,
 * signs on to the test server and prints everything the Jabber module writes into its log.
 *
 *   smwire [seconds] [drop after] [sign on again after]   default 12, never, 1
 *
 * It connects without encryption, because the test server allows that and the question about the
 * self signed certificate would otherwise need a user interface, which there is none of here.
 * The account lives in a directory of its own under /tmp and does not touch the application's
 * settings.
 */
#include <glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libpurple/libpurple.h>
/* For JabberStream, so the socket can be pulled out from under the connection. */
#include <libpurple/jabber.h>
#include <unistd.h>
#include <sys/socket.h>
#include <signal.h>

#define UI_ID "smwire"

/* These two belong to pidgin's glue between glib and libpurple, not to libpurple itself;
   nullclient carries them for the same reason. */
#define PURPLE_GLIB_READ_COND  (G_IO_IN | G_IO_HUP | G_IO_ERR)
#define PURPLE_GLIB_WRITE_COND (G_IO_OUT | G_IO_HUP | G_IO_ERR | G_IO_NVAL)

static int seconds = 12;
static int dropAfter = 0;
static int reconnectAfter = 1;
static PurpleAccount *theAccount = NULL;

/* --- The loop, the way nullclient runs one too ------------------------------------------- */

typedef struct {
	PurpleInputFunction function;
	guint result;
	gpointer data;
} IoClosure;

static gboolean io_invoke(GIOChannel *source, GIOCondition condition, gpointer data)
{
	IoClosure *closure = data;
	PurpleInputCondition purple_cond = 0;

	if (condition & PURPLE_GLIB_READ_COND)  purple_cond |= PURPLE_INPUT_READ;
	if (condition & PURPLE_GLIB_WRITE_COND) purple_cond |= PURPLE_INPUT_WRITE;

	closure->function(closure->data, g_io_channel_unix_get_fd(source), purple_cond);
	return TRUE;
}

static guint input_add(gint fd, PurpleInputCondition condition,
                       PurpleInputFunction function, gpointer data)
{
	IoClosure *closure = g_new0(IoClosure, 1);
	GIOChannel *channel;
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

/* --- What the Jabber module logs is exactly the wire ------------------------------------- */

static void say(PurpleDebugLevel level, const char *category, const char *text)
{
	/* Everything else is internals and would bury the picture. */
	if (!purple_strequal(category, "jabber") && !purple_strequal(category, "XEP-0198"))
		return;

	printf("%-9s %s", category, text);
	fflush(stdout);
}

static PurpleDebugUiOps debug_ops = { say, NULL, NULL, NULL, NULL, NULL };

/* --- Just enough of an interface that libpurple does not ask for one --------------------- */

static gboolean sign_on_again(gpointer data)
{
	printf("\n== signing on again\n");
	fflush(stdout);
	/* set_enabled is no good: the account is still enabled after a break, so the call does
	   nothing. The connection wants to be started directly. */
	purple_account_connect(theAccount);
	return FALSE;
}

static void connection_report(PurpleConnection *gc, PurpleConnectionError reason,
                              const char *description)
{
	printf("\n== the connection went down: %s\n", description ? description : "no reason given");
	fflush(stdout);

	/* Exactly what Adium otherwise does: it notices the break and signs on again. One second
	   of distance is enough here for libpurple to finish clearing up. */
	if (dropAfter > 0)
		g_timeout_add_seconds(reconnectAfter, sign_on_again, NULL);
}

/*! Pull the socket out from under the connection.
 *
 * Disconnecting cleanly is no good: libpurple sends a </stream:stream> while doing so, and by
 * XEP-0198 section 7 that destroys the session at once and for good. A network that breaks away
 * says nothing, and that is exactly what is staged here. */
static gboolean pull_the_plug(gpointer data)
{
	PurpleConnection *gc = purple_account_get_connection(theAccount);
	JabberStream *js = gc ? purple_connection_get_protocol_data(gc) : NULL;

	if (js == NULL || js->fd < 0) {
		printf("\n== nothing to pull: no open stream\n");
		return FALSE;
	}

	printf("\n== pulling the plug on the socket, without a closing tag\n");
	fflush(stdout);
	/* shutdown and not close: a closed descriptor does not reliably wake the read watch,
	   while a shut down socket reports end of file at once and libpurple sees the break exactly
	   as it would with a network that has gone away. */
	shutdown(js->fd, SHUT_RDWR);

	return FALSE;
}

static PurpleConnectionUiOps connection_ops = {
	NULL, NULL, NULL, NULL, NULL, NULL, NULL, connection_report, NULL, NULL, NULL
};

static void ui_init(void)
{
	purple_connections_set_ui_ops(&connection_ops);
}

static PurpleCoreUiOps core_ops = { NULL, NULL, ui_init, NULL, NULL, NULL, NULL, NULL };

/*! Exactly the archive query Adium sends, so that it can be told whether the fault is the
    query or the server. Against a Prosody with mod_mam an answer has to come back. */
static gboolean ask_the_archive(gpointer data)
{
	PurpleConnection *gc = purple_account_get_connection(theAccount);
	JabberStream *js = gc ? purple_connection_get_protocol_data(gc) : NULL;
	xmlnode *iq, *query, *x, *field, *value, *set, *max;

	if (js == NULL)
		return FALSE;

	printf("\n== asking the archive\n");
	fflush(stdout);

	iq = xmlnode_new("iq");
	xmlnode_set_attrib(iq, "type", "set");
	xmlnode_set_attrib(iq, "to", "adium@localhost");
	xmlnode_set_attrib(iq, "id", "smwire-mam-1");

	query = xmlnode_new_child(iq, "query");
	xmlnode_set_namespace(query, "urn:xmpp:mam:2");
	xmlnode_set_attrib(query, "queryid", "smwire-mam-1");

	x = xmlnode_new_child(query, "x");
	xmlnode_set_namespace(x, "jabber:x:data");
	xmlnode_set_attrib(x, "type", "submit");
	field = xmlnode_new_child(x, "field");
	xmlnode_set_attrib(field, "var", "FORM_TYPE");
	xmlnode_set_attrib(field, "type", "hidden");
	value = xmlnode_new_child(field, "value");
	xmlnode_insert_data(value, "urn:xmpp:mam:2", -1);
	field = xmlnode_new_child(x, "field");
	xmlnode_set_attrib(field, "var", "with");
	value = xmlnode_new_child(field, "value");
	xmlnode_insert_data(value, "peer@localhost", -1);

	set = xmlnode_new_child(query, "set");
	xmlnode_set_namespace(set, "http://jabber.org/protocol/rsm");
	max = xmlnode_new_child(set, "max");
	xmlnode_insert_data(max, "25", -1);
	xmlnode_new_child(set, "before");

	jabber_send(js, iq);
	xmlnode_free(iq);

	return FALSE;
}

static gboolean time_is_up(gpointer data)
{
	printf("\n== %d seconds are up\n", seconds);
	g_main_loop_quit(data);
	return FALSE;
}

int main(int argc, char *argv[])
{
	PurpleAccount *account;
	GMainLoop *loop;
	char *dir;

	/* Writing into a socket that has gone away sends SIGPIPE, and that ends the process
	   without a word. Every serious client ignores it and reads the error from the return value
	   instead; without that, this harness dies exactly when things get interesting. */
	signal(SIGPIPE, SIG_IGN);

	if (argc > 1) seconds = atoi(argv[1]);
	if (seconds <= 0) seconds = 12;
	if (argc > 2) dropAfter = atoi(argv[2]);
	if (argc > 3) reconnectAfter = atoi(argv[3]);
	if (reconnectAfter <= 0) reconnectAfter = 1;

	/* A directory of its own, so that nothing hangs on the application's settings. */
	dir = g_strdup_printf("%s/adium-smwire", g_get_tmp_dir());
	purple_util_set_user_dir(dir);
	g_free(dir);

	/* The interface gets everything, but libpurple should not also write to stderr:
	   otherwise every line stands there twice, once filtered and once raw. */
	purple_debug_set_ui_ops(&debug_ops);
	purple_debug_set_enabled(FALSE);
	purple_eventloop_set_ui_ops(&loop_ops);
	purple_core_set_ui_ops(&core_ops);

	if (!purple_core_init(UI_ID)) {
		printf("purple_core_init failed\n");
		return 1;
	}

	purple_set_blist(purple_blist_new());
	purple_blist_load();

	account = purple_account_new("adium@localhost", "prpl-jabber");
	purple_account_set_password(account, "adium-pw");
	purple_account_set_string(account, "connect_server", "127.0.0.1");
	purple_account_set_int(account, "port", 5222);
	/* Without encryption, and therefore PLAIN has to be allowed in the clear. The test server
	   permits both; against a real server that would not be a good idea. */
	purple_account_set_string(account, "connection_security", "none");
	purple_account_set_bool(account, "auth_plain_in_clear", TRUE);

	purple_accounts_add(account);
	purple_account_set_enabled(account, UI_ID, TRUE);

	theAccount = account;

	loop = g_main_loop_new(NULL, FALSE);
	if (dropAfter > 0)
		g_timeout_add_seconds(dropAfter, pull_the_plug, NULL);
	if (getenv("SMWIRE_ASK_ARCHIVE"))
		g_timeout_add_seconds(4, ask_the_archive, NULL);
	g_timeout_add_seconds(seconds, time_is_up, loop);
	g_main_loop_run(loop);

	return 0;
}
