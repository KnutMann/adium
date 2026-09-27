/* Does an OMEMO message come out in the shape other clients accept, and come back in again?
 *
 * What is checked is the wire form, not the cryptography underneath: that the tag hangs ON THE
 * KEY and not on the text (Conversations refuses anything else with the note that the SENDER
 * should update their client), that one text goes to several devices at once and is encrypted
 * ONLY ONCE while doing so, that we do not write to ourselves, and that a message nobody could
 * read never comes into being at all.
 *
 * And the cases in which nothing may happen: a message to another device of the same account, a
 * mangled initialisation vector, a changed ciphertext.
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

/*! @brief Let Alice build a session to a device out of that device's bundle */
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

	//Bob's second device: a store of its own under an account name of its own, so that both
	//identities really are different, as with two real installations
	AIOMEMOStore *bobLaptop = [AIOMEMOStore storeForAccount:@"bob-laptop@example.org"];

	check(@"Bob's two devices have different numbers",
		  bobPhone.deviceIdentifier != bobLaptop.deviceIdentifier, nil);

	check(@"Alice reaches Bob's phone", letTalk(alice, BOB, bobPhone), nil);
	check(@"and Bob's laptop", letTalk(alice, BOB, bobLaptop), nil);

	NSDictionary *recipients = @{ BOB: @[@(bobPhone.deviceIdentifier), @(bobLaptop.deviceIdentifier)] };

	NSString *said = @"Shall we meet at eight? Regards, 👋";
	AIOMEMOMessage *sent = [AIOMEMOMessage encrypting:said withStore:alice forDevices:recipients];

	check(@"A message to two devices comes into being", sent != nil, nil);
	check(@"It carries our device number", sent.sender == alice.deviceIdentifier, nil);
	check(@"The initialisation vector is twelve bytes long", [sent.initialisationVector length] == 12,
		  [NSString stringWithFormat:@"was %lu", (unsigned long)[sent.initialisationVector length]]);
	check(@"The text was encrypted only once", [sent.keys count] == 2,
		  [NSString stringWithFormat:@"there were %lu keys", (unsigned long)[sent.keys count]]);

	//The size Conversations refuses a message over: sixteen bytes of key plus sixteen bytes of
	//tag, and that IN the key, not on the text
	check(@"The encrypted text is as long as the plain text",
		  [sent.payload length] == [[said dataUsingEncoding:NSUTF8StringEncoding] length],
		  [NSString stringWithFormat:@"%lu instead of %lu", (unsigned long)[sent.payload length],
		   (unsigned long)[[said dataUsingEncoding:NSUTF8StringEncoding] length]]);

	//Both devices read the same message
	NSString *atPhone = [AIOMEMOMessage textFromPayload:sent.payload
								   initialisationVector:sent.initialisationVector
												   keys:sent.keys
											   sentFrom:ALICE
												 device:alice.deviceIdentifier
											  withStore:bobPhone trouble:NULL];
	check(@"Bob's phone reads it", [atPhone isEqualToString:said], atPhone);

	NSString *atLaptop = [AIOMEMOMessage textFromPayload:sent.payload
									initialisationVector:sent.initialisationVector
													keys:sent.keys
												sentFrom:ALICE
												  device:alice.deviceIdentifier
											   withStore:bobLaptop trouble:NULL];
	check(@"and so does Bob's laptop", [atLaptop isEqualToString:said], atLaptop);

	//A device that was not meant finds nothing for itself
	AIOMEMOStore *stranger = [AIOMEMOStore storeForAccount:@"carol@example.org"];
	NSString *atStranger = [AIOMEMOMessage textFromPayload:sent.payload
									  initialisationVector:sent.initialisationVector
													  keys:sent.keys
												  sentFrom:ALICE
													device:alice.deviceIdentifier
												 withStore:stranger trouble:NULL];
	check(@"A device that was not meant finds nothing for itself", atStranger == nil, atStranger);

	//We do not write to ourselves
	NSDictionary *includingOurselves = @{
		BOB: @[@(bobPhone.deviceIdentifier)],
		ALICE: @[@(alice.deviceIdentifier)]
	};
	AIOMEMOMessage *second = [AIOMEMOMessage encrypting:@"once more" withStore:alice forDevices:includingOurselves];
	check(@"Our own device gets no copy", second != nil && [second.keys count] == 1,
		  second ? [NSString stringWithFormat:@"there were %lu", (unsigned long)[second.keys count]] : @"nothing at all");

	//A message nobody could read never comes into being at all
	AIOMEMOMessage *toNobody = [AIOMEMOMessage encrypting:@"into the void"
												withStore:alice
											   forDevices:@{ @"dave@example.org": @[@(999)] }];
	check(@"A message to nothing but unknown devices does not come into being", toNobody == nil, nil);

	//A changed ciphertext is noticed
	AIOMEMOMessage *third = [AIOMEMOMessage encrypting:@"unchanged" withStore:alice forDevices:recipients];
	NSMutableData *tampered = [third.payload mutableCopy];
	((uint8_t *)[tampered mutableBytes])[0] ^= 0xFF;
	NSString *broken = [AIOMEMOMessage textFromPayload:tampered
								  initialisationVector:third.initialisationVector
												  keys:third.keys
											  sentFrom:ALICE
												device:alice.deviceIdentifier
											 withStore:bobPhone trouble:NULL];
	check(@"A changed ciphertext is noticed", broken == nil, broken);

	//An initialisation vector of the wrong length is refused rather than guessed at
	AIOMEMOMessage *fourth = [AIOMEMOMessage encrypting:@"never mind" withStore:alice forDevices:recipients];
	NSString *wrongVector = [AIOMEMOMessage textFromPayload:fourth.payload
									   initialisationVector:[NSData dataWithBytes:"too few" length:7]
													   keys:fourth.keys
												   sentFrom:ALICE
													 device:alice.deviceIdentifier
												  withStore:bobPhone trouble:NULL];
	check(@"An initialisation vector that is too short is refused", wrongVector == nil, wrongVector);

	//The first message to a device has to be marked as opening the session
	BOOL anyStartsASession = NO;
	for (AIOMEMOKeyForDevice *one in sent.keys)
		if (one.startsASession) anyStartsASession = YES;
	check(@"The first message is marked as opening the session", anyStartsASession, nil);

	/* And so is the second one, because until Bob has answered, Alice does not know whether he
	 * ever got the first. Drop the one time key too early and a message that overtakes the
	 * first loses its only chance of arriving. */
	AIOMEMOMessage *later = [AIOMEMOMessage encrypting:@"and on we go" withStore:alice forDevices:recipients];
	BOOL stillStarting = NO;
	for (AIOMEMOKeyForDevice *one in later.keys)
		if (one.startsASession) stillStarting = YES;
	check(@"Until the other side has answered, the one time key stays with it", stillStarting, nil);

	//Bob reads it and can write back without ever having fetched a bundle from Alice
	[AIOMEMOMessage textFromPayload:later.payload
			   initialisationVector:later.initialisationVector
							   keys:later.keys
						   sentFrom:ALICE
							 device:alice.deviceIdentifier
						  withStore:bobPhone trouble:NULL];

	AIOMEMOMessage *answer = [AIOMEMOMessage encrypting:@"Yes, gladly"
											  withStore:bobPhone
											 forDevices:@{ ALICE: @[@(alice.deviceIdentifier)] }];
	check(@"Bob can answer without having fetched a bundle", answer != nil, nil);

	NSString *heard = [AIOMEMOMessage textFromPayload:answer.payload
								 initialisationVector:answer.initialisationVector
												 keys:answer.keys
											 sentFrom:BOB
											   device:bobPhone.deviceIdentifier
											withStore:alice trouble:NULL];
	check(@"and Alice reads the answer", [heard isEqualToString:@"Yes, gladly"], heard);

	//ONLY NOW, with Alice knowing that Bob is there, does the one time key go
	AIOMEMOMessage *afterward = [AIOMEMOMessage encrypting:@"understood"
												 withStore:alice
												forDevices:@{ BOB: @[@(bobPhone.deviceIdentifier)] }];
	BOOL stillStartingNow = NO;
	for (AIOMEMOKeyForDevice *one in afterward.keys)
		if (one.startsASession) stillStartingNow = YES;
	check(@"After the first answer it goes", !stillStartingNow, nil);

	NSString *finally = [AIOMEMOMessage textFromPayload:afterward.payload
								   initialisationVector:afterward.initialisationVector
												   keys:afterward.keys
											   sentFrom:ALICE
												 device:alice.deviceIdentifier
											  withStore:bobPhone trouble:NULL];
	check(@"and the conversation carries on", [finally isEqualToString:@"understood"], finally);

	/* The ordinary form, with the tag IN the key, has to open unchanged. The older reading,
	 * which hangs it on the end of the payload, is put back together while reading; that this
	 * does not break the normal case is what stands here. */
	AIOMEMOMessage *ordinary = [AIOMEMOMessage encrypting:@"packed the other way round"
												withStore:alice
											   forDevices:@{ BOB: @[@(bobPhone.deviceIdentifier)] }];
	AIOMEMOTrouble why = AIOMEMOTroubleNone;
	NSString *stillOpens = [AIOMEMOMessage textFromPayload:ordinary.payload
									  initialisationVector:ordinary.initialisationVector
													  keys:ordinary.keys
												  sentFrom:ALICE
													device:alice.deviceIdentifier
												 withStore:bobPhone
												   trouble:&why];
	check(@"The ordinary form still opens",
		  [stillOpens isEqualToString:@"packed the other way round"], stillOpens);
	check(@"and counts as unremarkable while doing so", why == AIOMEMOTroubleNone,
		  [NSString stringWithUTF8String:[AIOMEMOMessage nameOfTrouble:why]]);

	//A message without a payload is a ratchet step and not a fault
	AIOMEMOMessage *step = [AIOMEMOMessage encrypting:@"" withStore:alice
										   forDevices:@{ BOB: @[@(bobPhone.deviceIdentifier)] }];
	AIOMEMOTrouble stepWhy = AIOMEMOTroubleNone;
	NSString *nothing = [AIOMEMOMessage textFromPayload:[NSData data]
								   initialisationVector:step.initialisationVector
												   keys:step.keys
											   sentFrom:ALICE
												 device:alice.deviceIdentifier
											  withStore:bobPhone
												trouble:&stepWhy];
	check(@"A message without a payload is empty and not a fault",
		  [nothing isEqualToString:@""] && stepWhy == AIOMEMOTroubleNone,
		  [NSString stringWithUTF8String:[AIOMEMOMessage nameOfTrouble:stepWhy]]);

	//A key that is too short, with no matching payload, is named rather than swallowed
	AIOMEMOTrouble shortWhy = AIOMEMOTroubleNone;
	AIOMEMOKeyForDevice *stunted = [AIOMEMOMessage keyForDevice:bobPhone.deviceIdentifier
												 startsASession:NO
														wrapped:[NSData dataWithBytes:"too few" length:7]];
	[AIOMEMOMessage textFromPayload:[NSData dataWithBytes:"xxxxxxxxxxxxxxxxxxxx" length:20]
			   initialisationVector:ordinary.initialisationVector
							   keys:@[stunted]
						   sentFrom:ALICE
							 device:alice.deviceIdentifier
						  withStore:bobPhone
							trouble:&shortWhy];
	check(@"An unusable key is named",
		  shortWhy == AIOMEMOTroubleKeyWouldNotOpen,
		  [NSString stringWithUTF8String:[AIOMEMOMessage nameOfTrouble:shortWhy]]);

	//A rejected device is neither written to nor read from
	NSString *laptopPrint = [alice fingerprintForJID:BOB device:bobLaptop.deviceIdentifier];
	check(@"Alice knows the laptop's fingerprint", laptopPrint != nil, nil);

	[alice setTrust:AIOMEMOTrustRejected forFingerprint:laptopPrint];
	AIOMEMOMessage *afterRejecting = [AIOMEMOMessage encrypting:@"to the phone only"
													  withStore:alice
													 forDevices:recipients];
	check(@"A rejected device gets no copy any more",
		  afterRejecting != nil && [afterRejecting.keys count] == 1,
		  afterRejecting ? [NSString stringWithFormat:@"there were %lu",
							(unsigned long)[afterRejecting.keys count]] : @"nothing at all");

	//And the other way round: what comes from a rejected device is not read
	NSString *alicePrint = [bobPhone fingerprintForJID:ALICE device:alice.deviceIdentifier];
	[bobPhone setTrust:AIOMEMOTrustRejected forFingerprint:alicePrint];

	AIOMEMOMessage *fromRejected = [AIOMEMOMessage encrypting:@"all the same"
													withStore:alice
												   forDevices:@{ BOB: @[@(bobPhone.deviceIdentifier)] }];
	NSString *shouldStaySilent = [AIOMEMOMessage textFromPayload:fromRejected.payload
											initialisationVector:fromRejected.initialisationVector
															keys:fromRejected.keys
														sentFrom:ALICE
														  device:alice.deviceIdentifier
													   withStore:bobPhone trouble:NULL];
	check(@"Nothing is read from a rejected device", shouldStaySilent == nil, shouldStaySilent);

	[[NSFileManager defaultManager] removeItemAtPath:scratch error:NULL];

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
} }
