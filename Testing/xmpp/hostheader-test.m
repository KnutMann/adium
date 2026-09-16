/* Laesst die Plattform uns den Host-Kopf selbst setzen?
 *
 * Darauf ruht eine Funktion: manche Server verteilen Upload-Adressen auf einem Namen, der nicht
 * zu der Maschine aufloest, auf der der Dienst laeuft. Adium schickt die Datei dann an die
 * Maschine, mit der es ohnehin redet, behaelt aber den Namen des Servers in der Anfrage. Genau
 * darauf kommt es an: ejabberds mod_http_upload sucht den zustaendigen Prozess anhand dieses
 * Namens (parse_http_request -> gen_mod:get_module_proc), und ohne ihn antwortet es mit 404
 * und "Upload not configured for this host".
 *
 * Wuerde NSURLSession den Kopf verwerfen oder ueberschreiben, liefe der Umweg ins Leere, ohne
 * dass irgendetwas es sagt. Deshalb wird hier gemessen statt angenommen.
 */
#import <Foundation/Foundation.h>

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

int main(int argc, char **argv) { @autoreleasepool {
	if (argc < 2) { printf("FAIL  kein Port uebergeben\n"); return 1; }

	NSString *where = [NSString stringWithFormat:@"http://127.0.0.1:%s/upload/a/b/bild.png", argv[1]];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:where]];

	[request setHTTPMethod:@"PUT"];
	[request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"beispiel.example.org" forHTTPHeaderField:@"Host"];

	__block NSInteger status = 0;
	__block NSString *problem = nil;
	dispatch_semaphore_t done = dispatch_semaphore_create(0);

	[[[NSURLSession sharedSession] uploadTaskWithRequest:request
											   fromData:[NSData dataWithBytes:"xyz" length:3]
									  completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
		status = [r isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)r statusCode] : 0;
		problem = [e localizedDescription];
		dispatch_semaphore_signal(done);
	}] resume];

	dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 15ull * NSEC_PER_SEC));

	/* Der Testserver antwortet nur dann mit 201, wenn der Host-Kopf wirklich so ankam, wie wir
	 * ihn gesetzt haben. Alles andere beantwortet er mit 409. */
	check(@"Ein selbst gesetzter Host-Kopf kommt unveraendert an", status == 201,
		  problem ?: [NSString stringWithFormat:@"Antwort war %ld", (long)status]);

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
