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
 * @header AIJingleEngine
 * @brief The two languages of a call, translated: WebRTC's SDP and XMPP's Jingle
 *
 * A call has one shape and two spellings. WebRTC speaks SDP; the peers on the wire
 * speak Jingle (XEP-0167 RTP sessions, XEP-0176 ICE-UDP, XEP-0320 DTLS-SRTP,
 * XEP-0338 grouping, XEP-0339 source-specific media, XEP-0294 header extensions).
 * This translates between them through one neutral model, in both directions.
 *
 * Foundation only, deliberately: stanzas come in and go out as strings, so every
 * translation is testable without Adium or libpurple around it; see
 * Testing/webrtc/jingle-roundtrip.m. The shim that binds this to the jabber
 * stream hands xmlnode stanzas over as text.
 */

/*! @brief One rtpmap entry with its fmtp parameters and rtcp-fb lines */
@interface AIJinglePayloadType : NSObject
@property (nonatomic) NSInteger payloadId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) NSInteger clockrate;
@property (nonatomic) NSInteger channels;			//0 when the rtpmap named none
@property (nonatomic, strong) NSMutableArray<NSArray<NSString *> *> *parameters;	//[name, value]; name may be empty (red's "111/111")
@property (nonatomic, strong) NSMutableArray<NSArray<NSString *> *> *feedback;		//[type, subtype]; subtype may be empty
@end

/*! @brief One a=extmap / rtp-hdrext entry */
@interface AIJingleHeaderExtension : NSObject
@property (nonatomic) NSInteger extensionId;
@property (nonatomic, copy) NSString *uri;
@end

/*! @brief One a=ssrc block / source element */
@interface AIJingleSource : NSObject
@property (nonatomic, copy) NSString *ssrc;
@property (nonatomic, strong) NSMutableArray<NSArray<NSString *> *> *parameters;	//[name, value], cname and msid among them
@end

/*! @brief One a=ssrc-group / ssrc-group element */
@interface AIJingleSsrcGroup : NSObject
@property (nonatomic, copy) NSString *semantics;	//FID and friends
@property (nonatomic, strong) NSMutableArray<NSString *> *ssrcs;
@end

/*! @brief One ICE candidate, in either spelling */
@interface AIJingleCandidate : NSObject
@property (nonatomic, copy) NSString *foundation;
@property (nonatomic) NSInteger component;
@property (nonatomic, copy) NSString *protocol;		//udp/tcp, lowercased
@property (nonatomic) long long priority;
@property (nonatomic, copy) NSString *ip;
@property (nonatomic) NSInteger port;
@property (nonatomic, copy) NSString *type;			//host/srflx/prflx/relay
@property (nonatomic, copy) NSString *relAddr;		//nil unless reflexive/relayed
@property (nonatomic) NSInteger relPort;
@property (nonatomic, copy) NSString *tcpType;		//SDP only; Jingle has no spelling for it
@property (nonatomic) NSInteger generation;
@property (nonatomic, copy) NSString *candidateId;	//Jingle requires one; minted when SDP had none

/*! @brief Parse "candidate:..." or "a=candidate:..."; nil when it is no candidate line */
+ (instancetype)candidateFromSDPLine:(NSString *)line;
- (NSString *)sdpLine;								//without the "a=" prefix, the way WebRTC hands them around
@end

/*! @brief Everything one m-section / one content element says */
@interface AIJingleContent : NSObject
@property (nonatomic, copy) NSString *name;			//the mid
@property (nonatomic, copy) NSString *media;		//audio/video
@property (nonatomic, copy) NSString *senders;		//both/initiator/responder/none
@property (nonatomic, copy) NSString *msid;			//"stream track" as the a=msid line says it
@property (nonatomic) BOOL rtcpMux;
@property (nonatomic, copy) NSString *iceUfrag;
@property (nonatomic, copy) NSString *icePwd;
@property (nonatomic, copy) NSString *fingerprintHash;
@property (nonatomic, copy) NSString *fingerprintValue;
@property (nonatomic, copy) NSString *dtlsSetup;	//actpass/active/passive
@property (nonatomic, strong) NSMutableArray<AIJinglePayloadType *> *payloadTypes;
@property (nonatomic, strong) NSMutableArray<AIJingleHeaderExtension *> *headerExtensions;
@property (nonatomic, strong) NSMutableArray<AIJingleSource *> *sources;
@property (nonatomic, strong) NSMutableArray<AIJingleSsrcGroup *> *ssrcGroups;
@property (nonatomic, strong) NSMutableArray<AIJingleCandidate *> *candidates;
@end

/*! @brief One whole session description, whichever language it arrived in */
@interface AIJingleSession : NSObject
@property (nonatomic, copy) NSString *sid;
@property (nonatomic, copy) NSString *groupSemantics;				//BUNDLE, or nil for none
@property (nonatomic, strong) NSMutableArray<NSString *> *groupContents;
@property (nonatomic) BOOL extmapAllowMixed;
@property (nonatomic, strong) NSMutableArray<AIJingleContent *> *contents;

//SDP
+ (instancetype)sessionFromSDP:(NSString *)sdp;
- (NSString *)sdpString;

//Jingle. The role says whose view the direction attributes are written from:
//an offer travels as the initiator's words, an answer as the responder's.
- (NSString *)jingleElementForAction:(NSString *)action
						   initiator:(NSString *)initiator
						 responder:(NSString *)responder
						   asInitiator:(BOOL)asInitiator;
+ (instancetype)sessionFromJingleElementString:(NSString *)jingleXML asInitiator:(BOOL)asInitiator;

/*! @brief Everything as plain values, for tests to compare and people to read */
- (NSDictionary *)dictionaryRepresentation;
@end
