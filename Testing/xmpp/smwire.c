/* Zeigt, was beim Anmelden ueber den Draht geht, Stanza fuer Stanza.
 *
 * Die Arbeit an XEP-0198 endet in jedem Schritt bei derselben Frage: was haben wir gesendet und
 * was kam zurueck. Die bisherigen Antworten darauf waren Vermutungen aus dem Quelltext, und
 * mindestens eine davon war falsch, denn dass der Testserver Stream Management ueberhaupt nicht
 * anbot, fiel erst auf, als jemand hinsah.
 *
 * libpurples eigener nullclient kann das nicht leisten: er fragt sein Konto an einem Terminal ab
 * und laesst sich nicht aus einem Skript fuettern. Also dieser hier, der dasselbe libpurple laedt
 * wie die Anwendung, sich an den Testserver anmeldet und alles ausgibt, was das Jabber-Modul in
 * sein Protokoll schreibt.
 *
 *   smwire [Sekunden]      voreingestellt 12
 *
 * Es wird ohne Verschluesselung verbunden, weil der Testserver das erlaubt und die Frage nach dem
 * selbstsignierten Zertifikat sonst eine Benutzeroberflaeche braeuchte, die es hier nicht gibt.
 * Das Konto liegt in einem eigenen Verzeichnis unter /tmp und fasst die Einstellungen der
 * Anwendung nicht an.
 */
#include <glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libpurple/libpurple.h>

#define UI_ID "smwire"

/* Diese beiden gehoeren zu pidgins Glue zwischen glib und libpurple, nicht zu libpurple selbst;
   nullclient traegt sie aus demselben Grund bei sich. */
#define PURPLE_GLIB_READ_COND  (G_IO_IN | G_IO_HUP | G_IO_ERR)
#define PURPLE_GLIB_WRITE_COND (G_IO_OUT | G_IO_HUP | G_IO_ERR | G_IO_NVAL)

static int seconds = 12;

/* --- Die Schleife, wie nullclient sie auch fuehrt ---------------------------------------- */

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

/* --- Was das Jabber-Modul protokolliert, ist genau der Draht ----------------------------- */

static void say(PurpleDebugLevel level, const char *category, const char *text)
{
	/* Alles andere ist Innenleben und wuerde das Bild zuschuetten. */
	if (!purple_strequal(category, "jabber") && !purple_strequal(category, "XEP-0198"))
		return;

	printf("%-9s %s", category, text);
	fflush(stdout);
}

static PurpleDebugUiOps debug_ops = { say, NULL, NULL, NULL, NULL, NULL };

/* --- Genug Oberflaeche, damit libpurple nicht nach einer fragt --------------------------- */

static void connection_report(PurpleConnection *gc, PurpleConnectionError reason,
                              const char *description)
{
	printf("\n== the connection failed: %s\n", description ? description : "no reason given");
	fflush(stdout);
}

static PurpleConnectionUiOps connection_ops = {
	NULL, NULL, NULL, NULL, NULL, NULL, NULL, connection_report, NULL, NULL, NULL
};

static void ui_init(void)
{
	purple_connections_set_ui_ops(&connection_ops);
}

static PurpleCoreUiOps core_ops = { NULL, NULL, ui_init, NULL, NULL, NULL, NULL, NULL };

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

	if (argc > 1) seconds = atoi(argv[1]);
	if (seconds <= 0) seconds = 12;

	/* Ein eigenes Verzeichnis, damit nichts an den Einstellungen der Anwendung haengt. */
	dir = g_strdup_printf("%s/adium-smwire", g_get_tmp_dir());
	purple_util_set_user_dir(dir);
	g_free(dir);

	/* Die Oberflaeche bekommt alles, aber libpurple soll nicht zusaetzlich nach stderr
	   schreiben: sonst steht jede Zeile zweimal da, einmal gefiltert und einmal roh. */
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
	/* Ohne Verschluesselung, und deshalb muss PLAIN im Klartext erlaubt sein. Der Testserver
	   laesst beides zu; gegen einen echten Server waere das keine gute Idee. */
	purple_account_set_string(account, "connection_security", "none");
	purple_account_set_bool(account, "auth_plain_in_clear", TRUE);

	purple_accounts_add(account);
	purple_account_set_enabled(account, UI_ID, TRUE);

	loop = g_main_loop_new(NULL, FALSE);
	g_timeout_add_seconds(seconds, time_is_up, loop);
	g_main_loop_run(loop);

	return 0;
}
