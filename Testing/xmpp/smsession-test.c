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

void jabber_send(JabberStream *js, xmlnode *packet)
{
	const char *resume = xmlnode_get_attrib(packet, "resume");

	sent++;
	g_free(lastName);
	g_free(lastResume);
	lastName = g_strdup(packet->name);
	lastResume = g_strdup(resume);
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

	jabber_sm_uninit();

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
}
