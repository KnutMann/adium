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

#import "AIOMEMOStore.h"
#import <omemo0.h>

/*
 * The durable half of OMEMO (XEP-0384).
 *
 * Everything here is bookkeeping around picomemo, which does the cryptography and holds no
 * state of its own beyond the two structures it hands back. Those structures are opaque on
 * purpose: they are written to disk as they come and read back the same way, so that a change
 * in the library's internals cannot be half understood by us.
 *
 * Three things in here are easy to get wrong and expensive to discover later.
 *
 * The first is that a ratchet advances when it is used, so a message that is decrypted but not
 * saved will decrypt again after a restart and then fail for good, because the ratchet moved
 * in memory and not on disk. Every method that touches a session therefore writes before it
 * returns, rather than leaving that to the caller.
 *
 * The second is that messages arrive out of order, and the ratchet has to keep the keys it
 * skipped over. Those are held here and handed back through the library's callbacks, which is
 * the only reason a message that overtakes another still opens.
 *
 * The third is that a one time key must be forgotten the moment it is used, or it is no longer
 * a one time key. Forgetting it means the bundle we published is now wrong, so this records
 * that the bundle needs publishing again and lets the wire half do it.
 */

#define OMEMO_DIRECTORY		@"OMEMO"

//What one account's file holds
#define KEY_DEVICE			@"device"
#define KEY_STORE			@"store"
#define KEY_SESSIONS		@"sessions"
#define KEY_SKIPPED			@"skipped"
#define KEY_TRUST			@"trust"
#define KEY_FINGERPRINTS	@"fingerprints"
#define KEY_SIGNED_MADE		@"signedPreKeyCreated"

//A skipped key, as one entry in that file
#define SKIPPED_RATCHET		@"dh"
#define SKIPPED_NUMBER		@"nr"
#define SKIPPED_KEY			@"mk"

/*
 * How many skipped keys to keep. Each one is a message that overtook another and may still
 * turn up; past a few hundred the sender is not merely out of order, and keeping more would
 * only help somebody trying to make us hold things.
 */
#define SKIPPED_LIMIT		512

@interface AIOMEMOStore ()
{
	struct omemo0Store		*store;
	NSMutableDictionary		*sessions;		//"jid deviceid" -> NSValue holding struct omemo0Session *
}
@property (readwrite, nonatomic) uint32_t deviceIdentifier;
@property (readwrite, nonatomic, copy) NSString *account;
@property (readwrite, nonatomic, strong) NSMutableArray *skippedKeys;
@property (readwrite, nonatomic, strong) NSMutableDictionary *trust;
@property (readwrite, nonatomic, strong) NSMutableDictionary *seenFingerprints;	//"jid deviceid" -> fingerprint
@property (readwrite, nonatomic, strong) NSDate *signedPreKeyCreated;

//Gerufen aus den Rueckrufen der Bibliothek, siehe unten
- (int)takeSkippedKey:(struct omemo0MessageKey *)wanted;
- (int)keepSkippedKey:(const struct omemo0MessageKey *)key;
@end

#pragma mark Finding the owner of a session again

/*
 * The library's callbacks for skipped keys are global and hand back only the session, so this
 * maps a session back to the store holding it. The pointers stay put because every session is
 * allocated on its own and freed only when its store goes away.
 */
static NSMapTable *ownerOfSession = nil;

static AIOMEMOStore *storeHolding(struct omemo0Session *session)
{
	return (AIOMEMOStore *)[ownerOfSession objectForKey:(__bridge id)(void *)session];
}

/*
 * These two must never be reached through a session with no owner, and the reason is worth
 * spelling out, because it cost an afternoon. A message sent to nil answers zero, and zero is
 * exactly what this callback uses to mean "found, and I have filled the key in". The library
 * would then decrypt with whatever happened to be on the stack, and the only sign of it is a
 * message that will not open. So the owner is registered before the library is ever entered,
 * and these still refuse rather than trust that.
 */
static int loadSkippedKey(struct omemo0Session *session, struct omemo0MessageKey *wanted)
{
	AIOMEMOStore *owner = storeHolding(session);
	if (!owner) return 1;		//Not a key we are holding, which is the ordinary answer

	return [owner takeSkippedKey:wanted];
}

