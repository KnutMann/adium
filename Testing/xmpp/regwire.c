/* Zeigt, was libpurple beim Registrieren eines Kontos meldet, und in welcher Reihenfolge.
 *
 * Die Registrierungsseite im Konteneditor hat drei Zustaende, die alle davon abhaengen, welche
 * Rueckrufe libpurple in welcher Folge liefert: laeuft noch, gelungen, gescheitert. Aus dem
 * Quelltext liess sich das nur erraten, und eine Vermutung war schon falsch: der Server schickt
 * ein Datenformular, und das nimmt libpurple vor den alten Feldern.
 *
 *   regwire <Name> <Passwort> [fill|raw|cancel]
 *
 *   fill    Benutzername und Passwort werden in jedes Formular eingetragen, das libpurple zeigt,
 *           und es wird bestaetigt. Das ist, was Adium tun soll.
 *   raw     Das Formular wird unveraendert bestaetigt. Das ist, was Adium heute mit dem
 *           Altfeld-Dialog tut, und was gegen ein Datenformular herauskommt, zeigt dieser Lauf.
 *   cancel  Das Formular wird abgebrochen.
 *
 * Ohne Verschluesselung, wie smwire, gegen den Testserver aus server.sh. Das Konto liegt in
 * einem eigenen Verzeichnis unter /tmp.
 */
#include <glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

#include <libpurple/libpurple.h>

#define UI_ID "regwire"

#define PURPLE_GLIB_READ_COND  (G_IO_IN | G_IO_HUP | G_IO_ERR)
#define PURPLE_GLIB_WRITE_COND (G_IO_OUT | G_IO_HUP | G_IO_ERR | G_IO_NVAL)

static const char *theName = NULL;
static const char *thePassword = NULL;
static const char *theMode = "fill";
static GMainLoop *theLoop = NULL;
static int step = 0;

static void mark(const char *what)
{
	printf("%2d. %s\n", ++step, what);
	fflush(stdout);
}

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

/* --- Nur die Registrierungs-Stanzas, der Rest ist Innenleben ----------------------------- */

static void say(PurpleDebugLevel level, const char *category, const char *text)
{
	if (!purple_strequal(category, "jabber"))
		return;
	if (!strstr(text, "jabber:iq:register") && !strstr(text, "type='error'") && !strstr(text, "type=\"error\""))
		return;
	printf("    wire: %s", text);
	fflush(stdout);
}

static PurpleDebugUiOps debug_ops = { say, NULL, NULL, NULL, NULL, NULL };

/* --- Was eine Oberflaeche zu sehen bekaeme ---------------------------------------------- */

static void *request_fields_cb(const char *title, const char *primary, const char *secondary,
                               PurpleRequestFields *fields, const char *ok_text, GCallback ok_cb,
                               const char *cancel_text, GCallback cancel_cb, PurpleAccount *account,
                               const char *who, PurpleConversation *conv, void *user_data)
{
	GList *g, *f;
	char line[256];

	g_snprintf(line, sizeof(line), "request_fields: title \"%s\", primary \"%s\"",
	           title ? title : "(none)", primary ? primary : "(none)");
	mark(line);
	if (secondary)
		printf("    instructions: %s\n", secondary);

	for (g = purple_request_fields_get_groups(fields); g; g = g->next) {
		for (f = purple_request_field_group_get_fields(g->data); f; f = f->next) {
			PurpleRequestField *field = f->data;
			const char *id = purple_request_field_get_id(field);
			int type = purple_request_field_get_type(field);
			const char *value = (type == PURPLE_REQUEST_FIELD_STRING) ? purple_request_field_string_get_value(field) : NULL;

			printf("    field %-12s type %d required %d value \"%s\"\n", id, type,
			       purple_request_field_is_required(field), value ? value : "");

			if (purple_strequal(theMode, "fill") && type == PURPLE_REQUEST_FIELD_STRING) {
				if (purple_strequal(id, "username"))
					purple_request_field_string_set_value(field, theName);
				else if (purple_strequal(id, "password"))
					purple_request_field_string_set_value(field, thePassword);
			}
		}
	}
	fflush(stdout);

	if (purple_strequal(theMode, "cancel")) {
		mark("answering the form: cancel");
		if (cancel_cb)
			((PurpleRequestFieldsCb)cancel_cb)(user_data, fields);
	} else {
		mark(purple_strequal(theMode, "fill") ? "answering the form: ok, with name and password filled in"
		                                       : "answering the form: ok, untouched");
		((PurpleRequestFieldsCb)ok_cb)(user_data, fields);
	}
	return NULL;
}

