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

@class AIChat, AIAccount;

/*!
 * @brief What the interface needs to know and say about OMEMO
 *
 * Everything below the encryption is expressed in libpurple's terms, which the interface has no
 * business knowing about. This is the one place where the two meet, so that a menu can be
 * written against chats and contacts as everything else in the interface is.
 */
@interface AIOMEMOController : NSObject

/*! @brief Can this conversation use OMEMO at all? True for a one to one XMPP chat */
+ (BOOL)isPossibleInChat:(AIChat *)chat;

/*! @brief Are we encrypting what we send here? */
+ (BOOL)isEncryptingChat:(AIChat *)chat;

/*!
 * @brief Do we hold the keys to encrypt here right now?
 *
 * Different from meaning to: a conversation can be switched on and not yet able, while the
 * other side's keys are being fetched, and the interface should be able to say which it is.
 */
+ (BOOL)isReadyInChat:(AIChat *)chat;

/*! @brief Start or stop encrypting to the person in this conversation */
+ (void)setEncrypting:(BOOL)encrypting inChat:(AIChat *)chat;

/*! @brief This installation's own fingerprint, as the user would read it out */
+ (NSString *)ownFingerprintForAccount:(AIAccount *)account;

/*!
 * @brief Every device of the other party that we have met, and what was decided about each
 *
 * Keyed by fingerprint, because that is what the user compares; the value is an
 * AIOMEMOTrust as a number.
 */
+ (NSDictionary<NSString *, NSNumber *> *)fingerprintsInChat:(AIChat *)chat;

/*! @brief Accept or turn down one device of the other party */
+ (void)setAccepted:(BOOL)accepted forFingerprint:(NSString *)fingerprint inChat:(AIChat *)chat;

#pragma mark Everything one account knows, for the settings

/*! @brief Does this account speak OMEMO at all? */
+ (BOOL)isPossibleForAccount:(AIAccount *)account;

/*!
 * @brief Every device of every contact this account has ever met
 *
 * One entry per device, with "jid", "device", "fingerprint" and "trust" (an AIOMEMOTrust as a
 * number). A conversation shows what one person has; the settings show what has accumulated.
 */
+ (NSArray<NSDictionary *> *)devicesKnownToAccount:(AIAccount *)account;

/*! @brief Decide about one device, named by its fingerprint rather than by a conversation */
+ (void)setTrust:(NSInteger)trust forFingerprint:(NSString *)fingerprint onAccount:(AIAccount *)account;

@end
