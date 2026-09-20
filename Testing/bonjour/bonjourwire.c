/* Zwei Nachbarn auf einer Maschine: beweist, dass prpl-bonjour findet und zustellt.
 *
 * Bonjour laesst sich nicht gegen den Prosody-Pruefstand testen, es gibt keinen Server,
 * gegen den man sich anmelden koennte; das Protokoll IST die Nachbarschaft. Also spielen
 * zwei Prozesse auf dieser Maschine die Nachbarn: beide melden sich bei mDNSResponder an,
 * jeder sieht den anderen auftauchen, und einer schickt dem anderen eine Nachricht ueber
 * die direkte TCP-Verbindung, die das Protokoll dafuer aufbaut.
 *
 *   bonjourwire <name> <port> send|wait [Sekunden]
 *
 * send wartet, bis irgendein Nachbar auftaucht, schickt ihm einen Gruss und meldet die
 * Zustellung; wait wartet auf den Gruss und druckt ihn. Beide enden mit 0 nur, wenn ihre
 * Haelfte wirklich passiert ist. Der Treiber dazu ist bonjour-test.sh.
 */
#include <glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

#include <libpurple/libpurple.h>

#define UI_ID "bonjourwire"

static int seconds = 25;
static const char *role = "wait";
static const char *myname = "nobody";
static PurpleAccount *theAccount = NULL;
static gboolean sent = FALSE, arrived = FALSE, connected = FALSE;
static GMainLoop *loop = NULL;

/* --- Die Schleife, wie nullclient und smwire sie auch fuehren --------------------------- */

#define PURPLE_GLIB_READ_COND  (G_IO_IN | G_IO_HUP | G_IO_ERR)
#define PURPLE_GLIB_WRITE_COND (G_IO_OUT | G_IO_HUP | G_IO_ERR | G_IO_NVAL)

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

static void say(PurpleDebugLevel level, const char *category, const char *text)
{
	if (!purple_strequal(category, "bonjour") && !purple_strequal(category, "mdns"))
		return;
	printf("[%s] %-7s %s", myname, category, text);
	fflush(stdout);
}

static PurpleDebugUiOps debug_ops = { say, NULL, NULL, NULL, NULL, NULL };

/* --- Was der Versuch wissen will --------------------------------------------------------- */

static void signed_on(PurpleConnection *gc, gpointer data)
{
	connected = TRUE;
	printf("[%s] == signed on\n", myname);
	fflush(stdout);
}

/*! Zeitversetzt schicken: wer eine Verbindung von einem Namen annimmt, den er noch nicht
    gesehen hat, weist sie als Fremden ab ("we don't like invisible buddies"). Auf einer
    Maschine findet der Sender den Wartenden oft eine Sekunde vor der Gegenrichtung, also
    bekommt die Gegenrichtung drei Sekunden Vorsprung. Unter Menschen vergeht zwischen
    Sehen und Anschreiben ohnehin mehr Zeit. */
static gboolean do_send(gpointer data)
{
	char *who = data;

	if (!sent) {
		PurpleConversation *conv = purple_conversation_new(PURPLE_CONV_TYPE_IM,
		                                                   theAccount, who);
		purple_conv_im_send(PURPLE_CONV_IM(conv), "Gruss von nebenan");
		sent = TRUE;
		printf("[%s] == greeting sent to %s\n", myname, who);
		fflush(stdout);
	}
	g_free(who);
	return FALSE;
}

/*! Ein Nachbar ist aufgetaucht. Der Sender nimmt den ersten, der nicht er selbst ist. */
static void buddy_signed_on(PurpleBuddy *buddy, gpointer data)
{
	const char *who = purple_buddy_get_name(buddy);
	static gboolean scheduled = FALSE;

	printf("[%s] == neighbour appeared: %s\n", myname, who);
	fflush(stdout);

	if (purple_strequal(role, "send") && !scheduled) {
		scheduled = TRUE;
		g_timeout_add_seconds(3, do_send, g_strdup(who));
	}
}

/*! Beim Empfaenger angekommen. received-im-msg reicht Werte, nicht Zeiger auf Zeiger;
    das waere die Signatur des Filters receiving-im-msg. */
static void received_im(PurpleAccount *account, char *sender, char *message,
                        PurpleConversation *conv, PurpleMessageFlags flags)
{
	printf("[%s] == received from %s: %s\n", myname, sender, message);
	fflush(stdout);
	arrived = TRUE;
	g_main_loop_quit(loop);
}

/*! Der Sender ist fertig, sobald die Nachricht das Haus verlassen hat. Es gibt keine
    Empfangsbestaetigung in diesem Protokoll; ob sie ankam, sagt der Empfaenger selbst. */
static void sent_im(PurpleAccount *account, const char *receiver,
                    const char *message, gpointer data)
{
	printf("[%s] == wrote out to %s\n", myname, receiver);
	fflush(stdout);
	g_timeout_add_seconds(2, (GSourceFunc)g_main_loop_quit, loop);
}

static void ui_init(void)
{
}

static PurpleCoreUiOps core_ops = { NULL, NULL, ui_init, NULL, NULL, NULL, NULL, NULL };

static gboolean time_is_up(gpointer data)
{
	printf("[%s] == %d seconds are up\n", myname, seconds);
	g_main_loop_quit(data);
	return FALSE;
}

int main(int argc, char *argv[])
{
	PurpleAccount *account;
	char *dir;
	int handle;

	signal(SIGPIPE, SIG_IGN);

	if (argc < 4) {
		fprintf(stderr, "bonjourwire <name> <port> send|wait [Sekunden]\n");
		return 2;
	}
	myname = argv[1];
	role = argv[3];
	if (argc > 4) seconds = atoi(argv[4]);
	if (seconds <= 0) seconds = 25;

	dir = g_strdup_printf("%s/adium-bonjourwire-%s", g_get_tmp_dir(), myname);
	purple_util_set_user_dir(dir);
	g_free(dir);

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

	account = purple_account_new(myname, "prpl-bonjour");
	purple_account_set_int(account, "port", atoi(argv[2]));

	purple_accounts_add(account);
	theAccount = account;

	purple_signal_connect(purple_connections_get_handle(), "signed-on",
	                      &handle, PURPLE_CALLBACK(signed_on), NULL);
	purple_signal_connect(purple_blist_get_handle(), "buddy-signed-on",
	                      &handle, PURPLE_CALLBACK(buddy_signed_on), NULL);
	purple_signal_connect(purple_conversations_get_handle(), "received-im-msg",
	                      &handle, PURPLE_CALLBACK(received_im), NULL);
	purple_signal_connect(purple_conversations_get_handle(), "sent-im-msg",
	                      &handle, PURPLE_CALLBACK(sent_im), NULL);

	purple_account_set_enabled(account, UI_ID, TRUE);

	loop = g_main_loop_new(NULL, FALSE);
	g_timeout_add_seconds(seconds, time_is_up, loop);
	g_main_loop_run(loop);

	if (purple_strequal(role, "send"))
		return (connected && sent) ? 0 : 1;
	return (connected && arrived) ? 0 : 1;
}
