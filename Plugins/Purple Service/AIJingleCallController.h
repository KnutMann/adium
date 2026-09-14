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
#import "AIJingleSessionMachine.h"

@class AIJingleCallController, RTCPeerConnection, RTCVideoTrack;

/*!
 * @brief What the controller reports upward, to a manager or a test
 */
@protocol AIJingleCallControllerDelegate <NSObject>
- (void)callController:(AIJingleCallController *)controller sendJingleElement:(NSString *)jingleXML;
- (void)callControllerConnected:(AIJingleCallController *)controller;
- (void)callController:(AIJingleCallController *)controller endedWithReason:(NSString *)reason locally:(BOOL)locally;
@optional
/*! @brief The peer's video is decodable; hand the track to whoever wants to draw it */
- (void)callController:(AIJingleCallController *)controller hasRemoteVideoTrack:(RTCVideoTrack *)track;
@end

/*!
 * @class AIJingleCallController
 * @brief One call, whole: the session machine on one side, the RTCPeerConnection on the other
 *
 * The controller owns both halves and wires them: SDP the connection produces goes
 * into the machine and out as Jingle, Jingle the machine decodes goes back in as
 * SDP and candidates. Foundation and WebRTC only, no Adium anywhere, so a test can
 * run two of them against each other in one process; the purple side lives in the
 * call manager above it. Everything happens on the main queue; WebRTC's callbacks
 * are bounced there.
 */
@interface AIJingleCallController : NSObject <AIJingleSessionMachineDelegate>

@property (nonatomic, weak) id<AIJingleCallControllerDelegate> delegate;
@property (nonatomic, readonly) AIJingleSessionMachine *machine;
@property (nonatomic, readonly) RTCPeerConnection *peerConnection;

/*! @brief The peer's full JID, for the manager to address the stanzas */
@property (nonatomic, copy) NSString *peerFullJid;

/*! @brief Send and expect a microphone track (the real call shape) */
@property (nonatomic) BOOL wantsAudio;

/*! @brief Send the camera too; asked of macOS the first time it happens */
@property (nonatomic) BOOL wantsVideo;

/*! @brief Our own camera's track, for a preview view; nil without wantsVideo */
@property (nonatomic, readonly) RTCVideoTrack *localVideoTrack;

/*! @brief Send fabricated video frames instead of touching any device; for tests */
@property (nonatomic) BOOL usesSyntheticVideo;

/*!
 * @brief STUN and TURN servers to try, one dictionary each: urls, username, credential
 *
 * What XEP-0215 answered for the account; empty means host candidates only,
 * which is all two machines on one network need.
 */
@property (nonatomic, copy) NSArray<NSDictionary *> *iceServerDictionaries;

- (id)initAsInitiatorFrom:(NSString *)localJid to:(NSString *)peerJid;
- (id)initAsResponderFrom:(NSString *)localJid to:(NSString *)peerJid;

/*! @brief Initiator only: build the connection, offer, and send session-initiate */
- (void)start;

/*! @brief Every Jingle element of this session, the initiate included */
- (void)handleRemoteJingleElement:(NSString *)jingleXML;

- (void)hangUpWithReason:(NSString *)reason;

@end
