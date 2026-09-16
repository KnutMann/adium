/* Gehoert die Warteschlange fuer XEP-0198 dem Konto oder nur seinem Namen?
 *
 * Upstream fuehrt die unbestaetigten Stanzas unter der nackten JID. Das reicht, solange es je
 * Adresse ein Konto gibt, und genau das ist nicht gesagt: wer dieselbe Adresse zweimal
 * einrichtet, teilt sich dann eine Warteschlange, und was auf der einen Verbindung unbestaetigt
 * liegengeblieben ist, geht bei der anderen hinaus. Ein Konto sendet also Stanzas, die es nie
 * geschrieben hat.
 *
 * Geprueft wird deshalb die Schluesselung selbst, an der ECHTEN Datei: zwei Konten gleicher
 * Adresse bekommen zwei Sitzungen, dasselbe Konto bekommt zweimal dieselbe, und eine Sitzung,
 * die unter einem wiederverwendeten Kontozeiger auftaucht, wird als fremd erkannt und
 * weggeworfen statt weitergereicht.
 *
 * Nur die drei Dinge, die stream_management.c aus dem uebrigen Jabber-Plugin ruft, sind hier
 * ersetzt; alles andere kommt aus der Bibliothek, die die Anwendung auch benutzt.
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

/* --- Was stream_management.c aus dem Rest des Plugins ruft ------------------------------ */

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

/* Der Zeitgeber fuer die gebuendelte Quittungsanfrage laeuft ueber libpurples Schleife. Hier
   gibt es keine, also nur so viel Ersatz, dass sich zaehlen laesst, ob einer gestellt wurde. */
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

/* Die beiden Wege zurueck nach jabber.c, die stream_management.c seit der Wiederaufnahme geht. */
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

/* --- Ein Strom, so weit gebaut, wie die Datei ihn anfasst ------------------------------- */

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

