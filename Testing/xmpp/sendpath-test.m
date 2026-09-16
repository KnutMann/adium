/* Ueberlebt eine Stanza den Umweg ueber Text, den der gezaehlte Sendeweg noetig macht?
 *
 * Vier Stellen in Adium haben ihre Stanzas bisher direkt an send_raw gegeben und damit den
 * Zaehler fuer XEP-0198 umgangen: der Server zaehlt sie, wir nicht, und die beiden Zahlen laufen
 * fuer den Rest der Verbindung auseinander. Zwei dieser Stellen halten fertigen TEXT und keinen
 * Baum, muessen also erst wieder eingelesen werden, damit der Zaehler sie sieht.
 *
 * Genau das wird hier geprueft: dass dabei nichts verlorengeht. Ein verschluckter Namensraum
 * oder ein verlorenes Attribut faellt sonst erst der Gegenseite auf, und auch dort nur als
 * ausbleibende Antwort.
 */
#import <Foundation/Foundation.h>
#import <libpurple/libpurple.h>

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

/*! @brief Einlesen und wieder ausschreiben, wie der gezaehlte Weg es tut */
static NSString *throughTheParser(NSString *written)
{
	xmlnode *parsed = xmlnode_from_str([written UTF8String], -1);
	if (!parsed) return nil;

	char *again = xmlnode_to_str(parsed, NULL);
	NSString *result = again ? [NSString stringWithUTF8String:again] : nil;
	if (again) g_free(again);
	xmlnode_free(parsed);
	return result;
}

static void survives(NSString *name, NSString *written, NSArray<NSString *> *mustContain)
{
	NSString *after = throughTheParser(written);
	if (!after) {
		check(name, NO, @"liess sich gar nicht einlesen");
		return;
	}

	for (NSString *needed in mustContain) {
		if ([after rangeOfString:needed].location == NSNotFound) {
			check(name, NO, [NSString stringWithFormat:@"\"%@\" fehlt in %@", needed, after]);
			return;
		}
	}
	check(name, YES, nil);
}

int main(void) { @autoreleasepool {
	//Was AMPurpleJabberNode beim Erkunden schickt, mit dem Namensraum auf dem query-Element
	survives(@"Eine Erkundungsanfrage behaelt ihren Namensraum",
			 @"<iq type=\"get\" to=\"conference.example.org\" id=\"AMPurpleJabberNode1\">"
			  "<query xmlns=\"http://jabber.org/protocol/disco#items\"></query></iq>",
			 @[@"disco#items", @"conference.example.org", @"AMPurpleJabberNode1", @"type='get'"]);

	survives(@"Und eine nach Faehigkeiten ebenso",
			 @"<iq type=\"get\" to=\"example.org\" id=\"n2\">"
			  "<query xmlns=\"http://jabber.org/protocol/disco#info\" node=\"urn:x\"></query></iq>",
			 @[@"disco#info", @"node='urn:x'", @"id='n2'"]);

	//Was der Ad-hoc-Server antwortet: verschachtelt, mit Formular
	survives(@"Eine Ad-hoc-Antwort behaelt ihre Verschachtelung",
			 @"<iq to=\"a@b/c\" type=\"result\" id=\"x1\">"
			  "<command xmlns=\"http://jabber.org/protocol/commands\" node=\"ping\" status=\"completed\">"
			  "<x xmlns=\"jabber:x:data\" type=\"result\">"
			  "<field var=\"beat\"><value>1</value></field></x></command></iq>",
			 @[@"protocol/commands", @"node='ping'", @"jabber:x:data", @"<value>1</value>"]);

	//Was der Datei-Upload fragt
	survives(@"Eine Upload-Anfrage behaelt Groesse und Namen",
			 @"<iq type=\"get\" to=\"upload.example.org\" id=\"u1\">"
			  "<request xmlns=\"urn:xmpp:http:upload:0\" filename=\"Bild ä.png\" size=\"4711\"/></iq>",
			 @[@"upload:0", @"Bild ä.png", @"size='4711'"]);

	//Umlaute und Sonderzeichen im Text
	survives(@"Ein Rumpf mit Umlauten kommt heil durch",
			 @"<message to=\"x@y\" type=\"chat\"><body>Grüße &amp; Küsse &lt;3</body></message>",
			 @[@"Grüße", @"&amp;", @"&lt;3"]);

	//Und der Fall, der NICHT durchgehen darf: kaputtes XML muss als nil zurueckkommen,
	//damit der Aufrufer es unveraendert weitergibt statt es stillschweigend zu verlieren
	check(@"Unvollstaendiges XML laesst sich nicht einlesen",
		  throughTheParser(@"<iq type='get'><query") == nil, nil);
	check(@"Und ein blosses Bruchstueck ebensowenig",
		  throughTheParser(@"</stream:stream>") == nil, nil);

	//Ein einzelnes Element ohne Inhalt ist dagegen gueltig und muss durchgehen
	check(@"Ein leeres Element geht durch", throughTheParser(@"<presence/>") != nil, nil);

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
