/* Haelt die OMEMO-Ablage das aus, was der Alltag ihr antut?
 *
 * Geprueft wird nicht die Kryptografie, die steht im Rundlauf daneben, sondern die Buchhaltung
 * drumherum, und zwar genau an den Stellen, an denen ein Fehler still bleibt und erst Wochen
 * spaeter als Unterhaltung auffaellt, die sich nicht mehr oeffnet:
 *
 *   - Eine Identitaet muss einen Neustart ueberleben, sonst sind wir jedes Mal ein neues Geraet.
 *   - Eine Ratsche, die beim Entschluesseln weiterlaeuft, muss VOR der Rueckgabe auf der Platte
 *     stehen. Sonst entschluesselt dieselbe Nachricht nach einem Neustart erneut, und die
 *     darauffolgende nie wieder.
 *   - Nachrichten ueberholen einander. Die uebersprungenen Schluessel muessen aufgehoben und
 *     spaeter wiedergefunden werden, jeder genau einmal.
 *   - Ein Einmalschluessel muss nach Gebrauch verschwinden, und das veroeffentlichte Buendel
 *     gilt damit als veraltet.
 *
 * Der Test legt seine Dateien in einem eigenen Verzeichnis ab und ruehrt die Schluessel eines
 * echten Kontos nicht an.
 */
#import <Foundation/Foundation.h>
#import "AIOMEMOStore.h"

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

#define ALICE	@"alice@example.org"
#define BOB		@"bob@example.org"

/*! @brief Einen Schluessel aus Bobs Buendel nehmen und Alice eine Sitzung dorthin aufbauen lassen */
static BOOL letTalk(AIOMEMOStore *alice, AIOMEMOStore *bob)
{
	NSNumber *anyPreKey = [[[bob preKeys] allKeys] firstObject];

	return [alice startSessionWithJID:BOB
							   device:bob.deviceIdentifier
						  identityKey:bob.identityKey
						 signedPreKey:bob.signedPreKey
				   signedPreKeyItself:bob.signedPreKeyIdentifier
							signature:bob.signedPreKeySignature
							   preKey:[bob preKeys][anyPreKey]
						 preKeyItself:[anyPreKey unsignedIntValue]];
}

