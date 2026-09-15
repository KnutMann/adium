/* Sieht die Stanza so aus, wie andere OMEMO-Clients sie erwarten, und kommt sie wieder auf?
 *
 * Geprueft wird hier die XML-Arbeit selbst, gegen das echte xmlnode aus libpurple, denn genau
 * dort versteckt sich ein Formatfehler: es uebersetzt, es laeuft, es kommt etwas heraus, das
 * wie eine Stanza aussieht, und die Gegenseite zeigt nichts und sagt nichts.
 *
 * Besonders im Blick:
 *   - der Klartext muss WEG sein, und zwar alles davon, nicht nur der Rumpf;
 *   - alles, was nicht auf der kurzen Liste des Harmlosen steht, muss verschwinden, auch
 *     Elemente, an die niemand gedacht hat;
 *   - der Ersatzrumpf fuer Clients ohne OMEMO muss da sein, sonst sehen die eine leere Zeile;
 *   - beim Lesen muss der Ersatzrumpf verschwinden und der echte Text an seine Stelle treten.
 */
#import <Foundation/Foundation.h>
#import <libpurple/libpurple.h>
#import "AIOMEMOStore.h"
#import "AIOMEMOStanza.h"

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

#define ALICE	@"alice@example.org"
#define BOB		@"bob@example.org"

static NSString *asText(xmlnode *node)
{
	char *raw = xmlnode_to_str(node, NULL);
	NSString *text = raw ? [NSString stringWithUTF8String:raw] : @"";
	if (raw) g_free(raw);
	return text;
}

static BOOL letTalk(AIOMEMOStore *from, NSString *toJID, AIOMEMOStore *to)
{
	NSNumber *anyPreKey = [[[to preKeys] allKeys] firstObject];
	return [from startSessionWithJID:toJID
							  device:to.deviceIdentifier
						 identityKey:to.identityKey
						signedPreKey:to.signedPreKey
				  signedPreKeyItself:to.signedPreKeyIdentifier
						   signature:to.signedPreKeySignature
							  preKey:[to preKeys][anyPreKey]
						preKeyItself:[anyPreKey unsignedIntValue]];
}

