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

@class AIOMEMOStore;

/*! @brief One wrapped copy of the message key, for one device */
@interface AIOMEMOKeyForDevice : NSObject
@property (readonly, nonatomic) uint32_t device;
@property (readonly, nonatomic) BOOL startsASession;	//the recipient must unwrap it differently
@property (readonly, nonatomic) NSData *wrapped;
@end

/*!
 * @brief An OMEMO message taken apart into the pieces that go into a stanza, and back
 *
 * The text is encrypted once, with a key nobody has yet, and that key is then wrapped
 * separately for every device that is meant to read it, including our own other devices. The
 * pieces here are exactly the ones the stanza carries, which keeps the arranging of XML in the
 * one place that has to talk to libpurple and leaves everything else able to be checked on its
 * own.
 */
@interface AIOMEMOMessage : NSObject

/*! @brief Our device, which the recipient needs in order to know whose ratchet to use */
@property (readonly, nonatomic) uint32_t sender;

/*! @brief The number used once for this message's own encryption */
@property (readonly, nonatomic) NSData *initialisationVector;

/*! @brief The encrypted text */
@property (readonly, nonatomic) NSData *payload;

/*! @brief The message key, wrapped once per device */
@property (readonly, nonatomic) NSArray<AIOMEMOKeyForDevice *> *keys;

/*!
 * @brief Encrypt a piece of text for every device that should be able to read it
 *
 * @param devicesByJID Whose devices to write to. Our own account belongs in here as well, or
 *        our other devices will show the conversation with our own side missing.
 * @return nil when not one device could be written to, which is the only case where sending
 *         would be worse than failing: a message nobody can read, that still looks sent.
 */
+ (instancetype)encrypting:(NSString *)text
				 withStore:(AIOMEMOStore *)store
				forDevices:(NSDictionary<NSString *, NSArray<NSNumber *> *> *)devicesByJID;

/*!
 * @brief Read back a message somebody sent us
 *
 * @param keys Every wrapped key in the stanza; the one addressed to us is picked out here
 *             rather than by the caller, because which device we are is this side's business.
 * @return nil if there is nothing for us in it, or if it will not open. Neither is
 *         necessarily an attack: a message to somebody else's device looks the same, and so
 *         does one from a ratchet we have since discarded.
 */
+ (NSString *)textFromPayload:(NSData *)payload
		 initialisationVector:(NSData *)vector
						 keys:(NSArray<AIOMEMOKeyForDevice *> *)keys
					 sentFrom:(NSString *)bareJID
					   device:(uint32_t)device
					withStore:(AIOMEMOStore *)store;

/*! @brief One wrapped key, as read out of a stanza */
+ (AIOMEMOKeyForDevice *)keyForDevice:(uint32_t)device
					   startsASession:(BOOL)startsASession
							  wrapped:(NSData *)wrapped;

@end