/*! Die Antwort des Servers, so wie sie vom Draht kaeme */
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

	/* Zwei Konten sind zwei Zeiger; dereferenziert wird hier keiner, sie sind nur Schluessel. */
	PurpleAccount *first = (PurpleAccount *)0x1001;
	PurpleAccount *second = (PurpleAccount *)0x1002;

	JabberStream *a = streamFor(first, "adium", "localhost");
	JabberStream *b = streamFor(second, "adium", "localhost");

	JabberSmSession *sessionA = jabber_sm_session_get(a);
	JabberSmSession *sessionB = jabber_sm_session_get(b);

	check("Dieselbe Adresse zweimal ergibt zwei Sitzungen", sessionA != sessionB,
	      "beide Konten teilen sich eine Warteschlange");
	check("Die Sitzung merkt sich, wem sie gehoert",
	      purple_strequal(sessionA->jid, "adium@localhost"), sessionA->jid);

	/* Dasselbe Konto noch einmal muss dieselbe Sitzung sein, sonst waere die Warteschlange
	   bei jeder Verwendung leer und nichts wuerde je nachgesendet. */
	check("Dasselbe Konto bekommt dieselbe Sitzung wieder",
	      jabber_sm_session_get(a) == sessionA, NULL);

	/* Und die Warteschlangen duerfen sich nicht beruehren. */
	g_queue_push_tail(sessionA->queue, aMessage());
	check("Was das eine Konto einreiht, sieht das andere nicht",
	      g_queue_get_length(sessionB->queue) == 0, NULL);

	/* Ein zweiter Strom desselben Kontos, wie nach einem Verbindungsabbruch, findet die
	   Warteschlange wieder. Das ist der ganze Zweck der Sache. */
	JabberStream *again = streamFor(first, "adium", "localhost");
	JabberSmSession *found = jabber_sm_session_get(again);
	check("Eine neue Verbindung findet die alte Warteschlange",
	      found == sessionA && g_queue_get_length(found->queue) == 1, NULL);

	/* Ein freigegebenes Konto kann seine Adresse an ein neues vererben. Die Sitzung, die
	   darunter liegt, gehoert dann jemand anderem und darf nicht weitergereicht werden. */
	JabberStream *stranger = streamFor(first, "somebody-else", "localhost");
	JabberSmSession *fresh = jabber_sm_session_get(stranger);
	/* Geprueft wird die leere Warteschlange und NICHT, ob der Zeiger ein anderer ist: das
	   Verwerfen gibt die alte Sitzung frei, und derselbe Allokator reicht dieselbe Adresse
	   gleich wieder heraus. Ein Vergleich gegen sessionA laese also freigegebenen Speicher und
	   ginge mal so und mal so aus. Die leere Warteschlange sagt ohnehin alles: haette der
	   Waechter nicht gegriffen, laege die eine Nachricht von vorhin noch darin. */
	check("Ein wiederverwendeter Kontozeiger erbt keine fremde Sitzung",
	      g_queue_get_length(fresh->queue) == 0, NULL);
	check("Und die neue Sitzung traegt den neuen Namen",
	      purple_strequal(fresh->jid, "somebody-else@localhost"), fresh->jid);

	/* Vergessen heisst vergessen: danach ist es eine andere, leere Sitzung. */
	JabberSmSession *before = jabber_sm_session_get(b);
	g_queue_push_tail(before->queue, aMessage());
	jabber_sm_session_forget(b);
	check("Nach dem Vergessen ist die Warteschlange leer",
	      g_queue_get_length(jabber_sm_session_get(b)->queue) == 0, NULL);

	/* --- Was auf dem Draht steht und was davon ankommt -------------------------------- */

	/* Ohne die Bitte um Wiederaufnahme legt der Server die Sitzung nicht beiseite, sondern
	   zerstoert sie beim ersten Abbruch. Die eine Zeile ist die Vorbedingung fuer alles. */
	jabber_sm_enable(a);
	check("Das <enable/> bittet um Wiederaufnahme",
	      purple_strequal(lastName, "enable") && purple_strequal(lastResume, "true"),
	      lastResume ? lastResume : "kein resume-Attribut");

	/* Und was der Server verspricht, muss ankommen, sonst weiss niemand, worauf man sich
	   spaeter berufen koennte. */
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3' id='abc123' max='600'"
	                  " resume='true' location='xmpp.example:5222'/>");
	JabberSmSession *promised = jabber_sm_session_get(a);
	check("Die Kennung der Sitzung wird behalten",
	      purple_strequal(promised->id, "abc123"), promised->id);
	check("Die zugesagte Haltezeit wird behalten", promised->max == 600, NULL);
	check("Der genannte Ort wird behalten",
	      purple_strequal(promised->location, "xmpp.example:5222"), promised->location);

	/* Ein Server, der nur zustimmt und nichts verspricht, darf nicht so aussehen, als haette
	   er etwas versprochen: ein <resume/> auf eine erfundene Kennung waere ein Fehlerfall. */
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3'/>");
	check("Ein leeres <enabled/> laesst nichts zum Wiederaufnehmen zurueck",
	      jabber_sm_session_get(a)->id == NULL, jabber_sm_session_get(a)->id);

	/* Die beiden Halbheiten zaehlen einzeln nicht. */
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3' id='xyz'/>");
	check("Eine Kennung ohne resume ist kein Angebot",
	      jabber_sm_session_get(a)->id == NULL, NULL);
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3' resume='true'/>");
	check("Ein resume ohne Kennung ist nichts, worauf man sich berufen kann",
	      jabber_sm_session_get(a)->id == NULL, NULL);

	/* Und eine neue Zusage loescht die alte, denn die alte Sitzung gibt es nicht mehr. */
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3' id='first' resume='true'/>");
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3' id='second' resume='true'/>");
	check("Eine neue Zusage ueberschreibt die alte Kennung",
	      purple_strequal(jabber_sm_session_get(a)->id, "second"),
	      jabber_sm_session_get(a)->id);

	/* --- Was aus einem <resume/> wird --------------------------------------------------- */

	/* Ohne Zusage gibt es nichts zu erbitten, und der Aufrufer muss binden wie immer. */
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3'/>");
	check("Ohne Zusage wird nicht um Wiederaufnahme gebeten",
	      jabber_sm_resume(a) == FALSE, NULL);

	/* Mit Zusage steht die Bitte auf dem Draht, und sie nennt beides: worum es geht und wie
	   viel wir empfangen haben. Die zweite Zahl entscheidet, was die Gegenseite nachsendet. */
	enabledArrives(a, "<enabled xmlns='urn:xmpp:sm:3' id='sess-1' resume='true' max='60'/>");
	jabber_sm_session_get(a)->inbound_count = 42;
	check("Mit Zusage wird um Wiederaufnahme gebeten", jabber_sm_resume(a) == TRUE, NULL);
	check("Die Bitte nennt die Sitzung und den Empfangsstand",
	      purple_strequal(lastName, "resume")
	      && purple_strequal(lastPrevid, "sess-1")
	      && purple_strequal(lastH, "42"),
	      lastPrevid ? lastPrevid : "kein previd");

	/* Eine abgelehnte Wiederaufnahme darf nicht haengenbleiben: sie muss binden. Und sie darf
	   die unbestaetigten Stanzas NICHT wegwerfen, denn unbestaetigt heisst nie zugestellt. */
	g_queue_push_tail(jabber_sm_session_get(a)->queue, aMessage());
	bindsAsked = 0;
	enabledArrives(a, "<failed xmlns='urn:xmpp:sm:3'><item-not-found/></failed>");
	check("Eine Absage bindet danach doch", bindsAsked == 1, NULL);
	check("Eine Absage laesst nichts zum Wiederaufnehmen zurueck",
	      jabber_sm_session_get(a)->id == NULL, NULL);
	check("Eine Absage behaelt aber, was noch unbestaetigt ist",
	      g_queue_get_length(jabber_sm_session_get(a)->queue) == 1, NULL);

	/* Eine Absage auf ein <enable/>, also nicht auf ein <resume/>, ist etwas anderes: dort
	   gibt es ueberhaupt keine Sitzung, und die Warteschlange hat keinen Besitzer mehr. */
	a->sm_state = SM_REQUESTED;
	bindsAsked = 0;
	enabledArrives(a, "<failed xmlns='urn:xmpp:sm:3'/>");
	check("Eine Absage auf das Einschalten bindet nicht", bindsAsked == 0, NULL);
	check("und wirft die Sitzung ganz weg",
	      g_queue_get_length(jabber_sm_session_get(a)->queue) == 0, NULL);

	/* Und die Wiederaufnahme selbst: die Zaehler sind wieder die der alten Sitzung, die
	   Adresse ist die alte, und der Strom gilt als verbunden, ohne dass etwas gebunden wurde. */
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
	check("Die Wiederaufnahme bindet nichts", bindsAsked == 0, NULL);
	check("Die Zaehler sind wieder die der alten Sitzung",
	      a->sm_inbound_count == 7 && a->sm_outbound_count == 9, NULL);
	check("Die alte Ressource ist wieder unsere",
	      purple_strequal(a->user->resource, "old-one"),
	      a->user->resource ? a->user->resource : "keine");
	check("Der Strom gilt danach als verbunden",
	      statesSet == 1 && a->state == JABBER_STREAM_CONNECTED, NULL);
	check("Und er weiss, dass er wiederaufgenommen wurde", a->sm_resumed == TRUE, NULL);

	/* --- Wie oft nach einer Quittung gefragt wird ---------------------------------------- */

	/* Upstream fragte nach JEDER Stanza und verdoppelte damit die Zahl der Stanzas auf dem
	   Draht. Die Quittung traegt eine laufende Summe, eine Antwort erledigt also alles davor. */
	JabberStream *counting = streamFor((PurpleAccount *)0x2001, "count", "localhost");
	counting->sm_state = SM_ENABLED;
	sent = 0;
	timersArmed = 0;
	for (int i = 0; i < 4; i++)
		jabber_sm_outbound(counting, aMessage());
	check("Vier Stanzas loesen noch keine Anfrage aus",
	      counting->sm_unrequested == 4, NULL);
	check("Dafuer wartet ein Zeitgeber darauf, dass es still wird",
	      timersArmed == 1, NULL);

	sent = 0;
	jabber_sm_outbound(counting, aMessage());
	check("Die fuenfte fragt nach", purple_strequal(lastName, "r"), lastName);
	check("Und setzt den Zaehler zurueck", counting->sm_unrequested == 0, NULL);
	check("Der wartende Zeitgeber wird dabei abgeraeumt", timersRemoved == 1, NULL);

	/* Und beim Schliessen darf keiner stehenbleiben, sonst feuert er in einen Strom, den es
	   nicht mehr gibt. */
	jabber_sm_outbound(counting, aMessage());
	check("Danach wartet wieder einer", counting->sm_request_timer != 0, NULL);
	jabber_sm_stream_closing(counting);
	check("Beim Schliessen wird er abgeraeumt", counting->sm_request_timer == 0, NULL);

	/* Die Sonde nach einer Netzunterbrechung: sie schreibt, und Schreiben ist das Einzige, was
	   ein totes Socket verraet. Ohne Stream Management gibt es nichts zu schreiben. */
	g_free(lastName);
	lastName = NULL;
	counting->sm_state = SM_DISABLED;
	jabber_sm_probe(counting);
	check("Ohne Stream Management schreibt die Sonde nichts", lastName == NULL, lastName);

	counting->sm_state = SM_ENABLED;
	jabber_sm_probe(counting);
	check("Mit Stream Management fragt sie sofort nach",
	      purple_strequal(lastName, "r"), lastName);

	jabber_sm_uninit();

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
}