int main(void) { @autoreleasepool {
	NSString *scratch = [NSTemporaryDirectory() stringByAppendingPathComponent:
						 [NSString stringWithFormat:@"adium-omemo-stanza-%d", getpid()]];
	[AIOMEMOStore useDirectory:scratch];

	AIOMEMOStore *alice = [AIOMEMOStore storeForAccount:ALICE];
	AIOMEMOStore *bob = [AIOMEMOStore storeForAccount:BOB];
	check(@"Alice erreicht Bob", letTalk(alice, BOB, bob), nil);

	//Eine Nachricht, wie Adium sie sonst verschickt: mit Rumpf, Empfangswunsch und Tippanzeige,
	//und dazu etwas, das Inhalt traegt und deshalb nicht im Klartext hinausgehen darf
	NSString *secret = @"Das Passwort lautet Löwenzahn";

	xmlnode *outgoing = xmlnode_new("message");
	xmlnode_set_attrib(outgoing, "to", [BOB UTF8String]);
	xmlnode_set_attrib(outgoing, "type", "chat");
	xmlnode_set_attrib(outgoing, "id", "abc123");
	xmlnode_insert_data(xmlnode_new_child(outgoing, "body"), [secret UTF8String], -1);
	xmlnode_set_namespace(xmlnode_new_child(outgoing, "request"), "urn:xmpp:receipts");
	xmlnode_set_namespace(xmlnode_new_child(outgoing, "composing"), "http://jabber.org/protocol/chatstates");

	//Ein Zitat, das den Text der Nachricht wiederholt, auf die geantwortet wird
	xmlnode *quoted = xmlnode_new_child(outgoing, "reply");
	xmlnode_set_namespace(quoted, "urn:xmpp:reply:0");
	xmlnode_set_attrib(quoted, "to", [BOB UTF8String]);

	//Und eine Formatierung, die den ganzen Text ein zweites Mal traegt
	xmlnode *formatted = xmlnode_new_child(outgoing, "html");
	xmlnode_set_namespace(formatted, "http://jabber.org/protocol/xhtml-im");
	xmlnode_insert_data(xmlnode_new_child(formatted, "body"), [secret UTF8String], -1);

	NSDictionary *toBob = @{ BOB: @[@(bob.deviceIdentifier)] };
	check(@"Die Nachricht laesst sich verschliessen",
		  AIOMEMOSealStanza(outgoing, alice, toBob), nil);

	NSString *onTheWire = asText(outgoing);

	//Das Wichtigste zuerst: nichts vom Klartext darf uebrig sein
	check(@"Der Klartext steht nicht mehr drin",
		  [onTheWire rangeOfString:@"Löwenzahn"].location == NSNotFound, nil);
	check(@"Auch nicht in der Formatierung, die ihn wiederholte",
		  [onTheWire rangeOfString:@"xhtml-im"].location == NSNotFound, nil);
	check(@"Und das Zitat ist ebenfalls weg",
		  [onTheWire rangeOfString:@"urn:xmpp:reply"].location == NSNotFound, nil);

	//Was harmlos ist, bleibt
	check(@"Der Empfangswunsch bleibt stehen",
		  xmlnode_get_child_with_namespace(outgoing, "request", "urn:xmpp:receipts") != NULL, nil);
	check(@"Die Tippanzeige bleibt stehen",
		  xmlnode_get_child_with_namespace(outgoing, "composing",
										   "http://jabber.org/protocol/chatstates") != NULL, nil);

	//Die Adresse und die Art der Nachricht ueberleben, sonst kaeme sie nirgends an
	check(@"Die Adresse steht noch dran",
		  purple_strequal(xmlnode_get_attrib(outgoing, "to"), [BOB UTF8String]), nil);
	check(@"Und die Art der Nachricht auch",
		  purple_strequal(xmlnode_get_attrib(outgoing, "type"), "chat"), nil);

	//Die Form, die andere Clients lesen
	xmlnode *encrypted = xmlnode_get_child_with_namespace(outgoing, "encrypted", AIOMEMO_NAMESPACE);
	check(@"Es gibt ein encrypted-Element im richtigen Namensraum", encrypted != NULL, nil);

	xmlnode *header = encrypted ? xmlnode_get_child(encrypted, "header") : NULL;
	check(@"Der Kopf nennt unsere Geraetenummer",
		  AIOMEMONumberIn(header, "sid") == alice.deviceIdentifier, nil);
	check(@"Es gibt einen Initialisierungsvektor",
		  header && xmlnode_get_child(header, "iv") != NULL, nil);
	check(@"Es gibt einen Schluessel fuer Bobs Geraet",
		  header && AIOMEMONumberIn(xmlnode_get_child(header, "key"), "rid") == bob.deviceIdentifier, nil);
	check(@"Der erste Schluessel ist als sitzungseroeffnend gekennzeichnet",
		  header && purple_strequal(xmlnode_get_attrib(xmlnode_get_child(header, "key"), "prekey"), "true"),
		  nil);
	check(@"Es gibt eine Nutzlast",
		  encrypted && xmlnode_get_child(encrypted, "payload") != NULL, nil);

	//Die Beigaben, ohne die es anderswo schlecht aussieht
	check(@"Der Hinweis zum Aufbewahren ist dabei",
		  xmlnode_get_child_with_namespace(outgoing, "store", "urn:xmpp:hints") != NULL, nil);
	check(@"Es steht dabei, womit verschluesselt wurde",
		  xmlnode_get_child_with_namespace(outgoing, "encryption", "urn:xmpp:eme:0") != NULL, nil);

	xmlnode *fallback = xmlnode_get_child(outgoing, "body");
	check(@"Ein Ersatzrumpf fuer Clients ohne OMEMO ist da", fallback != NULL, nil);

	//Und nun die Gegenrichtung: dieselbe Stanza, bei Bob angekommen
	xmlnode *incoming = xmlnode_from_str([onTheWire UTF8String], -1);
	check(@"Die Stanza laesst sich wieder einlesen", incoming != NULL, nil);

	if (incoming) {
		xmlnode_set_attrib(incoming, "from", [[ALICE stringByAppendingString:@"/mac"] UTF8String]);

		check(@"Bob macht wieder eine Nachricht daraus",
			  AIOMEMOOpenStanza(incoming, bob, ALICE) == AIOMEMOOpenedReadable, nil);

		xmlnode *opened = xmlnode_get_child(incoming, "body");
		char *raw = opened ? xmlnode_get_data(opened) : NULL;
		NSString *read = raw ? [NSString stringWithUTF8String:raw] : nil;
		if (raw) g_free(raw);

		check(@"und es steht der richtige Text darin", [read isEqualToString:secret], read);
		check(@"Der Ersatzrumpf ist dabei verschwunden",
			  [asText(incoming) rangeOfString:@"doesn't support it"].location == NSNotFound, nil);
		check(@"Und das encrypted-Element auch",
			  xmlnode_get_child_with_namespace(incoming, "encrypted", AIOMEMO_NAMESPACE) == NULL, nil);

		xmlnode_free(incoming);
	}

	//Eine Nachricht an ein Geraet, mit dem wir gar keine Sitzung haben, entsteht nicht
	xmlnode *hopeless = xmlnode_new("message");
	xmlnode_set_attrib(hopeless, "to", "dave@example.org");
	xmlnode_insert_data(xmlnode_new_child(hopeless, "body"), "ins Leere", -1);
	check(@"Ohne Sitzung wird nichts verschlossen",
		  !AIOMEMOSealStanza(hopeless, alice, @{ @"dave@example.org": @[@(4711)] }), nil);
	check(@"und die Nachricht bleibt unangetastet",
		  xmlnode_get_child(hopeless, "body") != NULL, nil);
	xmlnode_free(hopeless);

	//Eine Stanza ohne encrypted-Element wird nicht angefasst
	xmlnode *plain = xmlnode_from_str("<message from='x@y'><body>ganz normal</body></message>", -1);
	check(@"Eine gewoehnliche Nachricht wird nicht angefasst",
		  AIOMEMOOpenStanza(plain, bob, @"x@y") == AIOMEMOOpenedCouldNot, nil);
	xmlnode_free(plain);

	xmlnode_free(outgoing);
	[[NSFileManager defaultManager] removeItemAtPath:scratch error:NULL];

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