static PurpleRequestUiOps request_ops = { .request_fields = request_fields_cb };

static void *notify_message_cb(PurpleNotifyMsgType type, const char *title, const char *primary, const char *secondary)
{
	char line[512];
	g_snprintf(line, sizeof(line), "notify_message (%s): \"%s\" / \"%s\"",
	           type == PURPLE_NOTIFY_MSG_ERROR ? "error" : type == PURPLE_NOTIFY_MSG_WARNING ? "warning" : "info",
	           title ? title : "", secondary ? secondary : (primary ? primary : ""));
	mark(line);
	return NULL;
}

static void *notify_uri_cb(const char *uri)
{
	char line[512];
	g_snprintf(line, sizeof(line), "notify_uri: %s", uri);
	mark(line);
	return NULL;
}

static PurpleNotifyUiOps notify_ops = { .notify_message = notify_message_cb, .notify_uri = notify_uri_cb };

static gboolean leave(gpointer data)
{
	g_main_loop_quit(theLoop);
	return FALSE;
}

static void connected_cb(PurpleConnection *gc)
{
	mark("connection: connected (the UI would now show the account as online)");
}

static void disconnected_cb(PurpleConnection *gc)
{
	mark("connection: disconnected");
	g_timeout_add_seconds(1, leave, NULL);
}

static void progress_cb(PurpleConnection *gc, const char *text, size_t s, size_t count)
{
	char line[256];
	g_snprintf(line, sizeof(line), "connection: progress \"%s\" (%zu/%zu)", text, s, count);
	mark(line);
}

static void report_cb(PurpleConnection *gc, PurpleConnectionError reason, const char *text)
{
	char line[512];
	g_snprintf(line, sizeof(line), "connection: report_disconnect_reason %d \"%s\"", reason, text ? text : "");
	mark(line);
}

static PurpleConnectionUiOps connection_ops = {
	.connect_progress = progress_cb, .connected = connected_cb, .disconnected = disconnected_cb,
	.report_disconnect_reason = report_cb
};

static void registered_cb(PurpleAccount *account, gboolean succeeded, void *user_data)
{
	char line[256];
	g_snprintf(line, sizeof(line), "registration_cb: %s, account username now \"%s\", password \"%s\"",
	           succeeded ? "SUCCEEDED" : "FAILED",
	           purple_account_get_username(account),
	           purple_account_get_password(account) ? purple_account_get_password(account) : "(none)");
	mark(line);
}

static void ui_init(void)
{
	purple_connections_set_ui_ops(&connection_ops);
	purple_request_set_ui_ops(&request_ops);
	purple_notify_set_ui_ops(&notify_ops);
}

static PurpleCoreUiOps core_ops = { NULL, NULL, ui_init, NULL, NULL, NULL, NULL, NULL };

static gboolean time_is_up(gpointer data)
{
	mark("time is up, giving up");
	g_main_loop_quit(theLoop);
	return FALSE;
}

int main(int argc, char *argv[])
{
	PurpleAccount *account;
	char *dir, *jid;

	signal(SIGPIPE, SIG_IGN);

	if (argc < 3) {
		fprintf(stderr, "regwire <name> <password> [fill|raw|cancel]\n");
		return 2;
	}
	theName = argv[1];
	thePassword = argv[2];
	if (argc > 3) theMode = argv[3];

	dir = g_strdup_printf("%s/adium-regwire", g_get_tmp_dir());
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

	jid = g_strdup_printf("%s@localhost", theName);
	account = purple_account_new(jid, "prpl-jabber");
	g_free(jid);
	purple_account_set_password(account, thePassword);
	purple_account_set_string(account, "connect_server", "127.0.0.1");
	purple_account_set_int(account, "port", 5222);
	purple_account_set_string(account, "connection_security", "none");
	purple_account_set_bool(account, "auth_plain_in_clear", TRUE);
	purple_accounts_add(account);

	printf("registering %s@localhost, mode %s\n", theName, theMode);
	purple_account_set_register_callback(account, registered_cb, NULL);
	mark("purple_account_register called");
	purple_account_register(account);

	theLoop = g_main_loop_new(NULL, FALSE);
	g_timeout_add_seconds(10, time_is_up, NULL);
	g_main_loop_run(theLoop);

	printf("at the end: account connected %d, connecting %d, enabled %d\n",
	       purple_account_is_connected(account), purple_account_is_connecting(account),
	       purple_account_get_enabled(account, UI_ID));
	return 0;
}
