/* Does a file shared in encrypted form (XEP-0454) come out right again?
 *
 * The check runs against a PUBLISHED test value from the NIST series for AES-256-GCM, not
 * against ourselves. That difference is the whole point: a decryption that only matches our own
 * encryption proves self consistency, not that a stranger's file opens.
 *
 * Plus the cases in which NOTHING may come out: a changed tag, a changed ciphertext, a key part
 * that is too short, a link without a key.
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
	/* NIST CAVP, gcmDecrypt256, the case with 128 bits of text and a 96 bit vector.
	 * Key, vector, ciphertext, tag and the expected plain text. */
	NSString *key = @"4c8ebfe1444ec1b2d503c6986659af2c94fafe945f72c1e8486a5acfedb8a0f8";
	NSString *iv  = @"473360e0ad24889959858995";
	NSString *ct  = @"d2c78110ac7e8f107c0df0570bd7c90c";
	NSString *tag = @"c26a379b6d98ef2852ead8ce83a833a7";
	NSString *pt  = @"7789b41cb3ee548814ca0b388c10b343";

	//The way XEP-0454 puts it together: vector and key in the fragment, tag at the end
	NSMutableData *material = [[fromHex(iv) mutableCopy] mutableCopy];
	[material appendData:fromHex(key)];

	NSMutableData *file = [[fromHex(ct) mutableCopy] mutableCopy];
	[file appendData:fromHex(tag)];

	check(@"The key material has the expected length", [material length] == 44,
		  [NSString stringWithFormat:@"was %lu", (unsigned long)[material length]]);

	NSData *opened = AIOMEMOMediaDecrypt(file, material);
	check(@"A stranger's value from the NIST series opens",
		  [toHex(opened) isEqualToString:pt], toHex(opened));

	//A changed tag must yield NOTHING
	NSMutableData *badTag = [file mutableCopy];
	((uint8_t *)[badTag mutableBytes])[[badTag length] - 1] ^= 0x01;
	check(@"A changed tag yields nothing",
		  AIOMEMOMediaDecrypt(badTag, material) == nil, nil);

	//A changed ciphertext likewise
	NSMutableData *badText = [file mutableCopy];
	((uint8_t *)[badText mutableBytes])[0] ^= 0x01;
	check(@"A changed ciphertext yields nothing",
		  AIOMEMOMediaDecrypt(badText, material) == nil, nil);

	//And a wrong key
	NSMutableData *badKey = [material mutableCopy];
	((uint8_t *)[badKey mutableBytes])[20] ^= 0x01;
	check(@"A wrong key yields nothing",
		  AIOMEMOMediaDecrypt(file, badKey) == nil, nil);

	//A file shorter than the tag is not one of ours
	check(@"A file that is too short yields nothing",
		  AIOMEMOMediaDecrypt([NSData dataWithBytes:"tiny" length:4], material) == nil, nil);

	//Now the addresses. First the real one out of the live test log.
	NSString *real = @"aesgcm://share.conversations.im/knutmann/message/8Edi5w0drQc4lgXl/"
					  "RECORDING_20260915_231545105.m4a#0a2acde7f0acb5fe69c21cb5523efdfd"
					  "3501c54c2188575c4449ecde27217dc3126439879efea65a9a9486ce";
	NSString *where = nil;
	NSData *carried = nil;
	check(@"A real voice message address is read",
		  AIOMEMOMediaReadLink(real, &where, &carried), nil);
	check(@"and points at the same file over https",
		  [where isEqualToString:@"https://share.conversations.im/knutmann/message/"
							      "8Edi5w0drQc4lgXl/RECORDING_20260915_231545105.m4a"], where);
	check(@"and carries forty four bytes of key material", [carried length] == 44,
		  [NSString stringWithFormat:@"there were %lu", (unsigned long)[carried length]]);

	//What must NOT be read
	check(@"An ordinary address is not an encrypted one",
		  !AIOMEMOMediaReadLink(@"https://example.org/picture.png", NULL, NULL), nil);
	check(@"An address without a key is refused",
		  !AIOMEMOMediaReadLink(@"aesgcm://example.org/picture.png", NULL, NULL), nil);
	check(@"A fragment of the wrong length is refused",
		  !AIOMEMOMediaReadLink(@"aesgcm://example.org/picture.png#0a2acde7", NULL, NULL), nil);
	check(@"A fragment that is not hexadecimal is refused",
		  !AIOMEMOMediaReadLink(@"aesgcm://example.org/picture.png#"
								 "zzzzcde7f0acb5fe69c21cb5523efdfd3501c54c2188575c4449ecde"
								 "27217dc3126439879efea65a9a9486ce", NULL, NULL), nil);

	//The older form with a sixteen byte vector has to be read as well
	NSMutableString *longer = [NSMutableString stringWithString:@"aesgcm://example.org/a.png#"];
	for (int i = 0; i < 48; i++) [longer appendString:@"ab"];
	NSData *longerMaterial = nil;
	check(@"The older form with the longer vector is read too",
		  AIOMEMOMediaReadLink(longer, NULL, &longerMaterial) && [longerMaterial length] == 48,
		  [NSString stringWithFormat:@"%lu", (unsigned long)[longerMaterial length]]);

	/* The other direction: what we encrypt ourselves has to open with the SAME decryptor that
	 * was checked against the NIST value above. That hangs the sending direction on somebody
	 * else's yardstick instead of on itself. */
	NSData *secret = [@"A voice message, let us pretend" dataUsingEncoding:NSUTF8StringEncoding];
	NSData *ourMaterial = nil;
	NSData *sealed = AIOMEMOMediaEncrypt(secret, &ourMaterial);

	check(@"A file can be encrypted", [sealed length] > 0, nil);
	check(@"It is exactly sixteen bytes longer than before",
		  [sealed length] == [secret length] + 16,
		  [NSString stringWithFormat:@"%lu instead of %lu", (unsigned long)[sealed length],
		   (unsigned long)[secret length] + 16]);
	check(@"The key material is forty four bytes long", [ourMaterial length] == 44, nil);
	check(@"And it opens again with the same decryptor",
		  [AIOMEMOMediaDecrypt(sealed, ourMaterial) isEqualToData:secret], nil);

	//The same thing twice must never give the same key
	NSData *otherMaterial = nil;
	AIOMEMOMediaEncrypt(secret, &otherMaterial);
	check(@"Encrypted twice means different twice",
		  ![ourMaterial isEqualToData:otherMaterial], nil);

	//And the address that comes out of it has to open again with our own reader
	NSString *made = AIOMEMOMediaMakeLink(@"https://up.example.org/a/b/note.m4a", ourMaterial);
	NSString *backAddress = nil;
	NSData *backMaterial = nil;
	check(@"Address and key become an aesgcm link",
		  [made hasPrefix:@"aesgcm://up.example.org/a/b/note.m4a#"], made);
	check(@"which our own reader takes apart again",
		  AIOMEMOMediaReadLink(made, &backAddress, &backMaterial) &&
		  [backAddress isEqualToString:@"https://up.example.org/a/b/note.m4a"] &&
		  [backMaterial isEqualToData:ourMaterial], backAddress);

	//The extension, even with a key or a query hanging off the end
	check(@"The extension is found even behind the key",
		  [AIOMEMOMediaExtensionOf(made) isEqualToString:@"m4a"], AIOMEMOMediaExtensionOf(made));
	check(@"and behind a query",
		  [AIOMEMOMediaExtensionOf(@"https://x/y/picture.PNG?t=1") isEqualToString:@"png"], nil);
	check(@"Without a dot there is no extension",
		  AIOMEMOMediaExtensionOf(@"https://x/y/nodot") == nil, nil);

	/* What a file IS when its name does not say so. A picture pasted into the window lands in
	 * a file without any extension, and by name it is no longer a picture after that. */
	struct { const char *bytes; size_t n; const char *type; const char *ending; } samples[] = {
		{ "\x89PNG\r\n\x1a\n....", 12, "image/png", "png" },
		{ "\xff\xd8\xff\xe0JFIF", 9, "image/jpeg", "jpg" },
		{ "GIF89a.......", 13, "image/gif", "gif" },
		{ "RIFF\x24\x00\x00\x00WEBPVP8 ", 16, "image/webp", "webp" },
	};

	for (unsigned i = 0; i < sizeof(samples) / sizeof(samples[0]); i++) {
		NSString *ending = nil;
		NSString *kind = AIMediaKindOfData([NSData dataWithBytes:samples[i].bytes length:samples[i].n],
										   &ending);
		check([NSString stringWithFormat:@"%s is recognised by its first bytes", samples[i].type],
			  [kind isEqualToString:[NSString stringWithUTF8String:samples[i].type]] &&
			  [ending isEqualToString:[NSString stringWithUTF8String:samples[i].ending]],
			  kind ?: @"nothing at all");
	}

	check(@"And what is not a picture is not taken for one",
		  AIMediaKindOfData([NSData dataWithBytes:"This is simply text" length:20], NULL) == nil, nil);
	check(@"Nor is a file that is too short",
		  AIMediaKindOfData([NSData dataWithBytes:"\x89P" length:2], NULL) == nil, nil);
	check(@"RIFF on its own is not yet a WebP",
		  AIMediaKindOfData([NSData dataWithBytes:"RIFF\x24\x00\x00\x00AVI LIST" length:16], NULL) == nil,
		  nil);

	/* Rewriting an address onto a different host. Port, path and everything after them have to
	 * stay untouched, or the file lands somewhere other than intended. */
	NSURL *slot = [NSURL URLWithString:@"https://shoogee.com:5443/upload/977443/EscRx/picture%20one.png?t=1"];
	NSURL *moved = AIMediaSameAddressOnHost(slot, @"meet.shoogee.com");

	check(@"Only the host name changes",
		  [[moved absoluteString] isEqualToString:
		   @"https://meet.shoogee.com:5443/upload/977443/EscRx/picture%20one.png?t=1"],
		  [moved absoluteString]);

	check(@"If it is the same host already, nothing happens",
		  AIMediaSameAddressOnHost(slot, @"shoogee.com") == nil, nil);
	check(@"Upper and lower case do not count here",
		  AIMediaSameAddressOnHost(slot, @"SHOOGEE.COM") == nil, nil);
	check(@"Without a name nothing happens", AIMediaSameAddressOnHost(slot, @"") == nil, nil);
	check(@"Nor without an address", AIMediaSameAddressOnHost(nil, @"meet.shoogee.com") == nil, nil);

	//With no port in the original, none may be invented either
	NSURL *plain = [NSURL URLWithString:@"https://shoogee.com/upload/a/b.png"];
	check(@"A missing port is not invented",
		  [[AIMediaSameAddressOnHost(plain, @"meet.shoogee.com") absoluteString]
		   isEqualToString:@"https://meet.shoogee.com/upload/a/b.png"],
		  [AIMediaSameAddressOnHost(plain, @"meet.shoogee.com") absoluteString]);

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
} }
