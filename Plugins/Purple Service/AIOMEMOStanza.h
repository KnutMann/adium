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
#import <libpurple/libpurple.h>

@class AIOMEMOStore;

/*
 * Turning a message stanza into its encrypted form and back.
 *
 * Kept apart from everything else so that it can be checked on its own against the real
 * xmlnode, because rearranging XML is where a format mistake hides: it compiles, it runs, it
 * produces something that looks like a stanza, and the other client silently shows nothing.
 */

#define AIOMEMO_NAMESPACE	"eu.siacs.conversations.axolotl"

/*!
 * @brief One base64 value out of an element, or nil if it is not one
 *
 * Shared because a bundle and a message are read the same way, and two copies of that would
 * drift apart on the day one of them learned to tolerate something the other does not.
 */
NSData *AIOMEMOBase64In(xmlnode *element);

/*!
 * @brief One attribute read as a device or key number, or zero if it is not a sensible one
 */
uint32_t AIOMEMONumberIn(xmlnode *element, const char *attribute);

/*!
 * @brief Replace a message's readable parts with their encrypted form, in place
 *
 * Everything in the stanza that is not on a short list of harmless elements is taken out. The
 * list says what may stay rather than what must go, so an element nobody thought about is
 * dropped rather than sent in the open.
 *
 * @param devicesByJID Who to write to, including this account's own other devices
 * @return NO when it could not be encrypted, in which case the stanza is untouched and the
 *         caller must not send it
 */
BOOL AIOMEMOSealStanza(xmlnode *stanza, AIOMEMOStore *store,
					   NSDictionary<NSString *, NSArray<NSNumber *> *> *devicesByJID);

/*! @brief What became of an encrypted message we were handed */
typedef NS_ENUM(NSInteger, AIOMEMOOpened) {
	/*! It is now an ordinary message and should carry on downstream */
	AIOMEMOOpenedReadable,

	/*! There was nothing in it to show, and that is correct: a message with no payload exists
	 *  only to let the ratchet step, or was addressed to somebody else's device. Drop it. */
	AIOMEMOOpenedNothingToShow,

	/*! It could not be opened. The stanza is untouched, and passing it on is better than
	 *  dropping it: the sender's own fallback line then appears, so the person at least learns
	 *  that something arrived and could not be read. Silence here is indistinguishable from a
	 *  message that was never sent. */
	AIOMEMOOpenedCouldNot
};

/*!
 * @brief Turn an encrypted message back into the message it was, in place
 *
 * Rewriting the stanza rather than handling it separately means everything downstream sees an
 * ordinary message and needs to know nothing about any of this.
 *
 * @param fromBareJID Who sent it, without a resource
 */
AIOMEMOOpened AIOMEMOOpenStanza(xmlnode *stanza, AIOMEMOStore *store, NSString *fromBareJID);
