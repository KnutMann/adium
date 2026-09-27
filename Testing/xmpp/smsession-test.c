/* Does the XEP-0198 queue belong to the account, or only to its name?
 *
 * Upstream keeps the unacknowledged stanzas under the bare JID. That is enough as long as there
 * is one account per address, and that is precisely what nobody promises: set the same address
 * up twice and the two share a queue, so whatever was left unacknowledged on one connection
 * goes out over the other. An account then sends stanzas it never wrote.
 *
 * What is checked is therefore the keying itself, against the REAL file: two accounts with the
 * same address get two sessions, the same account gets the same one twice, and a session that
 * turns up under a reused account pointer is recognised as a stranger's and thrown away rather
 * than handed on.
 *
 * Only the three things stream_management.c calls from the rest of the Jabber plugin are stood
 * in for here; everything else comes from the library the application itself uses.
 */
#include <glib.h>
#include <stdio.h>
#include <string.h>

#include "jabber.h"

static int failures = 0;

static void check(const char *name, int ok, const char *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name,
	       (!ok && detail) ? "  " : "", (!ok && detail) ? detail : "");
	if (!ok) failures++;
}

/* --- What stream_management.c calls from the rest of the plugin ------------------------- */

char *jabber_id_get_bare_jid(const JabberID *jid)
{
	return g_strdup_printf("%s@%s", jid->node, jid->domain);
}

gboolean jabber_is_stanza(xmlnode *node)
{
	return purple_strequal(node->name, "message")
	    || purple_strequal(node->name, "presence")
	    || purple_strequal(node->name, "iq");
}

static int sent = 0;
static char *lastName = NULL;
static char *lastResume = NULL;
static char *lastPrevid = NULL;
static char *lastH = NULL;

void jabber_send(JabberStream *js, xmlnode *packet)
{
	const char *resume = xmlnode_get_attrib(packet, "resume");

	sent++;
	g_free(lastName);
	g_free(lastResume);
	g_free(lastPrevid);
	g_free(lastH);
	lastName = g_strdup(packet->name);
	lastResume = g_strdup(resume);
	lastPrevid = g_strdup(xmlnode_get_attrib(packet, "previd"));
	lastH = g_strdup(xmlnode_get_attrib(packet, "h"));
}

/* The timer for the batched acknowledgement request runs on libpurple's loop. There is none
   here, so there is only enough of a stand in to count whether one was armed. */
static guint timersArmed = 0;
static guint timersRemoved = 0;

static guint fake_timeout_add(guint interval, GSourceFunc function, gpointer data)
{
	timersArmed++;
	return timersArmed;
}

static gboolean fake_timeout_remove(guint handle)
{
	timersRemoved++;
	return TRUE;
}

static PurpleEventLoopUiOps loopStandIn = {
	fake_timeout_add, fake_timeout_remove, NULL, NULL, NULL,
	fake_timeout_add, NULL, NULL, NULL
};

static int bindsAsked = 0;
static int statesSet = 0;

/* The two ways back into jabber.c that stream_management.c takes since resumption exists. */
void jabber_bind_resource(JabberStream *js)
{
	bindsAsked++;
}

void jabber_stream_set_state(JabberStream *js, JabberStreamState state)
{
	statesSet++;
	js->state = state;
}

#include "stream_management.c"

/* --- A stream, built as far as the file under test touches it --------------------------- */

static JabberStream *streamFor(PurpleAccount *account, const char *node, const char *domain)
{
	JabberStream *js = g_new0(JabberStream, 1);
	PurpleConnection *gc = g_new0(PurpleConnection, 1);

	gc->account = account;
	js->gc = gc;
	js->user = g_new0(JabberID, 1);
	js->user->node = g_strdup(node);
	js->user->domain = g_strdup(domain);

	return js;
}

static xmlnode *aMessage(void)
{
	return xmlnode_new("message");
}

/*! The server's answer, the way it would come off the wire */
static void enabledArrives(JabberStream *js, const char *xml)
{
	xmlnode *packet = xmlnode_from_str(xml, -1);

	jabber_sm_process_packet(js, packet);
	xmlnode_free(packet);
}