static int keepSkippedKey(struct omemo0Session *session, const struct omemo0MessageKey *key, uint64_t stillToCome)
{
	AIOMEMOStore *owner = storeHolding(session);
	if (!owner) return OMEMO0_EUSER;

	return [owner keepSkippedKey:key];
}

static int randomBytes(void *bytes, size_t length)
{
	arc4random_buf(bytes, length);
	return 0;
}

@implementation AIOMEMOStore

+ (void)initialize
{
	if (self != [AIOMEMOStore class]) return;

	ownerOfSession = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality
										   valueOptions:NSPointerFunctionsWeakMemory];

	/* Without this the library has no source of randomness at all on this platform: its own
	 * fallback is written for Linux, and everywhere else it simply refuses. Every key we would
	 * ever generate depends on this line. */
	omemo0SetCallbacks(loadSkippedKey, keepSkippedKey, randomBytes);
}

#pragma mark Where it lives

static NSString *directoryInsteadOfTheUsual = nil;

+ (void)useDirectory:(NSString *)path
{
	directoryInsteadOfTheUsual = [path copy];
}

+ (NSString *)directory
{
	/* The wire half sets this from Adium's own account directory as it starts. The fallback is
	 * that same place as Adium lays it out by default, so that forgetting to set it puts the
	 * files where they belong rather than somewhere surprising. */
	NSString *path = directoryInsteadOfTheUsual;

	if (!path) {
		NSString *support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
																 NSUserDomainMask, YES) firstObject];
		path = [[support stringByAppendingPathComponent:@"Adium 2.0"]
				stringByAppendingPathComponent:OMEMO_DIRECTORY];
	}

	[[NSFileManager defaultManager] createDirectoryAtPath:path
							  withIntermediateDirectories:YES
											   attributes:@{NSFilePosixPermissions: @(0700)}
													error:NULL];
	return path;
}

+ (NSString *)pathForAccount:(NSString *)bareJID
{
	/* A JID may hold a slash or a colon in principle, and certainly holds an at sign, so the
	 * name is not usable as a file name until it has been made safe. */
	NSString *safe = [bareJID stringByReplacingOccurrencesOfString:@"/" withString:@"%2F"];
	safe = [safe stringByReplacingOccurrencesOfString:@":" withString:@"%3A"];

	return [[self directory] stringByAppendingPathComponent:[safe stringByAppendingPathExtension:@"omemo"]];
}

/*!
 * @brief The stores that are open, one per account
 *
 * There can only be one, because two would each hold their own copy of a ratchet and the
 * second one to write would undo the first. That is the kind of mistake that shows up much
 * later as a conversation that has stopped opening.
 */
+ (NSMutableDictionary *)openStores
{
	static NSMutableDictionary *open = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ open = [NSMutableDictionary dictionary]; });
	return open;
}

+ (instancetype)storeForAccount:(NSString *)bareJID
{
	NSMutableDictionary *open = [self openStores];

	@synchronized (open) {
		AIOMEMOStore *already = open[bareJID];
		if (already) return already;

		AIOMEMOStore *fresh = [[self alloc] initForAccount:bareJID];
		if (fresh) open[bareJID] = fresh;
		return fresh;
	}
}

+ (void)closeStoreForAccount:(NSString *)bareJID
{
	NSMutableDictionary *open = [self openStores];

	@synchronized (open) {
		[open removeObjectForKey:bareJID];
	}
}

+ (void)discardStoreForAccount:(NSString *)bareJID
{
	[self closeStoreForAccount:bareJID];
	[[NSFileManager defaultManager] removeItemAtPath:[self pathForAccount:bareJID] error:NULL];
}

#pragma mark Coming into being

- (instancetype)initForAccount:(NSString *)bareJID
{
	if (!(self = [super init])) return nil;

	self.account = bareJID;
	sessions = [NSMutableDictionary dictionary];
	self.skippedKeys = [NSMutableArray array];
	self.trust = [NSMutableDictionary dictionary];
	self.seenFingerprints = [NSMutableDictionary dictionary];

	store = calloc(1, sizeof(*store));
	if (!store) return nil;

	if (![self readFromDisk] && ![self beginANewIdentity])
		return nil;

	return self;
}

