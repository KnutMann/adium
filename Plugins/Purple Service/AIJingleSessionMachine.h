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

@class AIJingleSessionMachine;

typedef NS_ENUM(NSInteger, AIJingleCallState) {
	AIJingleCallStateIdle = 0,
	AIJingleCallStatePendingOutgoing,	//session-initiate sent, waiting for the accept
	AIJingleCallStatePendingIncoming,	//session-initiate received, waiting for our answer
	AIJingleCallStateActive,
	AIJingleCallStateEnded,
};

/*!
 * @brief What the machine asks of its surroundings
 *
 * The machine speaks only strings: jingle elements outward, SDP and candidate
 * lines toward whatever owns the media. It never touches the network or WebRTC
 * itself, which is what makes it testable with two of them in one process.
 */
@protocol AIJingleSessionMachineDelegate <NSObject>
- (void)machine:(AIJingleSessionMachine *)machine sendJingleElement:(NSString *)jingleXML;
- (void)machine:(AIJingleSessionMachine *)machine applyRemoteSDP:(NSString *)sdp isOffer:(BOOL)isOffer;
- (void)machine:(AIJingleSessionMachine *)machine addRemoteCandidateLine:(NSString *)line mid:(NSString *)mid;
- (void)machine:(AIJingleSessionMachine *)machine endedWithReason:(NSString *)reason locally:(BOOL)locally;
@end

/*!
 * @class AIJingleSessionMachine
 * @brief One call's Jingle conversation, from initiate to terminate
 *
 * Holds the state a single session passes through and the bookkeeping the wire
 * demands: the sid, the local ICE credentials per content (a trickled candidate
 * travels inside a transport that must name them), and a queue for candidates
 * the peer sends before its accept arrives, the way Conversations does; they
 * are handed over only once the remote description is in place.
 */
@interface AIJingleSessionMachine : NSObject

@property (nonatomic, weak) id<AIJingleSessionMachineDelegate> delegate;
@property (nonatomic, readonly) AIJingleCallState state;
@property (nonatomic, readonly, copy) NSString *sid;
@property (nonatomic, readonly, copy) NSString *peerJid;
@property (nonatomic, readonly) BOOL isInitiator;

/*! @brief A machine for a call we start; sid may be nil to mint one */
- (id)initAsInitiatorFrom:(NSString *)localJid to:(NSString *)peerJid sid:(NSString *)sid;

/*! @brief A machine for a call that reached us as a session-initiate */
- (id)initAsResponderFrom:(NSString *)localJid to:(NSString *)peerJid;

//Initiator: the local offer is ready; sends session-initiate
- (void)startWithLocalOfferSDP:(NSString *)offerSDP;

//Responder: feed the received session-initiate, then answer when the media side has one
- (void)receivedInitiateElement:(NSString *)jingleXML;
- (void)acceptWithLocalAnswerSDP:(NSString *)answerSDP;

//Both sides: everything else the peer says about this session
- (void)handleRemoteJingleElement:(NSString *)jingleXML;

//Both sides: a local ICE candidate to trickle out
- (void)addLocalCandidateLine:(NSString *)line mid:(NSString *)mid;

//Both sides: hang up (reason per XEP-0166, "success" for a normal end)
- (void)hangUpWithReason:(NSString *)reason;

/*!
 * @brief End without a word on the wire
 *
 * For endings the wire already knows about in another language: a rejected or
 * retracted proposal (XEP-0353) ends the call before a session ever existed,
 * so a session-terminate would name a session the peer never heard of.
 */
- (void)abandonWithReason:(NSString *)reason locally:(BOOL)locally;

@end
