/* Kommt eine OMEMO-Nachricht in der Form heraus, die andere Clients annehmen, und wieder herein?
 *
 * Geprueft wird die Drahtform, nicht die Kryptografie darunter: dass der Pruefwert AM SCHLUESSEL
 * haengt und nicht am Text (Conversations weist alles andere mit dem Hinweis ab, der ABSENDER
 * muesse seinen Client erneuern), dass ein Text an mehrere Geraete gleichzeitig geht und dabei
 * NUR EINMAL verschluesselt wird, dass wir uns selbst nicht anschreiben, und dass eine
 * Nachricht, die fuer niemanden lesbar waere, gar nicht erst entsteht.
 *
 * Und die Faelle, in denen nichts passieren darf: eine Nachricht an ein anderes Geraet desselben
 * Kontos, ein verdrehter Initialisierungsvektor, ein veraenderter Text.
 */
#import <Foundation/Foundation.h>
#import "AIOMEMOStore.h"
#import "AIOMEMOMessage.h"

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

#define ALICE	@"alice@example.org"
#define BOB		@"bob@example.org"

/*! @brief Alice eine Sitzung zu einem Geraet aufbauen lassen, aus dessen Buendel */
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
						 [NSString stringWithFormat:@"adium-omemo-msg-%d", getpid()]];
	[AIOMEMOStore useDirectory:scratch];

	AIOMEMOStore *alice = [AIOMEMOStore storeForAccount:ALICE];
	AIOMEMOStore *bobPhone = [AIOMEMOStore storeForAccount:BOB];

	//Bobs zweites Geraet: ein eigener Vorrat unter einem eigenen Kontonamen, damit beide
	//Identitaeten wirklich verschieden sind, wie bei zwei echten Installationen
	AIOMEMOStore *bobLaptop = [AIOMEMOStore storeForAccount:@"bob-laptop@example.org"];

	check(@"Bobs zwei Geraete haben verschiedene Nummern",
		  bobPhone.deviceIdentifier != bobLaptop.deviceIdentifier, nil);

	check(@"Alice erreicht Bobs Telefon", letTalk(alice, BOB, bobPhone), nil);
	check(@"und Bobs Rechner", letTalk(alice, BOB, bobLaptop), nil);

	NSDictionary *recipients = @{ BOB: @[@(bobPhone.deviceIdentifier), @(bobLaptop.deviceIdentifier)] };

	NSString *said = @"Treffen wir uns um acht? Grüße, 👋";
	AIOMEMOMessage *sent = [AIOMEMOMessage encrypting:said withStore:alice forDevices:recipients];

	check(@"Eine Nachricht an zwei Geraete entsteht", sent != nil, nil);
	check(@"Sie traegt unsere Geraetenummer", sent.sender == alice.deviceIdentifier, nil);
	check(@"Der Initialisierungsvektor ist zwoelf Byte lang", [sent.initialisationVector length] == 12,
		  [NSString stringWithFormat:@"war %lu", (unsigned long)[sent.initialisationVector length]]);
	check(@"Der Text wurde nur einmal verschluesselt", [sent.keys count] == 2,
		  [NSString stringWithFormat:@"es waren %lu Schluessel", (unsigned long)[sent.keys count]]);

	//Die Groesse, an der Conversations eine Nachricht ablehnt: sechzehn Byte Schluessel plus
	//sechzehn Byte Pruefwert, und zwar IM Schluessel, nicht am Text
	check(@"Der verschluesselte Text ist so lang wie der Klartext",
		  [sent.payload length] == [[said dataUsingEncoding:NSUTF8StringEncoding] length],
		  [NSString stringWithFormat:@"%lu statt %lu", (unsigned long)[sent.payload length],
		   (unsigned long)[[said dataUsingEncoding:NSUTF8StringEncoding] length]]);

	//Beide Geraete lesen dieselbe Nachricht
	NSString *atPhone = [AIOMEMOMessage textFromPayload:sent.payload
								   initialisationVector:sent.initialisationVector
												   keys:sent.keys
											   sentFrom:ALICE
												 device:alice.deviceIdentifier
											  withStore:bobPhone];
	check(@"Bobs Telefon liest sie", [atPhone isEqualToString:said], atPhone);

	NSString *atLaptop = [AIOMEMOMessage textFromPayload:sent.payload
									initialisationVector:sent.initialisationVector
													keys:sent.keys
												sentFrom:ALICE
												  device:alice.deviceIdentifier
											   withStore:bobLaptop];
	check(@"und Bobs Rechner ebenso", [atLaptop isEqualToString:said], atLaptop);

	//Ein Geraet, das nicht gemeint war, findet nichts fuer sich
	AIOMEMOStore *stranger = [AIOMEMOStore storeForAccount:@"carol@example.org"];
	NSString *atStranger = [AIOMEMOMessage textFromPayload:sent.payload
									  initialisationVector:sent.initialisationVector
													  keys:sent.keys
												  sentFrom:ALICE
													device:alice.deviceIdentifier
												 withStore:stranger];
	check(@"Ein nicht gemeintes Geraet findet nichts fuer sich", atStranger == nil, atStranger);

	//Wir schreiben uns nicht selbst an
	NSDictionary *includingOurselves = @{
		BOB: @[@(bobPhone.deviceIdentifier)],
		ALICE: @[@(alice.deviceIdentifier)]
	};
	AIOMEMOMessage *second = [AIOMEMOMessage encrypting:@"nochmal" withStore:alice forDevices:includingOurselves];
	check(@"Das eigene Geraet bekommt keine Kopie", second != nil && [second.keys count] == 1,
		  second ? [NSString stringWithFormat:@"es waren %lu", (unsigned long)[second.keys count]] : @"gar nichts");

	//Eine Nachricht, die niemand lesen koennte, entsteht gar nicht erst
	AIOMEMOMessage *toNobody = [AIOMEMOMessage encrypting:@"ins Leere"
												withStore:alice
											   forDevices:@{ @"dave@example.org": @[@(999)] }];
	check(@"Eine Nachricht an lauter unbekannte Geraete entsteht nicht", toNobody == nil, nil);

	//Ein veraenderter Text faellt auf
	AIOMEMOMessage *third = [AIOMEMOMessage encrypting:@"unveraendert" withStore:alice forDevices:recipients];
	NSMutableData *tampered = [third.payload mutableCopy];
	((uint8_t *)[tampered mutableBytes])[0] ^= 0xFF;
	NSString *broken = [AIOMEMOMessage textFromPayload:tampered
								  initialisationVector:third.initialisationVector
												  keys:third.keys
											  sentFrom:ALICE
												device:alice.deviceIdentifier
											 withStore:bobPhone];
	check(@"Ein veraenderter Text faellt auf", broken == nil, broken);

	//Ein Initialisierungsvektor der falschen Laenge wird abgelehnt statt geraten
	AIOMEMOMessage *fourth = [AIOMEMOMessage encrypting:@"egal" withStore:alice forDevices:recipients];
	NSString *wrongVector = [AIOMEMOMessage textFromPayload:fourth.payload
									   initialisationVector:[NSData dataWithBytes:"zu kurz" length:7]
													   keys:fourth.keys
												   sentFrom:ALICE
													 device:alice.deviceIdentifier
												  withStore:bobPhone];
	check(@"Ein zu kurzer Initialisierungsvektor wird abgelehnt", wrongVector == nil, wrongVector);

	//Die erste Nachricht an ein Geraet muss als sitzungseroeffnend gekennzeichnet sein
	BOOL anyStartsASession = NO;
	for (AIOMEMOKeyForDevice *one in sent.keys)
		if (one.startsASession) anyStartsASession = YES;
	check(@"Die erste Nachricht ist als sitzungseroeffnend gekennzeichnet", anyStartsASession, nil);

	/* Und die zweite AUCH NOCH, denn bis Bob geantwortet hat, weiss Alice nicht, ob er die
	 * erste ueberhaupt bekommen hat. Faellt der Einmalschluessel zu frueh weg, verliert eine
	 * Nachricht, die die erste ueberholt, ihre einzige Moeglichkeit anzukommen. */
	AIOMEMOMessage *later = [AIOMEMOMessage encrypting:@"und weiter" withStore:alice forDevices:recipients];
	BOOL stillStarting = NO;
	for (AIOMEMOKeyForDevice *one in later.keys)
		if (one.startsASession) stillStarting = YES;
	check(@"Bis die Gegenseite geantwortet hat, bleibt der Einmalschluessel dabei", stillStarting, nil);

	//Bob liest sie und kann zurueckschreiben, ohne je ein Buendel von Alice geholt zu haben
	[AIOMEMOMessage textFromPayload:later.payload
			   initialisationVector:later.initialisationVector
							   keys:later.keys
						   sentFrom:ALICE
							 device:alice.deviceIdentifier
						  withStore:bobPhone];

	AIOMEMOMessage *answer = [AIOMEMOMessage encrypting:@"Ja, gerne"
											  withStore:bobPhone
											 forDevices:@{ ALICE: @[@(alice.deviceIdentifier)] }];
	check(@"Bob kann antworten, ohne ein Buendel geholt zu haben", answer != nil, nil);

	NSString *heard = [AIOMEMOMessage textFromPayload:answer.payload
								 initialisationVector:answer.initialisationVector
												 keys:answer.keys
											 sentFrom:BOB
											   device:bobPhone.deviceIdentifier
											withStore:alice];
	check(@"und Alice liest die Antwort", [heard isEqualToString:@"Ja, gerne"], heard);

	//ERST JETZT, wo Alice weiss, dass Bob da ist, faellt der Einmalschluessel weg
	AIOMEMOMessage *afterward = [AIOMEMOMessage encrypting:@"alles klar"
												 withStore:alice
												forDevices:@{ BOB: @[@(bobPhone.deviceIdentifier)] }];
	BOOL stillStartingNow = NO;
	for (AIOMEMOKeyForDevice *one in afterward.keys)
		if (one.startsASession) stillStartingNow = YES;
	check(@"Nach der ersten Antwort faellt er weg", !stillStartingNow, nil);

	NSString *finally = [AIOMEMOMessage textFromPayload:afterward.payload
								   initialisationVector:afterward.initialisationVector
												   keys:afterward.keys
											   sentFrom:ALICE
												 device:alice.deviceIdentifier
											  withStore:bobPhone];
	check(@"und die Unterhaltung laeuft weiter", [finally isEqualToString:@"alles klar"], finally);

	[[NSFileManager defaultManager] removeItemAtPath:scratch error:NULL];

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