- (void)dealloc
{
	for (NSValue *held in [sessions allValues]) {
		struct omemo0Session *session = [held pointerValue];
		[ownerOfSession removeObjectForKey:(__bridge id)(void *)session];
		free(session);
	}
	free(store);
}

/*!
 * @brief Generate everything from nothing, for an account that has never used OMEMO
 */
- (BOOL)beginANewIdentity
{
	if (omemo0SetupStore(store) != 0)
		return NO;

	/* The device number is a name, not a secret, but it must not collide with another device
	 * of the same account and it must fit where the specification says it fits. */
	self.deviceIdentifier = arc4random_uniform(INT32_MAX - 1) + 1;
	self.signedPreKeyCreated = [NSDate date];

	return [self writeToDisk];
}

#pragma mark Reading and writing

- (BOOL)readFromDisk
{
	NSString *path = [[self class] pathForAccount:self.account];
	NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:path];
	if (!saved) return NO;

	NSData *storeBytes = saved[KEY_STORE];
	if (![storeBytes isKindOfClass:[NSData class]]) return NO;
	if (omemo0DeserializeStore([storeBytes bytes], [storeBytes length], store) != 0) return NO;

	self.deviceIdentifier = [saved[KEY_DEVICE] unsignedIntValue];
	if (!self.deviceIdentifier) return NO;

	self.signedPreKeyCreated = saved[KEY_SIGNED_MADE] ?: [NSDate date];
	self.trust = [saved[KEY_TRUST] mutableCopy] ?: [NSMutableDictionary dictionary];
	self.seenFingerprints = [saved[KEY_FINGERPRINTS] mutableCopy] ?: [NSMutableDictionary dictionary];
	self.skippedKeys = [saved[KEY_SKIPPED] mutableCopy] ?: [NSMutableArray array];

	[saved[KEY_SESSIONS] enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSData *bytes, BOOL *stop) {
		if (![bytes isKindOfClass:[NSData class]]) return;

		struct omemo0Session *session = calloc(1, sizeof(*session));
		if (!session) return;

		if (omemo0DeserializeSession([bytes bytes], [bytes length], session) == 0) {
			self->sessions[name] = [NSValue valueWithPointer:session];
			[ownerOfSession setObject:self forKey:(__bridge id)(void *)session];
		} else {
			//A session we cannot read is a session we no longer have; the next message rebuilds it
			free(session);
		}
	}];

	return YES;
}

- (BOOL)writeToDisk
{
	size_t needed = omemo0GetSerializedStoreSize(store);
	NSMutableData *storeBytes = [NSMutableData dataWithLength:needed];
	omemo0SerializeStore([storeBytes mutableBytes], store);

	NSMutableDictionary *keptSessions = [NSMutableDictionary dictionary];
	[sessions enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSValue *held, BOOL *stop) {
		struct omemo0Session *session = [held pointerValue];
		size_t size = omemo0GetSerializedSessionSize(session);
		NSMutableData *bytes = [NSMutableData dataWithLength:size];
		omemo0SerializeSession([bytes mutableBytes], session);
		keptSessions[name] = bytes;
	}];

	NSDictionary *whole = @{
		KEY_DEVICE:			@(self.deviceIdentifier),
		KEY_STORE:			storeBytes,
		KEY_SESSIONS:		keptSessions,
		KEY_SKIPPED:		self.skippedKeys,
		KEY_TRUST:			self.trust,
		KEY_FINGERPRINTS:	self.seenFingerprints,
		KEY_SIGNED_MADE:	self.signedPreKeyCreated ?: [NSDate date]
	};

	NSString *path = [[self class] pathForAccount:self.account];
	if (![whole writeToFile:path atomically:YES])
		return NO;

	/* This file holds private keys in the clear, exactly as the OTR key file next to it does.
	 * The least that owes the user is that nobody else on the machine can read it. */
	[[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0600)}
									 ofItemAtPath:path
											error:NULL];
	return YES;
}

#pragma mark Our own key material

