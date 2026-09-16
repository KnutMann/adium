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

void jabber_send(JabberStream *js, xmlnode *packet)
{
	sent++;
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
	check("Ein wiederverwendeter Kontozeiger erbt keine fremde Sitzung",
	      fresh != sessionA && g_queue_get_length(fresh->queue) == 0, NULL);
	check("Und die neue Sitzung traegt den neuen Namen",
	      purple_strequal(fresh->jid, "somebody-else@localhost"), fresh->jid);

	/* Vergessen heisst vergessen: danach ist es eine andere, leere Sitzung. */
	JabberSmSession *before = jabber_sm_session_get(b);
	g_queue_push_tail(before->queue, aMessage());
	jabber_sm_session_forget(b);
	check("Nach dem Vergessen ist die Warteschlange leer",
	      g_queue_get_length(jabber_sm_session_get(b)->queue) == 0, NULL);

	jabber_sm_uninit();

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
}
