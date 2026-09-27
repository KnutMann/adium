/* Two neighbours on one machine: proves that prpl-bonjour finds and delivers.
 *
 * Bonjour cannot be tested against the Prosody harness, there is no server to sign on to;
 * the protocol IS the neighbourhood. So two processes on this machine play the neighbours:
 * both register with mDNSResponder, each sees the other appear, and one sends the other a
 * message over the direct TCP connection the protocol builds for it.
 *
 *   bonjourwire <name> <port> send|wait|echo <seconds> [partner]
 *
 * send waits until the NAMED partner appears, sends them a greeting and reports the delivery;
 * wait waits for the greeting and prints it. Both exit 0 only if their half really happened.
 * The driver for this is bonjour-test.sh.
 *
 * echo stays up the whole time and answers every message that arrives with something ELSE: a
 * changing line carrying a running number and the length of what it heard. That makes it
 * possible to check both at once by hand, sending and receiving, without the answer being
 * mistaken for what was sent. Answering is never unsolicited, so the partner is optional here;
 * if one is named, only they are answered.
 *
 * The partner is demanded rather than guessed. Normally the user's real Adium runs on this
 * machine too, with a Bonjour account, and a harness that talks to the first neighbour it finds
 * would then write into a real conversation of theirs.
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
static const char *partner = NULL;
static PurpleAccount *theAccount = NULL;
static gboolean sent = FALSE, arrived = FALSE, connected = FALSE;
static int heard = 0, echoed = 0;
static GMainLoop *loop = NULL;

/* --- The loop, the way nullclient and smwire run one too -------------------------------- */

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

/* --- What the experiment wants to know --------------------------------------------------- */

static void signed_on(PurpleConnection *gc, gpointer data)
{
	connected = TRUE;
	printf("[%s] == signed on\n", myname);
	fflush(stdout);
}

/*! Send on a delay: anyone accepting a connection from a name they have not yet seen turns
    it away as a stranger ("we don't like invisible buddies"). On one machine the sender often
    finds the waiting side a second before the other direction does, so the other direction is
    given a three second head start. Between people more time passes between seeing somebody
    and writing to them anyway. */
static gboolean do_send(gpointer data)
{
	char *who = data;

	if (!sent) {
		PurpleConversation *conv = purple_conversation_new(PURPLE_CONV_TYPE_IM,
		                                                   theAccount, who);
		purple_conv_im_send(PURPLE_CONV_IM(conv), "A greeting from next door");
		sent = TRUE;
		printf("[%s] == greeting sent to %s\n", myname, who);
		fflush(stdout);
	}
	g_free(who);
	return FALSE;
}

/*! Whether this neighbour is the agreed partner. Neighbours are called "name@host.local",
    so the comparison only runs up to the at sign. Anyone with a different name is never spoken
    to: on this machine the first neighbour found is often the user's real Adium. */
static gboolean is_partner(const char *who)
{
	size_t len;

	if (!partner || !who) return FALSE;

	len = strlen(partner);

	return (g_ascii_strncasecmp(who, partner, len) == 0 && who[len] == '@');
}

/*! A neighbour has appeared. The sender takes only the agreed partner. */
static void buddy_signed_on(PurpleBuddy *buddy, gpointer data)
{
	const char *who = purple_buddy_get_name(buddy);
	static gboolean scheduled = FALSE;

	printf("[%s] == neighbour appeared: %s%s\n", myname, who,
	       (purple_strequal(role, "send") && !is_partner(who)) ? " (not the partner, ignored)" : "");
	fflush(stdout);

	if (purple_strequal(role, "send") && !scheduled && is_partner(who)) {
		scheduled = TRUE;
		g_timeout_add_seconds(3, do_send, g_strdup(who));
	}
}

/*! What the echo sends back: never what it heard, but a changing line. Whoever sees the
    answer in the window should know at a glance that it comes from here and which one in the
    sequence it is. */
struct echo_reply { char *who; char *text; };

static gboolean do_reply(gpointer data)
{
	struct echo_reply *reply = data;
	PurpleConversation *conv = purple_conversation_new(PURPLE_CONV_TYPE_IM, theAccount, reply->who);

	purple_conv_im_send(PURPLE_CONV_IM(conv), reply->text);
	echoed++;

	g_free(reply->who);
	g_free(reply->text);
	g_free(reply);

	return FALSE;
}

/*! Arrived at the receiver. received-im-msg passes values, not pointers to pointers;
    that would be the signature of the receiving-im-msg filter. */
static void received_im(PurpleAccount *account, char *sender, char *message,
                        PurpleConversation *conv, PurpleMessageFlags flags)
{
	printf("[%s] == received from %s: %s\n", myname, sender, message);
	fflush(stdout);
	arrived = TRUE;

	if (purple_strequal(role, "echo")) {
		static const char *openings[] = { "Arrived", "Heard", "Noted", "Logged", "Carry on" };
		char *plain;
		long length;
		struct echo_reply *reply;

		/* A named partner narrows things here too, even though an answer is never
		   unsolicited: whoever pins the harness to one counterpart does not want it talking
		   to anybody else. */
		if (partner && !is_partner(sender)) {
			printf("[%s] == (not the partner, no answer)\n", myname);
			fflush(stdout);
			return;
		}

		/* On the wire there is markup ("<font>...</font>"), what is counted is the text. */
		plain = purple_markup_strip_html(message);
		length = g_utf8_strlen(plain ? plain : "", -1);

		heard++;
		reply = g_new0(struct echo_reply, 1);
		reply->who = g_strdup(sender);
		reply->text = g_strdup_printf("%s. Answer %d to %ld characters.",
		                              openings[(heard - 1) % G_N_ELEMENTS(openings)], heard, length);

		printf("[%s] == answering with: %s\n", myname, reply->text);
		fflush(stdout);

		g_free(plain);

		/* Do not send from inside the signal, send just after it. */
		g_timeout_add(200, do_reply, reply);
		return;
	}

	g_main_loop_quit(loop);
}

/*! The sender is done as soon as the message has left the house. There is no delivery
    receipt in this protocol; whether it arrived is for the receiver to say. */
static void sent_im(PurpleAccount *account, const char *receiver,
                    const char *message, gpointer data)
{
	printf("[%s] == wrote out to %s\n", myname, receiver);
	fflush(stdout);

	//The echo keeps listening until its time is up
	if (purple_strequal(role, "echo")) return;

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
		fprintf(stderr, "bonjourwire <name> <port> send|wait|echo <seconds> [partner]\n");
		return 2;
	}
	myname = argv[1];
	role = argv[3];
	if (argc > 4) seconds = atoi(argv[4]);
	if (seconds <= 0) seconds = 25;
	if (argc > 5) partner = argv[5];

	/* Without a partner nothing is sent. A failure is better than a message to a neighbour
	   that has nothing to do with the harness. */
	if (purple_strequal(role, "send") && !partner) {
		fprintf(stderr, "bonjourwire: send needs the partner's name as its fifth argument\n");
		return 2;
	}

	/* A mistyped role would otherwise quietly behave like wait. */
	if (!purple_strequal(role, "send") && !purple_strequal(role, "wait") && !purple_strequal(role, "echo")) {
		fprintf(stderr, "bonjourwire: unknown role \"%s\", allowed are send, wait and echo\n", role);
		return 2;
	}

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
	if (purple_strequal(role, "echo")) {
		printf("[%s] == %d heard, %d answered\n", myname, heard, echoed);
		return (connected && echoed > 0) ? 0 : 1;
	}
	return (connected && arrived) ? 0 : 1;
}
