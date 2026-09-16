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

#import <Foundation/Foundation.h>

/*!
 * @brief How far we trust the device behind an identity key
 *
 * OMEMO leaves the decision to the user, and the only honest starting point is that we do not
 * know yet. A device stays undecided until somebody says otherwise, which is what lets the
 * interface ask.
 */
typedef NS_ENUM(NSInteger, AIOMEMOTrust) {
	AIOMEMOTrustUndecided = 0,
	AIOMEMOTrustAccepted,
	AIOMEMOTrustRejected
};

/*!
 * @brief Everything one account must remember about OMEMO between launches
 *
 * This is the durable half of OMEMO: our own identity, the key material other people fetch in
 * order to write to us, one ratchet per device we talk to, the keys of messages that arrived
 * out of order, and what the user has decided about each device.
 *
 * The class owns the cryptography library's state and never hands it out, so that saving
 * cannot be forgotten by a caller: every method that advances a ratchet writes the result
 * before it returns.
 */
@interface AIOMEMOStore : NSObject

/*!
 * @brief Say where the key material lives
 *
 * Set from Adium's account directory as the connection comes up, and set elsewhere by the
 * tests, so that a check can never reach the key material of a real account. It has to be set
 * before the first store is asked for.
 */
+ (void)useDirectory:(NSString *)path;

/*!
 * @brief Has this account ever used OMEMO?
 *
 * Asked where the answer is wanted without the asking itself creating one: storeForAccount:
 * makes an identity and a hundred keys where it finds none, which is right when a conversation
 * needs them and wrong when somebody merely opens a settings window.
 */
+ (BOOL)haveStoreForAccount:(NSString *)bareJID;

/*!
 * @brief The store for one account, loaded from disk or freshly generated
 *
 * @param bareJID The account's own address, without a resource
 */
+ (instancetype)storeForAccount:(NSString *)bareJID;

/*!
 * @brief Let go of an account's store in memory, leaving the file alone
 *
 * What a sign off does, and what the next call to storeForAccount: undoes by reading the file
 * again. Holding two stores for one account would mean two copies of every ratchet, where the
 * second one saved quietly undoes the first.
 */
+ (void)closeStoreForAccount:(NSString *)bareJID;

/*!
 * @brief Forget everything belonging to an account, on disk as well
 */
+ (void)discardStoreForAccount:(NSString *)bareJID;

/*! @brief The account this store belongs to, without a resource */
@property (readonly, nonatomic, copy) NSString *account;

/*! @brief This installation's device number, as it appears in the device list */
@property (readonly, nonatomic) uint32_t deviceIdentifier;

/*! @brief Our public identity key in the form that goes on the wire, 33 bytes */
@property (readonly, nonatomic) NSData *identityKey;

/*! @brief Our own identity key as the user sees it, eight groups of eight hex digits */
@property (readonly, nonatomic) NSString *fingerprint;

#pragma mark The bundle other people fetch

@property (readonly, nonatomic) uint32_t signedPreKeyIdentifier;
@property (readonly, nonatomic) NSData *signedPreKey;			//33 bytes
@property (readonly, nonatomic) NSData *signedPreKeySignature;	//64 bytes

/*! @brief The one time keys, each an NSNumber identifier mapped to 33 bytes */
@property (readonly, nonatomic) NSDictionary<NSNumber *, NSData *> *preKeys;

/*!
 * @brief Put a fresh signed key in place, keeping the previous one valid for one more turn
 *
 * Meant to be called when the current one has been in use for long enough, which the caller
 * decides, because only the caller knows when we last published a bundle.
 */
- (void)rotateSignedPreKey;

/*! @brief How long the current signed key has been in use */
@property (readonly, nonatomic) NSDate *signedPreKeyCreated;

/*!
 * @brief Set when what we published no longer matches what we hold
 *
 * A one time key is spent the moment somebody uses it, and the bundle on the server still
 * offers it until we say otherwise. The wire half clears this once it has published again.
 */
@property (readwrite, nonatomic) BOOL bundleNeedsPublishing;

#pragma mark Sessions

/*! @brief Is there already a ratchet running with this device? */
- (BOOL)hasSessionWithJID:(NSString *)jid device:(uint32_t)device;

/*!
 * @brief Start a ratchet from a bundle somebody published
 *
 * @return NO if the bundle does not hold together, which includes a signature that does not
 *         match the identity that claims to have made it
 */
- (BOOL)startSessionWithJID:(NSString *)jid
					 device:(uint32_t)device
				identityKey:(NSData *)identityKey
			   signedPreKey:(NSData *)signedPreKey
		 signedPreKeyItself:(uint32_t)signedPreKeyIdentifier
				  signature:(NSData *)signature
					 preKey:(NSData *)preKey
			   preKeyItself:(uint32_t)preKeyIdentifier;

/*!
 * @brief Wrap the message key for one device
 *
 * @param wasPreKey Set when the result must be marked as carrying a prekey, which the
 *                  recipient needs in order to know how to unwrap it
 * @return nil if there is no session with that device
 */
- (NSData *)encryptKey:(NSData *)key
				 forJID:(NSString *)jid
				 device:(uint32_t)device
			  wasPreKey:(BOOL *)wasPreKey;

/*!
 * @brief Unwrap the message key one device sent us
 *
 * A prekey message may arrive from a device we have never met, and starts a session by itself;
 * that is the whole point of a prekey, and the reason this does not require a session first.
 *
 * @return nil if it cannot be unwrapped, which is not necessarily an attack: an old message
 *         from a ratchet we have since discarded looks exactly the same.
 */
- (NSData *)decryptKey:(NSData *)wrapped
				fromJID:(NSString *)jid
				 device:(uint32_t)device
				isPreKey:(BOOL)isPreKey;

/*!
 * @brief The key material for an empty message, if the ratchet has run far enough to want one
 *
 * OMEMO ratchets only move forward when both sides send. After a long one sided conversation
 * the sender is far ahead, and the answer is a message with no body whose only job is to let
 * the ratchet step. This returns that message's wrapped key, or nil when none is needed.
 */
- (NSData *)keyForHeartbeatWithJID:(NSString *)jid
							device:(uint32_t)device
						 wasPreKey:(BOOL *)wasPreKey;

/*! @brief The devices we hold a session with for one contact */
- (NSArray<NSNumber *> *)devicesWithSessionsForJID:(NSString *)jid;

#pragma mark What the user has decided

/*! @brief The identity key of a device we have met, as the user sees it */
- (NSString *)fingerprintForJID:(NSString *)jid device:(uint32_t)device;

- (AIOMEMOTrust)trustForFingerprint:(NSString *)fingerprint;
- (void)setTrust:(AIOMEMOTrust)trust forFingerprint:(NSString *)fingerprint;

/*! @brief Every fingerprint we have seen for a contact, mapped to what was decided about it */
- (NSDictionary<NSString *, NSNumber *> *)fingerprintsForJID:(NSString *)jid;

/*!
 * @brief Every device of every contact this account has ever met
 *
 * One entry per device, each with the keys below. Meant for the settings, where the question is
 * not what one conversation looks like but what this account has accumulated over time.
 *
 * "jid"          who it belongs to
 * "device"       which of their devices, as the number it announces itself by
 * "fingerprint"  as the user reads it out
 * "trust"        an AIOMEMOTrust
 */
- (NSArray<NSDictionary *> *)everyDeviceSeen;

@end