int main(void) { @autoreleasepool {
	NSString *scratch = [NSTemporaryDirectory() stringByAppendingPathComponent:
						 [NSString stringWithFormat:@"adium-omemo-test-%d", getpid()]];
	[AIOMEMOStore useDirectory:scratch];

	//Eine Identitaet entsteht
	AIOMEMOStore *alice = [AIOMEMOStore storeForAccount:ALICE];
	check(@"Ein Konto ohne Vorgeschichte bekommt eine Identitaet", alice != nil, nil);
	check(@"und eine Geraetenummer, die nicht null ist", alice.deviceIdentifier != 0,
		  [NSString stringWithFormat:@"war %u", alice.deviceIdentifier]);
	check(@"Der Fingerabdruck hat die Laenge, die man vorliest",
		  [alice.fingerprint length] == 64 + 7,
		  [NSString stringWithFormat:@"war %lu", (unsigned long)[alice.fingerprint length]]);
	check(@"Das Buendel enthaelt hundert Einmalschluessel", [[alice preKeys] count] == 100,
		  [NSString stringWithFormat:@"waren %lu", (unsigned long)[[alice preKeys] count]]);

	//Und ueberlebt einen Neustart
	NSString *fingerprintBefore = alice.fingerprint;
	uint32_t deviceBefore = alice.deviceIdentifier;

	[AIOMEMOStore closeStoreForAccount:ALICE];
	alice = [AIOMEMOStore storeForAccount:ALICE];

	check(@"Nach einem Neustart ist es dieselbe Identitaet",
		  [alice.fingerprint isEqualToString:fingerprintBefore], nil);
	check(@"und dieselbe Geraetenummer", alice.deviceIdentifier == deviceBefore, nil);

	//Zwei Seiten koennen einander schreiben
	AIOMEMOStore *bob = [AIOMEMOStore storeForAccount:BOB];
	check(@"Zwei Konten haben verschiedene Identitaeten",
		  ![bob.fingerprint isEqualToString:alice.fingerprint], nil);

	check(@"Alice baut aus Bobs Buendel eine Sitzung auf", letTalk(alice, bob), nil);
	check(@"und weiss danach, dass sie eine hat",
		  [alice hasSessionWithJID:BOB device:bob.deviceIdentifier], nil);
	check(@"Sie kennt jetzt Bobs Fingerabdruck",
		  [[alice fingerprintForJID:BOB device:bob.deviceIdentifier] isEqualToString:bob.fingerprint],
		  [alice fingerprintForJID:BOB device:bob.deviceIdentifier]);

	//Ein Nachrichtenschluessel geht hin und wird drueben ausgepackt
	uint8_t material[32];
	for (int i = 0; i < 32; i++) material[i] = (uint8_t)(i * 7 + 1);
	NSData *messageKey = [NSData dataWithBytes:material length:sizeof(material)];

	BOOL wasPreKey = NO;
	NSData *wrapped = [alice encryptKey:messageKey forJID:BOB device:bob.deviceIdentifier wasPreKey:&wasPreKey];
	check(@"Alice packt einen Nachrichtenschluessel fuer Bob ein", wrapped != nil, nil);
	check(@"Die erste Nachricht traegt einen Einmalschluessel", wasPreKey, nil);

	NSData *unwrapped = [bob decryptKey:wrapped fromJID:ALICE device:alice.deviceIdentifier isPreKey:wasPreKey];
	check(@"Bob packt ihn wieder aus", [unwrapped isEqualToData:messageKey], nil);
	check(@"und hat dabei von selbst eine Sitzung bekommen",
		  [bob hasSessionWithJID:ALICE device:alice.deviceIdentifier], nil);
	check(@"Bob kennt jetzt Alices Fingerabdruck",
		  [[bob fingerprintForJID:ALICE device:alice.deviceIdentifier] isEqualToString:alice.fingerprint], nil);

	//Der gebrauchte Einmalschluessel ist weg, und das Buendel gilt als veraltet
	check(@"Ein gebrauchter Einmalschluessel wird nachgelegt", [[bob preKeys] count] == 100,
		  [NSString stringWithFormat:@"waren %lu", (unsigned long)[[bob preKeys] count]]);
	check(@"und das veroeffentlichte Buendel gilt als veraltet", bob.bundleNeedsPublishing, nil);

	//Nachrichten, die einander ueberholen
	NSMutableArray *sent = [NSMutableArray array];
	NSMutableArray *keys = [NSMutableArray array];
	for (int round = 0; round < 3; round++) {
		uint8_t raw[32];
		for (int i = 0; i < 32; i++) raw[i] = (uint8_t)(round * 31 + i);
		NSData *key = [NSData dataWithBytes:raw length:sizeof(raw)];

		BOOL prekey = NO;
		NSData *packed = [alice encryptKey:key forJID:BOB device:bob.deviceIdentifier wasPreKey:&prekey];
		[sent addObject:@{@"packed": packed ?: [NSData data], @"prekey": @(prekey)}];
		[keys addObject:key];
	}

	//Die dritte zuerst, dann die erste, dann die zweite
	for (NSNumber *which in @[@2, @0, @1]) {
		NSDictionary *one = sent[[which intValue]];
		NSData *got = [bob decryptKey:one[@"packed"]
							  fromJID:ALICE
							   device:alice.deviceIdentifier
							 isPreKey:[one[@"prekey"] boolValue]];
		check([NSString stringWithFormat:@"Nachricht %d oeffnet sich auch ausser der Reihe",
			   [which intValue] + 1],
			  [got isEqualToData:keys[[which intValue]]], nil);
	}

	//Eine Ratsche, die gelaufen ist, muss das nach einem Neustart noch wissen
	BOOL fourthWasPreKey = NO;
	NSData *fourth = [alice encryptKey:messageKey forJID:BOB device:bob.deviceIdentifier wasPreKey:&fourthWasPreKey];

	[AIOMEMOStore closeStoreForAccount:BOB];
	bob = [AIOMEMOStore storeForAccount:BOB];

	check(@"Nach einem Neustart steht Bobs Sitzung noch",
		  [bob hasSessionWithJID:ALICE device:alice.deviceIdentifier], nil);
	NSData *afterRestart = [bob decryptKey:fourth fromJID:ALICE device:alice.deviceIdentifier isPreKey:fourthWasPreKey];
	check(@"und die naechste Nachricht oeffnet sich damit",
		  [afterRestart isEqualToData:messageKey], nil);

	//Dieselbe Nachricht ein zweites Mal darf nicht noch einmal aufgehen
	NSData *again = [bob decryptKey:fourth fromJID:ALICE device:alice.deviceIdentifier isPreKey:fourthWasPreKey];
	check(@"Dieselbe Nachricht ein zweites Mal geht nicht mehr auf", again == nil,
		  again ? @"sie ging auf" : nil);

	//Was der Benutzer entscheidet, bleibt entschieden
	check(@"Ein unbekanntes Geraet ist zunaechst unentschieden",
		  [alice trustForFingerprint:bob.fingerprint] == AIOMEMOTrustUndecided, nil);
	[alice setTrust:AIOMEMOTrustAccepted forFingerprint:bob.fingerprint];

	[AIOMEMOStore closeStoreForAccount:ALICE];
	alice = [AIOMEMOStore storeForAccount:ALICE];
	check(@"Eine Entscheidung ueberlebt den Neustart",
		  [alice trustForFingerprint:bob.fingerprint] == AIOMEMOTrustAccepted, nil);
	check(@"und steht bei dem Kontakt, zu dem sie gehoert",
		  [[alice fingerprintsForJID:BOB][bob.fingerprint] integerValue] == AIOMEMOTrustAccepted, nil);

	//Ein Buendel, das nicht zusammenpasst, wird nicht angenommen
	AIOMEMOStore *mallory = [AIOMEMOStore storeForAccount:@"mallory@example.org"];
	NSNumber *somePreKey = [[[bob preKeys] allKeys] firstObject];
	BOOL taken = [alice startSessionWithJID:@"carol@example.org"
									 device:4242
								identityKey:mallory.identityKey		//fremde Identitaet
							   signedPreKey:bob.signedPreKey
						 signedPreKeyItself:bob.signedPreKeyIdentifier
								  signature:bob.signedPreKeySignature	//zu Bob gehoerige Unterschrift
									 preKey:[bob preKeys][somePreKey]
							   preKeyItself:[somePreKey unsignedIntValue]];
	check(@"Ein Buendel mit fremder Unterschrift wird abgelehnt", !taken, nil);

	//Und ein Buendel der falschen Groesse ebenso
	BOOL stunted = [alice startSessionWithJID:@"carol@example.org"
									   device:4243
								  identityKey:[NSData dataWithBytes:"kurz" length:4]
								 signedPreKey:bob.signedPreKey
						   signedPreKeyItself:bob.signedPreKeyIdentifier
									signature:bob.signedPreKeySignature
									   preKey:[bob preKeys][somePreKey]
								 preKeyItself:[somePreKey unsignedIntValue]];
	check(@"Ein Buendel der falschen Groesse wird abgelehnt", !stunted, nil);

	//Die Datei darf niemand sonst lesen koennen
	NSString *file = [scratch stringByAppendingPathComponent:@"alice%3Aexample.org.omemo"];
	file = [scratch stringByAppendingPathComponent:@"alice@example.org.omemo"];
	NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:file error:NULL];
	check(@"Die Schluesseldatei liegt nur fuer den Eigentuemer lesbar",
		  [attributes[NSFilePosixPermissions] shortValue] == 0600,
		  [NSString stringWithFormat:@"war %o", [attributes[NSFilePosixPermissions] shortValue]]);

	[[NSFileManager defaultManager] removeItemAtPath:scratch error:NULL];

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
