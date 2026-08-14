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

#import <Adium/AIService.h>

/*!
 * @class AIPurpleGenericService
 * @brief A service for a libpurple protocol that has no class of its own
 *
 * Every protocol here used to need two hand written classes, and almost all of both was transcription:
 * the protocol already says whether it takes a password, whether it has group chats, and what options
 * it wants, and none of that was ever read. This asks the protocol, and takes the rest from a
 * descriptor in AIPurpleServiceDescriptors.plist.
 *
 * The descriptor exists because two things cannot be derived. serviceCodeUniqueID is written into
 * every stored account and into the encryption key store, so it has to be decided once and then never
 * move, which is the opposite of a value computed from whatever the plugin happens to call itself
 * today. And icons have no fallback: AIServiceIcons returns nil when it finds nothing, so a service
 * has to bring its own.
 *
 * A protocol with real quirks can still have an account subclass. The point is that it needs one only
 * for the quirks.
 */
@interface AIPurpleGenericService : AIService {
	NSString		*prplID;
	char			*prplIDCString;
	NSDictionary	*descriptor;
}

/*!
 * @brief Register a service for every descriptor whose protocol is loaded
 *
 * Skips any protocol already claimed by a hand written service, so a descriptor added for a protocol
 * that later gets a class of its own does not produce two services for one protocol.
 *
 * @param claimedPrplIDs The protocol ids the hand written services answer for
 */
+ (void)registerServicesForLoadedProtocolsExcluding:(NSSet *)claimedPrplIDs;

/*!
 * @brief The protocol id, as libpurple wants it
 *
 * Kept as a C string for the lifetime of the service, because that is what an account has to hand
 * back from protocolPlugin and it may not be a string that has gone away by the time it is read.
 */
- (const char *)prplIDCString;

/*!
 * @brief One entry from the descriptor, or nil
 */
- (id)descriptorValueForKey:(NSString *)key;

@end
