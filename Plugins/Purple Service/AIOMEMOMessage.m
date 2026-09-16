/*
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 *
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import "AIOMEMOMessage.h"
#import "AIOMEMOStore.h"
#import <omemo0.h>

/*
 * Taking an OMEMO message apart and putting one together.
 *
 * The shape is worth stating once, because it explains every decision below. The text is
 * encrypted a single time with a key made for this message alone. That key is then wrapped
 * separately for each device that should be able to read it, through the ratchet running with
 * that device. A message to somebody with three devices, sent from an account that has two
 * others of its own, therefore carries one payload and five wrapped keys.
 *
 * The detail that decides whether other clients accept what we send: in this, the older of the
 * two OMEMO forms, the authentication tag does not travel with the payload. It is appended to
 * the key, so the thing wrapped for each device is thirty two bytes, sixteen of key and sixteen
 * of tag. Conversations refuses anything else with a message telling the user that the SENDER
 * needs to update their client, which is a sentence one would rather not cause.
 */

#define KEY_AND_TAG		32		//sixteen bytes of key, sixteen of authentication tag
#define VECTOR_LENGTH	12

@interface AIOMEMOKeyForDevice ()
@property (readwrite, nonatomic) uint32_t device;
@property (readwrite, nonatomic) BOOL startsASession;
@property (readwrite, nonatomic, strong) NSData *wrapped;
@end

@implementation AIOMEMOKeyForDevice
@end

@interface AIOMEMOMessage ()
@property (readwrite, nonatomic) uint32_t sender;
@property (readwrite, nonatomic, strong) NSData *initialisationVector;
@property (readwrite, nonatomic, strong) NSData *payload;
@property (readwrite, nonatomic, strong) NSArray<AIOMEMOKeyForDevice *> *keys;
@end

@implementation AIOMEMOMessage

+ (AIOMEMOKeyForDevice *)keyForDevice:(uint32_t)device
					   startsASession:(BOOL)startsASession
							  wrapped:(NSData *)wrapped
{
	AIOMEMOKeyForDevice *one = [[AIOMEMOKeyForDevice alloc] init];
	one.device = device;
	one.startsASession = startsASession;
	one.wrapped = wrapped;
	return one;
}

#pragma mark Writing

+ (instancetype)encrypting:(NSString *)text
				 withStore:(AIOMEMOStore *)store
				forDevices:(NSDictionary<NSString *, NSArray<NSNumber *> *> *)devicesByJID
{
	if (!text || !store) return nil;

	NSData *plain = [text dataUsingEncoding:NSUTF8StringEncoding];
	if (!plain) return nil;

	NSMutableData *cipher = [NSMutableData dataWithLength:[plain length]];
	uint8_t keyAndTag[KEY_AND_TAG];
	uint8_t vector[VECTOR_LENGTH];

	/* Both the key and the vector are made here rather than passed in: they must never be used
	 * twice, and the only way to be sure of that is for nobody else to be able to supply them. */
	if (omemo0EncryptMessage([cipher mutableBytes], keyAndTag, vector, [plain bytes], [plain length]) != 0)
		return nil;

	NSData *messageKey = [NSData dataWithBytes:keyAndTag length:sizeof(keyAndTag)];
	NSMutableArray *wrappedForEach = [NSMutableArray array];

	[devicesByJID enumerateKeysAndObjectsUsingBlock:^(NSString *jid, NSArray<NSNumber *> *devices, BOOL *stop) {
		for (NSNumber *device in devices) {
			uint32_t number = [device unsignedIntValue];

			//Never to ourselves: our own ratchet with ourselves is not a thing that exists
			if ([jid isEqualToString:store.account] && number == store.deviceIdentifier)
				continue;

			/* A device the user has turned down is not written to, and that is the whole point
			 * of having been asked. Undecided is still written to, which is the trust on first
			 * use every other client starts from, and is honest only for as long as the
			 * interface can show what has piled up undecided. */
			NSString *print = [store fingerprintForJID:jid device:number];
			if (print && [store trustForFingerprint:print] == AIOMEMOTrustRejected)
				continue;

			/* A device we have no session with is skipped rather than refused. Somebody with
			 * four devices, one of which has never published a bundle, should still be written
			 * to on the other three. */
			BOOL startsASession = NO;
			NSData *wrapped = [store encryptKey:messageKey forJID:jid device:number wasPreKey:&startsASession];
			if (!wrapped) continue;

			[wrappedForEach addObject:[self keyForDevice:number startsASession:startsASession wrapped:wrapped]];
		}
	}];

	/* Nobody at all is the one case where failing beats sending. A message wrapped for no
	 * device still looks sent from here and arrives as noise everywhere else. */
	if (![wrappedForEach count]) return nil;

	AIOMEMOMessage *message = [[self alloc] init];
	message.sender = store.deviceIdentifier;
	message.initialisationVector = [NSData dataWithBytes:vector length:sizeof(vector)];
	message.payload = cipher;
	message.keys = wrappedForEach;
	return message;
}