- (NSData *)identityKey
{
	omemo0SerializedKey wire;
	omemo0SerializeKey(wire, store->identity.pub);
	return [NSData dataWithBytes:wire length:sizeof(wire)];
}

- (NSString *)fingerprint
{
	return [[self class] fingerprintOfIdentityKey:[self identityKey]];
}

/*!
 * @brief An identity key in the form people read out to each other
 *
 * The leading byte says only that this is a curve key and is the same for everybody, so it is
 * left off; what remains is grouped into eights because that is how every other client shows
 * it, and comparing two of these by eye is the entire point.
 */
+ (NSString *)fingerprintOfIdentityKey:(NSData *)identityKey
{
	if ([identityKey length] < 33) return nil;

	const uint8_t *bytes = [identityKey bytes];
	NSMutableString *readable = [NSMutableString string];

	for (int index = 1; index < 33; index++) {
		if (index > 1 && (index - 1) % 4 == 0)
			[readable appendString:@" "];
		[readable appendFormat:@"%02x", bytes[index]];
	}
	return readable;
}

- (uint32_t)signedPreKeyIdentifier	{ return store->cursignedprekey.id; }

- (NSData *)signedPreKey
{
	omemo0SerializedKey wire;
	omemo0SerializeKey(wire, store->cursignedprekey.kp.pub);
	return [NSData dataWithBytes:wire length:sizeof(wire)];
}

- (NSData *)signedPreKeySignature
{
	return [NSData dataWithBytes:store->cursignedprekey.sig length:sizeof(store->cursignedprekey.sig)];
}

- (NSDictionary<NSNumber *, NSData *> *)preKeys
{
	NSMutableDictionary *published = [NSMutableDictionary dictionary];

	for (int index = 0; index < OMEMO0_NUMPREKEYS; index++) {
		//A used key is zeroed rather than removed, and a zero identifier is how that shows
		if (!store->prekeys[index].id) continue;

		omemo0SerializedKey wire;
		omemo0SerializeKey(wire, store->prekeys[index].kp.pub);
		published[@(store->prekeys[index].id)] = [NSData dataWithBytes:wire length:sizeof(wire)];
	}
	return published;
}

- (void)rotateSignedPreKey
{
	if (omemo0RotateSignedPreKey(store) != 0) return;

	self.signedPreKeyCreated = [NSDate date];
	[self writeToDisk];
}

#pragma mark Sessions

- (NSString *)nameForJID:(NSString *)jid device:(uint32_t)device
{
	return [NSString stringWithFormat:@"%@ %u", [jid lowercaseString], device];
}

- (struct omemo0Session *)sessionWithJID:(NSString *)jid device:(uint32_t)device
{
	NSValue *held = sessions[[self nameForJID:jid device:device]];
	return held ? [held pointerValue] : NULL;
}

- (BOOL)hasSessionWithJID:(NSString *)jid device:(uint32_t)device
{
	return [self sessionWithJID:jid device:device] != NULL;
}

- (NSArray<NSNumber *> *)devicesWithSessionsForJID:(NSString *)jid
{
	NSString *prefix = [[jid lowercaseString] stringByAppendingString:@" "];
	NSMutableArray *found = [NSMutableArray array];

	for (NSString *name in [sessions allKeys]) {
		if (![name hasPrefix:prefix]) continue;
		[found addObject:@((uint32_t)[[name substringFromIndex:[prefix length]] longLongValue])];
	}
	return found;
}

/*!
 * @brief Take ownership of a session and make it findable from the library's callbacks
 */
- (void)holdSession:(struct omemo0Session *)session asJID:(NSString *)jid device:(uint32_t)device
{
	NSString *name = [self nameForJID:jid device:device];

	NSValue *previous = sessions[name];
	if (previous) {
		struct omemo0Session *old = [previous pointerValue];
		[ownerOfSession removeObjectForKey:(__bridge id)(void *)old];
		free(old);
	}

	sessions[name] = [NSValue valueWithPointer:session];
	[ownerOfSession setObject:self forKey:(__bridge id)(void *)session];

	//Remember what this device's identity looked like, so the user can be shown it later
	omemo0SerializedKey wire;
	omemo0SerializeKey(wire, session->remoteidentity);
	NSString *readable = [[self class] fingerprintOfIdentityKey:[NSData dataWithBytes:wire length:sizeof(wire)]];
	if (readable) self.seenFingerprints[name] = readable;
}

