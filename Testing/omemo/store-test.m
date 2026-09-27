/* Does the OMEMO store survive what everyday use does to it?
 *
 * What is checked is not the cryptography, that stands in the roundtrip test next door, but the
 * bookkeeping around it, and precisely at the places where a fault stays quiet and only turns up
 * weeks later as a conversation that will not open any more:
 *
 *   - An identity has to survive a restart, or we are a new device every time.
 *   - A ratchet that moves on while decrypting has to be on disk BEFORE the answer is returned.
 *     Otherwise the same message decrypts again after a restart, and the one after it never does.
 *   - Messages overtake each other. The skipped keys have to be kept and found again later, each
 *     one exactly once.
 *   - A one time key has to disappear once it is used, and the published bundle counts as stale
 *     from then on.
 *
 * The test puts its files in a directory of its own and does not touch the keys of a real
 * account.
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

/*! @brief Take a key out of Bob's bundle and let Alice build a session to him */
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

	//Looking must not create anything
	check(@"An account with no history has no store yet",
		  ![AIOMEMOStore haveStoreForAccount:ALICE], nil);

	//An identity comes into being
	AIOMEMOStore *alice = [AIOMEMOStore storeForAccount:ALICE];
	check(@"and afterwards it does", [AIOMEMOStore haveStoreForAccount:ALICE], nil);
	check(@"An account with no history is given an identity", alice != nil, nil);
	check(@"and a device number that is not zero", alice.deviceIdentifier != 0,
		  [NSString stringWithFormat:@"was %u", alice.deviceIdentifier]);
	check(@"The fingerprint has the length one reads out aloud",
		  [alice.fingerprint length] == 64 + 7,
		  [NSString stringWithFormat:@"was %lu", (unsigned long)[alice.fingerprint length]]);
	check(@"The bundle holds one hundred one time keys", [[alice preKeys] count] == 100,
		  [NSString stringWithFormat:@"there were %lu", (unsigned long)[[alice preKeys] count]]);

	//And survives a restart
	NSString *fingerprintBefore = alice.fingerprint;
	uint32_t deviceBefore = alice.deviceIdentifier;

	[AIOMEMOStore closeStoreForAccount:ALICE];
	alice = [AIOMEMOStore storeForAccount:ALICE];

	check(@"After a restart it is the same identity",
		  [alice.fingerprint isEqualToString:fingerprintBefore], nil);
	check(@"and the same device number", alice.deviceIdentifier == deviceBefore, nil);

	//Two sides can write to each other
	AIOMEMOStore *bob = [AIOMEMOStore storeForAccount:BOB];
	check(@"Two accounts have different identities",
		  ![bob.fingerprint isEqualToString:alice.fingerprint], nil);

	check(@"Alice builds a session out of Bob's bundle", letTalk(alice, bob), nil);
	check(@"and knows afterwards that she has one",
		  [alice hasSessionWithJID:BOB device:bob.deviceIdentifier], nil);
	check(@"She now knows Bob's fingerprint",
		  [[alice fingerprintForJID:BOB device:bob.deviceIdentifier] isEqualToString:bob.fingerprint],
		  [alice fingerprintForJID:BOB device:bob.deviceIdentifier]);

	//A message key goes across and is unpacked on the other side
	uint8_t material[32];
	for (int i = 0; i < 32; i++) material[i] = (uint8_t)(i * 7 + 1);
	NSData *messageKey = [NSData dataWithBytes:material length:sizeof(material)];

	BOOL wasPreKey = NO;
	NSData *wrapped = [alice encryptKey:messageKey forJID:BOB device:bob.deviceIdentifier wasPreKey:&wasPreKey];
	check(@"Alice packs a message key for Bob", wrapped != nil, nil);
	check(@"The first message carries a one time key", wasPreKey, nil);

	NSData *unwrapped = [bob decryptKey:wrapped fromJID:ALICE device:alice.deviceIdentifier isPreKey:wasPreKey];
	check(@"Bob unpacks it again", [unwrapped isEqualToData:messageKey], nil);
	check(@"and got a session of his own accord while doing so",
		  [bob hasSessionWithJID:ALICE device:alice.deviceIdentifier], nil);
	check(@"Bob now knows Alice's fingerprint",
		  [[bob fingerprintForJID:ALICE device:alice.deviceIdentifier] isEqualToString:alice.fingerprint], nil);

	//The used one time key is gone, and the bundle counts as stale
	check(@"A used one time key is replaced", [[bob preKeys] count] == 100,
		  [NSString stringWithFormat:@"there were %lu", (unsigned long)[[bob preKeys] count]]);
	check(@"and the published bundle counts as stale", bob.bundleNeedsPublishing, nil);

	//Messages that overtake each other
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

	//The third one first, then the first, then the second
	for (NSNumber *which in @[@2, @0, @1]) {
		NSDictionary *one = sent[[which intValue]];
		NSData *got = [bob decryptKey:one[@"packed"]
							  fromJID:ALICE
							   device:alice.deviceIdentifier
							 isPreKey:[one[@"prekey"] boolValue]];
		check([NSString stringWithFormat:@"Message %d opens even out of order",
			   [which intValue] + 1],
			  [got isEqualToData:keys[[which intValue]]], nil);
	}

	//A ratchet that has moved on has to still know that after a restart
	BOOL fourthWasPreKey = NO;
	NSData *fourth = [alice encryptKey:messageKey forJID:BOB device:bob.deviceIdentifier wasPreKey:&fourthWasPreKey];

	[AIOMEMOStore closeStoreForAccount:BOB];
	bob = [AIOMEMOStore storeForAccount:BOB];

	check(@"After a restart Bob's session is still there",
		  [bob hasSessionWithJID:ALICE device:alice.deviceIdentifier], nil);
	NSData *afterRestart = [bob decryptKey:fourth fromJID:ALICE device:alice.deviceIdentifier isPreKey:fourthWasPreKey];
	check(@"and the next message opens with it",
		  [afterRestart isEqualToData:messageKey], nil);

	//The same message a second time must not open again
	NSData *again = [bob decryptKey:fourth fromJID:ALICE device:alice.deviceIdentifier isPreKey:fourthWasPreKey];
	check(@"The same message a second time does not open any more", again == nil,
		  again ? @"it opened" : nil);

	//What the user decides stays decided
	check(@"An unknown device is undecided at first",
		  [alice trustForFingerprint:bob.fingerprint] == AIOMEMOTrustUndecided, nil);
	[alice setTrust:AIOMEMOTrustAccepted forFingerprint:bob.fingerprint];

	[AIOMEMOStore closeStoreForAccount:ALICE];
	alice = [AIOMEMOStore storeForAccount:ALICE];
	check(@"A decision survives the restart",
		  [alice trustForFingerprint:bob.fingerprint] == AIOMEMOTrustAccepted, nil);
	check(@"and sits with the contact it belongs to",
		  [[alice fingerprintsForJID:BOB][bob.fingerprint] integerValue] == AIOMEMOTrustAccepted, nil);

	//A bundle whose parts do not belong together is not accepted
	AIOMEMOStore *mallory = [AIOMEMOStore storeForAccount:@"mallory@example.org"];
	NSNumber *somePreKey = [[[bob preKeys] allKeys] firstObject];
	BOOL taken = [alice startSessionWithJID:@"carol@example.org"
									 device:4242
								identityKey:mallory.identityKey		//somebody else's identity
							   signedPreKey:bob.signedPreKey
						 signedPreKeyItself:bob.signedPreKeyIdentifier
								  signature:bob.signedPreKeySignature	//Bob's own signature
									 preKey:[bob preKeys][somePreKey]
							   preKeyItself:[somePreKey unsignedIntValue]];
	check(@"A bundle with somebody else's signature is refused", !taken, nil);

	//And a bundle of the wrong size likewise
	BOOL stunted = [alice startSessionWithJID:@"carol@example.org"
									   device:4243
								  identityKey:[NSData dataWithBytes:"tiny" length:4]
								 signedPreKey:bob.signedPreKey
						   signedPreKeyItself:bob.signedPreKeyIdentifier
									signature:bob.signedPreKeySignature
									   preKey:[bob preKeys][somePreKey]
								 preKeyItself:[somePreKey unsignedIntValue]];
	check(@"A bundle of the wrong size is refused", !stunted, nil);

	/* What the account has gathered over time, for the preferences: one entry per device,
	 * with address, device number, fingerprint and decision. */
	NSArray *everyone = [alice everyDeviceSeen];
	check(@"Alice keeps every device she has ever met", [everyone count] == 1,
		  [NSString stringWithFormat:@"there were %lu", (unsigned long)[everyone count]]);

	NSDictionary *first = [everyone firstObject];
	check(@"The entry names the address without the device number",
		  [first[@"jid"] isEqualToString:BOB], first[@"jid"]);
	check(@"and the device number as a number",
		  [first[@"device"] unsignedIntValue] == bob.deviceIdentifier,
		  [first[@"device"] stringValue]);
	check(@"and the fingerprint",
		  [first[@"fingerprint"] isEqualToString:bob.fingerprint], first[@"fingerprint"]);
	check(@"and what was decided about it",
		  [first[@"trust"] integerValue] == AIOMEMOTrustAccepted,
		  [first[@"trust"] stringValue]);

	//There is no address with a space in it, so the last space is a safe place to split
	check(@"The address is not split at the wrong space",
		  [first[@"jid"] rangeOfString:@" "].location == NSNotFound, nil);

	//Nobody else may be able to read the file
	NSString *file = [scratch stringByAppendingPathComponent:@"alice%3Aexample.org.omemo"];
	file = [scratch stringByAppendingPathComponent:@"alice@example.org.omemo"];
	NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:file error:NULL];
	check(@"The key file is readable by its owner only",
		  [attributes[NSFilePosixPermissions] shortValue] == 0600,
		  [NSString stringWithFormat:@"was %o", [attributes[NSFilePosixPermissions] shortValue]]);

	[[NSFileManager defaultManager] removeItemAtPath:scratch error:NULL];

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
} }
