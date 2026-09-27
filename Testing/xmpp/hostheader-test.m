/* Does the platform let us set the Host header ourselves?
 *
 * One feature rests on it: some servers hand out upload addresses under a name that does not
 * resolve to the machine the service runs on. Adium then sends the file to the machine it is
 * talking to anyway, but keeps the server's name in the request. That is exactly what matters:
 * ejabberd's mod_http_upload looks up the responsible process by that name
 * (parse_http_request -> gen_mod:get_module_proc), and without it answers with 404 and
 * "Upload not configured for this host".
 *
 * If NSURLSession were to drop or overwrite the header, the detour would lead nowhere without
 * anything saying so. Hence this measures rather than assumes.
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
	if (argc < 2) { printf("FAIL  no port was given\n"); return 1; }

	NSString *where = [NSString stringWithFormat:@"http://127.0.0.1:%s/upload/a/b/picture.png", argv[1]];
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

	/* The test server answers with 201 only if the Host header really arrived the way we set
	 * it. Anything else it answers with 409. */
	check(@"A Host header we set ourselves arrives unchanged", status == 201,
		  problem ?: [NSString stringWithFormat:@"the answer was %ld", (long)status]);

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
} }