int main(void)
{
	purple_eventloop_set_ui_ops(&loopStandIn);
	jabber_sm_init();

	/* Two accounts are two pointers; neither is dereferenced here, they are only keys. */
	PurpleAccount *first = (PurpleAccount *)0x1001;
	PurpleAccount *second = (PurpleAccount *)0x1002;

	JabberStream *a = streamFor(first, "adium", "localhost");
	JabberStream *b = streamFor(second, "adium", "localhost");

	JabberSmSession *sessionA = jabber_sm_session_get(a);
	JabberSmSession *sessionB = jabber_sm_session_get(b);

	check("The same address twice gives two sessions", sessionA != sessionB,
	      "both accounts share one queue");
	check("The session remembers whose it is",
	      purple_strequal(sessionA->jid, "adium@localhost"), sessionA->jid);

	/* The same account again has to be the same session, or the queue would be empty every
	   time it is used and nothing would ever be resent. */
	check("The same account gets the same session back",
	      jabber_sm_session_get(a) == sessionA, NULL);

	/* And the queues must not touch each other. */
	g_queue_push_tail(sessionA->queue, aMessage());
	check("What one account queues up, the other does not see",
	      g_queue_get_length(sessionB->queue) == 0, NULL);

	/* A second stream for the same account, as after a dropped connection, finds the queue
	   again. That is the whole point of the thing. */
	JabberStream *again = streamFor(first, "adium", "localhost");
	JabberSmSession *found = jabber_sm_session_get(again);
	check("A new connection finds the old queue",
	      found == sessionA && g_queue_get_length(found->queue) == 1, NULL);

	/* A freed account can pass its address on to a new one. The session underneath then
	   belongs to somebody else and must not be handed on. */
	JabberStream *stranger = streamFor(first, "somebody-else", "localhost");
	JabberSmSession *fresh = jabber_sm_session_get(stranger);
	/* What is checked is the empty queue and NOT whether the pointer is a different one:
	   discarding frees the old session, and the same allocator hands the same address straight
	   back out. Comparing against sessionA would therefore read freed memory and come out
	   differently from run to run. The empty queue says everything anyway: had the guard not
	   caught it, the one message from before would still be in there. */
	check("A reused account pointer inherits no stranger's session",
	      g_queue_get_length(fresh->queue) == 0, NULL);
	check("And the new session carries the new name",
	      purple_strequal(fresh->jid, "somebody-else@localhost"), fresh->jid);

	/* Forgetting means forgetting: afterwards it is a different, empty session. */
	JabberSmSession *before = jabber_sm_session_get(b);
	g_queue_push_tail(before->queue, aMessage());
	jabber_sm_session_forget(b);
	check("After forgetting, the queue is empty",
	      g_queue_get_length(jabber_sm_session_get(b)->queue) == 0, NULL);

	/* --- What stands on the wire and what of it arrives ------------------------------- */

	/* Without asking for resumption the server does not set the session aside but destroys it
	   at the first break. That one line is the precondition for everything else. */
	jabber_sm_enable(a);
	check("The <enable/> asks for resumption",
	      purple_strequal(lastName, "enable") && purple_strequal(lastResume, "true"),
	      lastResume ? lastResume : "no resume attribute");

	/* And what the server promises has to arrive, or nobody knows what could be invoked
	   later on. */
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3' id='abc123' max='600'"
	                  " resume='true' location='xmpp.example:5222'/>");
	JabberSmSession *promised = jabber_sm_session_get(a);
	check("The session identifier is kept",
	      purple_strequal(promised->id, "abc123"), promised->id);
	check("The promised hold time is kept", promised->max == 600, NULL);
	check("The named location is kept",
	      purple_strequal(promised->location, "xmpp.example:5222"), promised->location);

	/* A server that merely agrees and promises nothing must not look as though it had promised
	   something: a <resume/> naming an invented identifier would be an error case. */
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3'/>");
	check("An empty <enabled/> leaves nothing to resume",
	      jabber_sm_session_get(a)->id == NULL, jabber_sm_session_get(a)->id);

	/* The two halves do not count on their own. */
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3' id='xyz'/>");
	check("An identifier without resume is not an offer",
	      jabber_sm_session_get(a)->id == NULL, NULL);
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3' resume='true'/>");
	check("A resume without an identifier is nothing to invoke",
	      jabber_sm_session_get(a)->id == NULL, NULL);

	/* And a new promise erases the old one, because the old session is gone. */
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3' id='first' resume='true'/>");
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3' id='second' resume='true'/>");
	check("A new promise overwrites the old identifier",
	      purple_strequal(jabber_sm_session_get(a)->id, "second"),
	      jabber_sm_session_get(a)->id);

	/* --- What becomes of a <resume/> ---------------------------------------------------- */

	/* Without a promise there is nothing to ask for, and the caller has to bind as always. */
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3'/>");
	check("Without a promise, no resumption is asked for",
	      jabber_sm_resume(a) == FALSE, NULL);

	/* With a promise the request stands on the wire, and it names both: which session, and how
	   much we have received. That second number decides what the other side resends. */
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3' id='sess-1' resume='true' max='60'/>");
	jabber_sm_session_get(a)->inbound_count = 42;
	check("With a promise, resumption is asked for", jabber_sm_resume(a) == TRUE, NULL);
	check("The request names the session and how much was received",
	      purple_strequal(lastName, "resume")
	      && purple_strequal(lastPrevid, "sess-1")
	      && purple_strequal(lastH, "42"),
	      lastPrevid ? lastPrevid : "no previd");

	/* A refused resumption must not hang: it has to bind. And it must NOT throw the
	   unacknowledged stanzas away, because unacknowledged means never delivered. */
	g_queue_push_tail(jabber_sm_session_get(a)->queue, aMessage());
	bindsAsked = 0;
	enabledArrives(a, "<failed xmlns='urn:xmpp:sm:3'><item-not-found/></failed>");
	check("A refusal binds afterwards after all", bindsAsked == 1, NULL);
	check("A refusal leaves nothing to resume",
	      jabber_sm_session_get(a)->id == NULL, NULL);
	check("A refusal does keep what is still unacknowledged",
	      g_queue_get_length(jabber_sm_session_get(a)->queue) == 1, NULL);

	/* A refusal of an <enable/>, so not of a <resume/>, is a different thing: there is no
	   session at all in that case, and the queue has no owner any more. */
	a->sm_state = SM_REQUESTED;
	bindsAsked = 0;
	enabledArrives(a, "<failed xmlns='urn:xmpp:sm:3'/>");
	check("A refusal of the enable does not bind", bindsAsked == 0, NULL);
	check("and throws the session away entirely",
	      g_queue_get_length(jabber_sm_session_get(a)->queue) == 0, NULL);

	/* And resumption itself: the counters are the old session's again, the address is the old
	   one, and the stream counts as connected without anything having been bound. */
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3' id='sess-2' resume='true'/>");
	JabberSmSession *back = jabber_sm_session_get(a);
	back->inbound_count = 7;
	back->outbound_count = 9;
	back->outbound_confirmed = 4;
	g_free(back->full_jid);
	back->full_jid = g_strdup("adium@localhost/old-one");
	a->sm_inbound_count = 0;
	a->sm_outbound_count = 0;
	bindsAsked = 0;
	statesSet = 0;
	enabledArrives(a, "<resumed xmlns='urn:xmpp:sm:3' h='9' previd='sess-2'/>");
	check("Resumption binds nothing", bindsAsked == 0, NULL);
	check("The counters are the old session's again",
	      a->sm_inbound_count == 7 && a->sm_outbound_count == 9, NULL);
	check("The old resource is ours again",
	      purple_strequal(a->user->resource, "old-one"),
	      a->user->resource ? a->user->resource : "none");
	check("The stream counts as connected afterwards",
	      statesSet == 1 && a->state == JABBER_STREAM_CONNECTED, NULL);
	check("And it knows that it was resumed", a->sm_resumed == TRUE, NULL);

	/* --- How often an acknowledgement is asked for --------------------------------------- */

	/* Upstream asked after EVERY stanza and thereby doubled the number of stanzas on the wire.
	   The acknowledgement carries a running total, so one answer settles everything before it. */
	JabberStream *counting = streamFor((PurpleAccount *)0x2001, "count", "localhost");
	counting->sm_state = SM_ENABLED;
	sent = 0;
	timersArmed = 0;
	for (int i = 0; i < 4; i++)
		jabber_sm_outbound(counting, aMessage());
	check("Four stanzas do not trigger a request yet",
	      counting->sm_unrequested == 4, NULL);
	check("Instead a timer waits for things to go quiet",
	      timersArmed == 1, NULL);

	sent = 0;
	jabber_sm_outbound(counting, aMessage());
	check("The fifth one asks", purple_strequal(lastName, "r"), lastName);
	check("And resets the counter", counting->sm_unrequested == 0, NULL);
	check("The waiting timer is cleared away with it", timersRemoved == 1, NULL);

	/* And none may be left standing at closing time, or it fires into a stream that no longer
	   exists. */
	jabber_sm_outbound(counting, aMessage());
	check("Afterwards one is waiting again", counting->sm_request_timer != 0, NULL);
	jabber_sm_stream_closing(counting);
	check("At closing time it is cleared away", counting->sm_request_timer == 0, NULL);

	/* The probe after a network break: it writes, and writing is the only thing that gives a
	   dead socket away. Without stream management there is nothing to write. */
	g_free(lastName);
	lastName = NULL;
	counting->sm_state = SM_DISABLED;
	jabber_sm_probe(counting);
	check("Without stream management the probe writes nothing", lastName == NULL, lastName);

	counting->sm_state = SM_ENABLED;
	timersArmed = 0;
	jabber_sm_probe(counting);
	check("With stream management it asks straight away",
	      purple_strequal(lastName, "r"), lastName);
	check("And does not wait forever for an answer", counting->sm_probe_timer != 0, NULL);

	/* A second probe while the first is still waiting would only shorten its patience. */
	g_free(lastName);
	lastName = NULL;
	jabber_sm_probe(counting);
	check("A second probe during the first is skipped", lastName == NULL, lastName);

	/* Any acknowledgement means: somebody is there and they are reading us. */
	enabledArrives(counting, "<a xmlns='urn:xmpp:sm:3' h='0'/>");
	check("An acknowledgement ends the waiting", counting->sm_probe_timer == 0, NULL);

	/* And this one must not be left standing at closing time either. */
	jabber_sm_probe(counting);
	jabber_sm_stream_closing(counting);
	check("At closing time the probe is cleared away too",
	      counting->sm_probe_timer == 0, NULL);

	jabber_sm_uninit();

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
}