- (BOOL)startSessionWithJID:(NSString *)jid
					 device:(uint32_t)device
				identityKey:(NSData *)identityKey
			   signedPreKey:(NSData *)signedPreKey
		 signedPreKeyItself:(uint32_t)signedPreKeyIdentifier
				  signature:(NSData *)signature
					 preKey:(NSData *)preKey
			   preKeyItself:(uint32_t)preKeyIdentifier
{
	/* Everything here came off the wire, so nothing about its size may be assumed. A bundle of
	 * the wrong shape is a bundle we decline, not one we pad out to fit. */
	if ([identityKey length] != sizeof(omemo0SerializedKey) ||
		[signedPreKey length] != sizeof(omemo0SerializedKey) ||
		[preKey length] != sizeof(omemo0SerializedKey) ||
		[signature length] != sizeof(omemo0CurveSignature))
		return NO;

	struct omemo0Session *session = calloc(1, sizeof(*session));
	if (!session) return NO;

	/* The library checks the signature against the identity that claims to have made it, which
	 * is the one thing standing between us and a server handing out a bundle of its own. */
	int result = omemo0InitiateSession(session, store,
									   [signature bytes], [signedPreKey bytes], [identityKey bytes],
									   [preKey bytes], signedPreKeyIdentifier, preKeyIdentifier);
	if (result != 0) {
		free(session);
		return NO;
	}

	[self holdSession:session asJID:jid device:device];
	return [self writeToDisk];
}

#pragma mark Wrapping and unwrapping the message key

- (NSData *)wrap:(NSData *)key withSession:(struct omemo0Session *)session wasPreKey:(BOOL *)wasPreKey
{
	struct omemo0KeyMessage wrapped;
	memset(&wrapped, 0, sizeof(wrapped));

	if (omemo0EncryptKey(session, &wrapped, [key bytes], [key length]) != 0)
		return nil;

	if (wasPreKey) *wasPreKey = wrapped.isprekey;
	return [NSData dataWithBytes:wrapped.p length:wrapped.n];
}

- (NSData *)encryptKey:(NSData *)key
				 forJID:(NSString *)jid
				 device:(uint32_t)device
			  wasPreKey:(BOOL *)wasPreKey
{
	struct omemo0Session *session = [self sessionWithJID:jid device:device];
	if (!session) return nil;

	NSData *wrapped = [self wrap:key withSession:session wasPreKey:wasPreKey];

	//The ratchet moved whether or not that worked, so the new position has to reach the disk
	[self writeToDisk];
	return wrapped;
}

- (NSData *)decryptKey:(NSData *)wrapped
				fromJID:(NSString *)jid
				 device:(uint32_t)device
				isPreKey:(BOOL)isPreKey
{
	struct omemo0Session *session = [self sessionWithJID:jid device:device];
	BOOL isNew = NO;

	/* A prekey message may be the first thing we ever hear from a device. That is what a prekey
	 * is for, so it builds its own session rather than being turned away for lacking one. */
	if (!session) {
		if (!isPreKey) return nil;

		session = calloc(1, sizeof(*session));
		if (!session) return nil;
		isNew = YES;

		/* Registered now rather than after it works, because the library asks us about skipped
		 * keys while it is decrypting, and it must find us when it does. */
		[ownerOfSession setObject:self forKey:(__bridge id)(void *)session];
	}

	uint8_t key[OMEMO0_INTERNAL_PAYLOAD_MAXPADDEDSIZE];
	size_t keyLength = sizeof(key);

	int result = omemo0DecryptKey(session, store, key, &keyLength,
								  isPreKey, [wrapped bytes], [wrapped length]);
	if (result != 0) {
		if (isNew) {
			[ownerOfSession removeObjectForKey:(__bridge id)(void *)session];
			free(session);
		} else {
			//A session that already existed has still moved, and that has to be kept
			[self writeToDisk];
		}
		return nil;
	}

	if (isNew) [self holdSession:session asJID:jid device:device];

	/* A one time key that has been used is no longer one, so it goes now. The bundle we
	 * published still offers it, which is why the caller is told to publish again. */
	if (session->usedpk_id) [self forgetPreKey:session->usedpk_id];

	[self writeToDisk];
	return [NSData dataWithBytes:key length:keyLength];
}