#pragma mark Reading

+ (const char *)nameOfTrouble:(AIOMEMOTrouble)trouble
{
	switch (trouble) {
		case AIOMEMOTroubleNone:				return "nothing wrong";
		case AIOMEMOTroubleNotAddressedToUs:	return "not addressed to this device";
		case AIOMEMOTroubleVectorWrongLength:	return "the vector is not twelve bytes";
		case AIOMEMOTroubleKeyWouldNotOpen:		return "the ratchet would not open the key";
		case AIOMEMOTroubleKeyTooShort:			return "the sender put the authentication tag on the "
														"payload rather than in the key";
		case AIOMEMOTroublePayloadWouldNotOpen:	return "the key came out but the text did not";
		case AIOMEMOTroubleDeviceRejected:		return "this device was turned down by the user";
	}
	return "unknown";
}

+ (NSString *)textFromPayload:(NSData *)payload
		 initialisationVector:(NSData *)vector
						 keys:(NSArray<AIOMEMOKeyForDevice *> *)keys
					 sentFrom:(NSString *)bareJID
					   device:(uint32_t)device
					withStore:(AIOMEMOStore *)store
					  trouble:(AIOMEMOTrouble *)trouble
{
	AIOMEMOTrouble went = AIOMEMOTroubleNone;

	#define GAVE_UP(why) do { if (trouble) *trouble = (why); return nil; } while (0)

	if (!payload || !vector || !store) GAVE_UP(AIOMEMOTroubleNotAddressedToUs);

	/* The vector is the one length this side must insist on, because the library types it as
	 * twelve bytes and would read past a shorter one. Some older clients send sixteen, and
	 * those messages are declined rather than guessed at. */
	if ([vector length] != VECTOR_LENGTH) GAVE_UP(AIOMEMOTroubleVectorWrongLength);

	AIOMEMOKeyForDevice *ours = nil;
	for (AIOMEMOKeyForDevice *one in keys) {
		if (one.device != store.deviceIdentifier) continue;
		ours = one;
		break;
	}

	//Addressed to this account's other devices but not to us, which is ordinary and not a fault
	if (!ours) GAVE_UP(AIOMEMOTroubleNotAddressedToUs);

	/* A device the user turned down is not read from either. Showing its messages anyway would
	 * make the decision decorative, and the user would have no way of telling that the thing
	 * they rejected is still talking to them. */
	NSString *print = [store fingerprintForJID:bareJID device:device];
	if (print && [store trustForFingerprint:print] == AIOMEMOTrustRejected)
		GAVE_UP(AIOMEMOTroubleDeviceRejected);

	NSData *messageKey = [store decryptKey:ours.wrapped
								   fromJID:bareJID
									device:device
								  isPreKey:ours.startsASession];
	if (!messageKey) GAVE_UP(AIOMEMOTroubleKeyWouldNotOpen);

	/* A message with no payload is a message sent only to move the ratchet along, which happens
	 * after a long one sided conversation. There is nothing to show, and nothing is wrong. */
	if (![payload length]) { if (trouble) *trouble = went; return @""; }

	/* Sixteen bytes of key and sixteen of authentication tag, which is where this form of OMEMO
	 * puts the tag. Some senders read the specification the other way round and put the tag at
	 * the end of the payload instead, giving us a bare sixteen byte key. Rather than refuse
	 * those, the two are put back together the way the library expects them, because the
	 * difference is where sixteen bytes sit and not what they are. */
	if ([messageKey length] < KEY_AND_TAG) {
		if ([messageKey length] != KEY_AND_TAG / 2 || [payload length] <= KEY_AND_TAG / 2)
			GAVE_UP(AIOMEMOTroubleKeyTooShort);

		NSMutableData *joined = [messageKey mutableCopy];
		NSUInteger tagStarts = [payload length] - (KEY_AND_TAG / 2);
		[joined appendData:[payload subdataWithRange:NSMakeRange(tagStarts, KEY_AND_TAG / 2)]];

		messageKey = joined;
		payload = [payload subdataWithRange:NSMakeRange(0, tagStarts)];

		if (trouble) *trouble = AIOMEMOTroubleKeyTooShort;	//worth knowing, even though it worked
	}

	NSMutableData *plain = [NSMutableData dataWithLength:[payload length]];
	if (omemo0DecryptMessage([plain mutableBytes], [messageKey bytes], [messageKey length],
							 [vector bytes], [payload bytes], [payload length]) != 0)
		GAVE_UP(AIOMEMOTroublePayloadWouldNotOpen);

	if (trouble) *trouble = went;
	return [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding];

	#undef GAVE_UP
}

@end
