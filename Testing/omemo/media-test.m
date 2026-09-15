/* Kommt eine verschluesselt geteilte Datei (XEP-0454) richtig wieder heraus?
 *
 * Geprueft wird gegen einen VEROEFFENTLICHTEN Pruefwert aus der Testreihe des NIST zu
 * AES-256-GCM, nicht gegen uns selbst. Der Unterschied ist der ganze Zweck: eine Entschluesselung,
 * die nur zur eigenen Verschluesselung passt, beweist Selbstkonsistenz und nicht, dass die Datei
 * eines fremden Clients aufgeht.
 *
 * Dazu die Faelle, in denen NICHTS herauskommen darf: ein veraenderter Prueffwert, ein
 * veraenderter Text, ein zu kurzer Schluesselteil, ein Verweis ohne Schluessel.
 */
#import <Foundation/Foundation.h>
#import "AIOMEMOMedia.h"

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

static NSData *fromHex(NSString *hex)
{
	NSMutableData *bytes = [NSMutableData data];
	for (NSUInteger i = 0; i + 1 < [hex length]; i += 2) {
		unsigned int one = 0;
		[[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&one];
		uint8_t b = (uint8_t)one;
		[bytes appendBytes:&b length:1];
	}
	return bytes;
}

static NSString *toHex(NSData *d)
{
	NSMutableString *s = [NSMutableString string];
	const uint8_t *b = [d bytes];
	for (NSUInteger i = 0; i < [d length]; i++) [s appendFormat:@"%02x", b[i]];
	return s;
}

int main(void) { @autoreleasepool {
	/* NIST CAVP, gcmDecrypt256, Testfall mit 128 Bit Text und 96 Bit Vektor.
	 * Schluessel, Vektor, Geheimtext, Pruefwert und erwarteter Klartext. */
	NSString *key = @"4c8ebfe1444ec1b2d503c6986659af2c94fafe945f72c1e8486a5acfedb8a0f8";
	NSString *iv  = @"473360e0ad24889959858995";
	NSString *ct  = @"d2c78110ac7e8f107c0df0570bd7c90c";
	NSString *tag = @"c26a379b6d98ef2852ead8ce83a833a7";
	NSString *pt  = @"7789b41cb3ee548814ca0b388c10b343";

	//So, wie XEP-0454 es zusammensetzt: Vektor und Schluessel im Bruchstueck, Pruefwert am Ende
	NSMutableData *material = [[fromHex(iv) mutableCopy] mutableCopy];
	[material appendData:fromHex(key)];

	NSMutableData *file = [[fromHex(ct) mutableCopy] mutableCopy];
	[file appendData:fromHex(tag)];

	check(@"Das Schluesselmaterial hat die erwartete Laenge", [material length] == 44,
		  [NSString stringWithFormat:@"war %lu", (unsigned long)[material length]]);

	NSData *opened = AIOMEMOMediaDecrypt(file, material);
	check(@"Ein fremder Pruefwert aus der NIST-Reihe geht auf",
		  [toHex(opened) isEqualToString:pt], toHex(opened));

	//Ein veraenderter Pruefwert darf NICHTS liefern
	NSMutableData *badTag = [file mutableCopy];
	((uint8_t *)[badTag mutableBytes])[[badTag length] - 1] ^= 0x01;
	check(@"Ein veraenderter Pruefwert liefert nichts",
		  AIOMEMOMediaDecrypt(badTag, material) == nil, nil);

	//Ein veraenderter Text ebenso
	NSMutableData *badText = [file mutableCopy];
	((uint8_t *)[badText mutableBytes])[0] ^= 0x01;
	check(@"Ein veraenderter Text liefert nichts",
		  AIOMEMOMediaDecrypt(badText, material) == nil, nil);

	//Und ein falscher Schluessel
	NSMutableData *badKey = [material mutableCopy];
	((uint8_t *)[badKey mutableBytes])[20] ^= 0x01;
	check(@"Ein falscher Schluessel liefert nichts",
		  AIOMEMOMediaDecrypt(file, badKey) == nil, nil);

	//Eine Datei, die kuerzer ist als der Pruefwert, ist keine von uns
	check(@"Eine zu kurze Datei liefert nichts",
		  AIOMEMOMediaDecrypt([NSData dataWithBytes:"kurz" length:4], material) == nil, nil);

	//Jetzt die Adressen. Zuerst die echte aus dem Protokoll des Live-Tests.
	NSString *real = @"aesgcm://share.conversations.im/knutmann/message/8Edi5w0drQc4lgXl/"
					  "RECORDING_20260915_231545105.m4a#0a2acde7f0acb5fe69c21cb5523efdfd"
					  "3501c54c2188575c4449ecde27217dc3126439879efea65a9a9486ce";
	NSString *where = nil;
	NSData *carried = nil;
	check(@"Eine echte Sprachnachricht-Adresse wird gelesen",
		  AIOMEMOMediaReadLink(real, &where, &carried), nil);
	check(@"und zeigt auf dieselbe Datei ueber https",
		  [where isEqualToString:@"https://share.conversations.im/knutmann/message/"
							      "8Edi5w0drQc4lgXl/RECORDING_20260915_231545105.m4a"], where);
	check(@"und traegt vierundvierzig Byte Schluesselmaterial", [carried length] == 44,
		  [NSString stringWithFormat:@"waren %lu", (unsigned long)[carried length]]);

	//Was NICHT gelesen werden darf
	check(@"Eine gewoehnliche Adresse ist keine verschluesselte",
		  !AIOMEMOMediaReadLink(@"https://example.org/bild.png", NULL, NULL), nil);
	check(@"Eine Adresse ohne Schluessel wird abgelehnt",
		  !AIOMEMOMediaReadLink(@"aesgcm://example.org/bild.png", NULL, NULL), nil);
	check(@"Ein Bruchstueck der falschen Laenge wird abgelehnt",
		  !AIOMEMOMediaReadLink(@"aesgcm://example.org/bild.png#0a2acde7", NULL, NULL), nil);
	check(@"Ein Bruchstueck, das kein Hexadezimal ist, wird abgelehnt",
		  !AIOMEMOMediaReadLink(@"aesgcm://example.org/bild.png#"
								 "zzzzcde7f0acb5fe69c21cb5523efdfd3501c54c2188575c4449ecde"
								 "27217dc3126439879efea65a9a9486ce", NULL, NULL), nil);

	//Die aeltere Form mit sechzehn Byte Vektor muss ebenfalls gelesen werden
	NSMutableString *longer = [NSMutableString stringWithString:@"aesgcm://example.org/a.png#"];
	for (int i = 0; i < 48; i++) [longer appendString:@"ab"];
	NSData *longerMaterial = nil;
	check(@"Die aeltere Form mit laengerem Vektor wird auch gelesen",
		  AIOMEMOMediaReadLink(longer, NULL, &longerMaterial) && [longerMaterial length] == 48,
		  [NSString stringWithFormat:@"%lu", (unsigned long)[longerMaterial length]]);

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
