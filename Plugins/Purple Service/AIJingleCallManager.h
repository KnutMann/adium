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

#import "adiumPurpleJingle.h"
#import "AIJingleCallController.h"

/*!
 * @class AIJingleCallManager
 * @brief The house's calls, kept apart by session id and wired to their accounts
 *
 * Owns the stream side of every call: it registers as the Jingle stanza handler,
 * routes each element to the controller whose session it names, and addresses
 * outgoing elements to the peer on the right account. A session-initiate for an
 * unknown session starts a call only while the hidden default
 * AIJingleAutoAcceptCalls says so; the ringing interface is a later chapter, and
 * until it exists, unknown calls stay untouched and are answered
 * service-unavailable by the protocol, as before.
 */
@interface AIJingleCallManager : NSObject <AdiumJingleStanzaHandler, AIJingleCallControllerDelegate>

+ (AIJingleCallManager *)sharedManager;

/*! @brief Register as the stream's Jingle handler; called once at purple setup */
+ (void)install;

/*! @brief Start a call to a full JID; audio for now, the camera arrives with the interface */
- (AIJingleCallController *)startCallToJid:(NSString *)peerFullJid onAccount:(CBPurpleAccount *)account;

@end
