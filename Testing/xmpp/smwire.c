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
 *   smwire [Sekunden] [Abriss nach] [Neuanmeldung nach]   voreingestellt 12, keiner, 1
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
/* Fuer JabberStream, um den Socket unter der Verbindung wegziehen zu koennen. */
#include <libpurple/jabber.h>
#include <unistd.h>
#include <sys/socket.h>
#include <signal.h>

#define UI_ID "smwire"

/* Diese beiden gehoeren zu pidgins Glue zwischen glib und libpurple, nicht zu libpurple selbst;
   nullclient traegt sie aus demselben Grund bei sich. */
#define PURPLE_GLIB_READ_COND  (G_IO_IN | G_IO_HUP | G_IO_ERR)
#define PURPLE_GLIB_WRITE_COND (G_IO_OUT | G_IO_HUP | G_IO_ERR | G_IO_NVAL)

static int seconds = 12;
static int dropAfter = 0;
static int reconnectAfter = 1;
static PurpleAccount *theAccount = NULL;

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

static gboolean sign_on_again(gpointer data)
{
	printf("\n== signing on again\n");
	fflush(stdout);
	/* set_enabled taugt nicht: das Konto ist nach einem Abriss weiterhin aktiviert, der Aufruf
	   ist also folgenlos. Die Verbindung will direkt angestossen werden. */
	purple_account_connect(theAccount);
	return FALSE;
}

static void connection_report(PurpleConnection *gc, PurpleConnectionError reason,
                              const char *description)
{
	printf("\n== the connection went down: %s\n", description ? description : "no reason given");
	fflush(stdout);

	/* Genau das tut Adium sonst: es merkt den Abriss und meldet sich neu an. Hier reicht eine
	   Sekunde Abstand, damit libpurple mit dem Aufraeumen fertig ist. */
	if (dropAfter > 0)
		g_timeout_add_seconds(reconnectAfter, sign_on_again, NULL);
}

/*! Den Socket unter der Verbindung wegziehen.
 *
 * Ein sauberes Trennen taugt nicht: libpurple sendet dabei ein </stream:stream>, und nach
 * XEP-0198 Abschnitt 7 zerstoert das die Sitzung sofort und endgueltig. Ein Netz, das
 * wegbricht, sagt nichts, und genau das wird hier nachgestellt. */
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
	/* shutdown und nicht close: ein geschlossener Deskriptor weckt die Leseueberwachung nicht
	   zuverlaessig, waehrend ein abgeschaltetes Socket sofort das Dateiende meldet und libpurple
	   den Abriss genauso sieht wie bei einem weggebrochenen Netz. */
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

	/* Schreiben in ein weggebrochenes Socket schickt SIGPIPE, und das beendet den Prozess
	   wortlos. Jeder ernsthafte Client ignoriert es und liest den Fehler stattdessen aus dem
	   Rueckgabewert; ohne das stirbt dieser Prüfstand genau dann, wenn es interessant wird. */
	signal(SIGPIPE, SIG_IGN);

	if (argc > 1) seconds = atoi(argv[1]);
	if (seconds <= 0) seconds = 12;
	if (argc > 2) dropAfter = atoi(argv[2]);
	if (argc > 3) reconnectAfter = atoi(argv[3]);
	if (reconnectAfter <= 0) reconnectAfter = 1;

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

	theAccount = account;

	loop = g_main_loop_new(NULL, FALSE);
	if (dropAfter > 0)
		g_timeout_add_seconds(dropAfter, pull_the_plug, NULL);
	g_timeout_add_seconds(seconds, time_is_up, loop);
	g_main_loop_run(loop);

	return 0;
}