- (NSData *)keyForHeartbeatWithJID:(NSString *)jid
							device:(uint32_t)device
						 wasPreKey:(BOOL *)wasPreKey
{
	struct omemo0Session *session = [self sessionWithJID:jid device:device];
	if (!session) return nil;

	struct omemo0KeyMessage beat;
	memset(&beat, 0, sizeof(beat));

	if (omemo0Heartbeat(session, store, &beat) != 0 || beat.n == 0)
		return nil;

	if (wasPreKey) *wasPreKey = beat.isprekey;
	[self writeToDisk];
	return [NSData dataWithBytes:beat.p length:beat.n];
}

/*!
 * @brief Drop a one time key that has served its purpose, and make a replacement
 */
- (void)forgetPreKey:(uint32_t)identifier
{
	for (int index = 0; index < OMEMO0_NUMPREKEYS; index++) {
		if (store->prekeys[index].id != identifier) continue;

		memset(&store->prekeys[index], 0, sizeof(store->prekeys[index]));
		break;
	}

	omemo0RefillPreKeys(store);
	_bundleNeedsPublishing = YES;
}

#pragma mark Keys of messages that overtook others

- (int)keepSkippedKey:(const struct omemo0MessageKey *)key
{
	if ([self.skippedKeys count] >= SKIPPED_LIMIT)
		return OMEMO0_EUSER;

	[self.skippedKeys addObject:@{
		SKIPPED_RATCHET:	[NSData dataWithBytes:key->dh length:sizeof(key->dh)],
		SKIPPED_NUMBER:		@(key->nr),
		SKIPPED_KEY:		[NSData dataWithBytes:key->mk length:sizeof(key->mk)]
	}];
	return 0;
}

- (int)takeSkippedKey:(struct omemo0MessageKey *)wanted
{
	NSData *ratchet = [NSData dataWithBytes:wanted->dh length:sizeof(wanted->dh)];

	for (NSUInteger index = 0; index < [self.skippedKeys count]; index++) {
		NSDictionary *kept = self.skippedKeys[index];

		if ([kept[SKIPPED_NUMBER] unsignedIntValue] != wanted->nr) continue;
		if (![kept[SKIPPED_RATCHET] isEqualToData:ratchet]) continue;

		NSData *material = kept[SKIPPED_KEY];
		if ([material length] != sizeof(wanted->mk)) return OMEMO0_EUSER;
		memcpy(wanted->mk, [material bytes], sizeof(wanted->mk));

		//A skipped key is good exactly once, same as any other
		[self.skippedKeys removeObjectAtIndex:index];
		return 0;
	}

	//Not one we are holding, which is the ordinary case and not an error
	return 1;
}

#pragma mark What the user has decided

- (NSString *)fingerprintForJID:(NSString *)jid device:(uint32_t)device
{
	return self.seenFingerprints[[self nameForJID:jid device:device]];
}

- (AIOMEMOTrust)trustForFingerprint:(NSString *)fingerprint
{
	NSNumber *decided = self.trust[fingerprint];
	return decided ? (AIOMEMOTrust)[decided integerValue] : AIOMEMOTrustUndecided;
}

- (void)setTrust:(AIOMEMOTrust)trust forFingerprint:(NSString *)fingerprint
{
	if (!fingerprint) return;

	self.trust[fingerprint] = @(trust);
	[self writeToDisk];
}

- (NSDictionary<NSString *, NSNumber *> *)fingerprintsForJID:(NSString *)jid
{
	NSString *prefix = [[jid lowercaseString] stringByAppendingString:@" "];
	NSMutableDictionary *found = [NSMutableDictionary dictionary];

	[self.seenFingerprints enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *print, BOOL *stop) {
		if (![name hasPrefix:prefix]) return;
		found[print] = @([self trustForFingerprint:print]);
	}];
	return found;
}

@end
