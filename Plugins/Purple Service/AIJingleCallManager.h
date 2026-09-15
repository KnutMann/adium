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
@class AIJingleCallManager, AIListContact, RTCVideoTrack;

/*!
 * @brief What the interface layer shows for the manager: ringing, windows, endings
 */
@protocol AIJingleCallManagerUI <NSObject>
- (void)manager:(AIJingleCallManager *)manager promptForIncomingCallWithSid:(NSString *)sid
		   from:(NSString *)fromJid onAccount:(CBPurpleAccount *)account offersVideo:(BOOL)offersVideo;
- (void)manager:(AIJingleCallManager *)manager incomingCallWithdrawn:(NSString *)sid;
- (void)manager:(AIJingleCallManager *)manager callBegan:(AIJingleCallController *)controller
	  onAccount:(CBPurpleAccount *)account;
- (void)manager:(AIJingleCallManager *)manager callIsRinging:(AIJingleCallController *)controller;
- (void)manager:(AIJingleCallManager *)manager callConnected:(AIJingleCallController *)controller;
- (void)manager:(AIJingleCallManager *)manager call:(AIJingleCallController *)controller
	endedWithReason:(NSString *)reason locally:(BOOL)locally;
- (void)manager:(AIJingleCallManager *)manager call:(AIJingleCallController *)controller
	hasRemoteVideoTrack:(RTCVideoTrack *)track;
@end

@interface AIJingleCallManager : NSObject <AdiumJingleStanzaHandler, AIJingleCallControllerDelegate>

@property (nonatomic, weak) id<AIJingleCallManagerUI> uiDelegate;

+ (AIJingleCallManager *)sharedManager;

/*! @brief Register as the stream's Jingle handler; called once at purple setup */
+ (void)install;

/*! @brief Start a call to a full JID */
- (AIJingleCallController *)startCallToJid:(NSString *)peerFullJid
								 onAccount:(CBPurpleAccount *)account
								 withVideo:(BOOL)withVideo;

/*! @brief The full JID of a contact's best resource, or nil while nobody is there */
- (NSString *)fullJidForContact:(AIListContact *)contact;

/*! @brief Answer a ringing call the interface asked about */
- (AIJingleCallController *)acceptIncomingCallWithSid:(NSString *)sid withVideo:(BOOL)withVideo;

/*! @brief Turn a ringing call away */
- (void)declineIncomingCallWithSid:(NSString *)sid;

@end
