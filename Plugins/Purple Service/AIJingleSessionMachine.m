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

#import "AIJingleSessionMachine.h"
#import "AIJingleEngine.h"

@interface AIJingleSessionMachine ()
@property (nonatomic) AIJingleCallState state;
@property (nonatomic, copy) NSString *sid;
@property (nonatomic, copy) NSString *peerJid;
@property (nonatomic, copy) NSString *localJid;
@property (nonatomic) BOOL isInitiator;
@end

@implementation AIJingleSessionMachine {
	AIJingleSession *localSession;			//what we offered or answered; carries our ICE credentials
	NSMutableArray<NSArray<NSString *> *> *queuedRemoteCandidates;	//[line, mid] until the remote description stands
	BOOL remoteDescriptionApplied;
}

- (id)initAsInitiatorFrom:(NSString *)localJid to:(NSString *)peerJid sid:(NSString *)sid
{
	if ((self = [super init])) {
		self.localJid = localJid;
		self.peerJid = peerJid;
		self.isInitiator = YES;
		self.state = AIJingleCallStateIdle;
		self.sid = ([sid length] ? sid : ({
			//Mint an unpredictable sid; XEP-0166 only asks for uniqueness
			uint32_t noise[2] = { arc4random(), arc4random() };
			[NSString stringWithFormat:@"adium%08x%08x", noise[0], noise[1]];
		}));
		queuedRemoteCandidates = [NSMutableArray array];
	}
	return self;
}

- (id)initAsResponderFrom:(NSString *)localJid to:(NSString *)peerJid sid:(NSString *)sid
{
	if ((self = [super init])) {
		self.localJid = localJid;
		self.peerJid = peerJid;
		self.sid = sid;
		self.isInitiator = NO;
		self.state = AIJingleCallStateIdle;
		queuedRemoteCandidates = [NSMutableArray array];
	}
	return self;
}

//Initiator --------------------------------------------------------------------------------------
#pragma mark Initiator

- (void)startWithLocalOfferSDP:(NSString *)offerSDP
{
	if (self.state != AIJingleCallStateIdle)
		return;

	localSession = [AIJingleSession sessionFromSDP:offerSDP];
	localSession.sid = self.sid;
	self.state = AIJingleCallStatePendingOutgoing;

	[self.delegate machine:self
		 sendJingleElement:[localSession jingleElementForAction:@"session-initiate"
													  initiator:self.localJid
													  responder:nil
													asInitiator:YES]];
}

//Responder --------------------------------------------------------------------------------------
#pragma mark Responder

- (void)receivedInitiateElement:(NSString *)jingleXML
{
	if (self.state != AIJingleCallStateIdle || self.isInitiator)
		return;

	//The initiate is written in the initiator's words; we sit in the other chair
	AIJingleSession *remote = [AIJingleSession sessionFromJingleElementString:jingleXML asInitiator:NO];
	if (![remote.contents count]) {
		[self terminateLocallyWithReason:@"failed-application"];
		return;
	}

	if ([remote.sid length])
		self.sid = remote.sid;
	self.state = AIJingleCallStatePendingIncoming;
	remoteDescriptionApplied = YES;		//the initiate is the remote description

	[self.delegate machine:self applyRemoteSDP:[remote sdpString] isOffer:YES];
}

- (void)acceptWithLocalAnswerSDP:(NSString *)answerSDP
{
	if (self.state != AIJingleCallStatePendingIncoming)
		return;

	localSession = [AIJingleSession sessionFromSDP:answerSDP];
	localSession.sid = self.sid;
	self.state = AIJingleCallStateActive;

	[self.delegate machine:self
		 sendJingleElement:[localSession jingleElementForAction:@"session-accept"
													  initiator:nil
													  responder:self.localJid
													asInitiator:NO]];
}

//The peer's turns -------------------------------------------------------------------------------
#pragma mark The peer's turns

/*!
 * @brief The jingle element's own words, read as XML
 *
 * TRAP, and it cost a call: a stanza off the wire is spelled with single quotes,
 * ours with double ones, so anything that went looking for action=" found nothing
 * in everything a peer ever sent. Attributes are read from the parsed document.
 */
static NSXMLElement *jingleRootElement(NSString *jingleXML)
{
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:jingleXML options:0 error:NULL];
	NSXMLElement *root = [document rootElement];

	return ([[root name] isEqualToString:@"jingle"] ? root : nil);
}

- (void)handleRemoteJingleElement:(NSString *)jingleXML
{
	NSXMLElement *jingle = jingleRootElement(jingleXML);
	NSString *action = [[jingle attributeForName:@"action"] stringValue];

	if ([action isEqualToString:@"session-initiate"]) {
		[self receivedInitiateElement:jingleXML];

	} else if ([action isEqualToString:@"session-accept"]) {
		if (self.state != AIJingleCallStatePendingOutgoing)
			return;

		//The accept is written in the responder's words; we are the initiator reading them
		AIJingleSession *remote = [AIJingleSession sessionFromJingleElementString:jingleXML asInitiator:YES];
		if (![remote.contents count]) {
			[self hangUpWithReason:@"failed-application"];
			return;
		}

		/* An answer must say active or passive; a peer that parrots actpass back
		 * would leave both sides waiting for the other's DTLS hello */
		for (AIJingleContent *content in remote.contents)
			if (![content.dtlsSetup length])
				content.dtlsSetup = @"active";

		self.state = AIJingleCallStateActive;
		remoteDescriptionApplied = YES;
		[self.delegate machine:self applyRemoteSDP:[remote sdpString] isOffer:NO];
		[self flushQueuedCandidates];

	} else if ([action isEqualToString:@"transport-info"]) {
		AIJingleSession *info = [AIJingleSession sessionFromJingleElementString:jingleXML
																	 asInitiator:self.isInitiator];
		for (AIJingleContent *content in info.contents) {
			for (AIJingleCandidate *candidate in content.candidates) {
				if (remoteDescriptionApplied)
					[self.delegate machine:self addRemoteCandidateLine:[candidate sdpLine] mid:content.name];
				else
					//Candidates may outrun the accept; hold them until the description stands
					[queuedRemoteCandidates addObject:@[[candidate sdpLine], content.name ?: @""]];
			}
		}

	} else if ([action isEqualToString:@"session-terminate"]) {
		//The first element inside <reason> names it
		NSString *reason = @"gone";
		for (NSXMLNode *child in [[[jingle elementsForName:@"reason"] firstObject] children]) {
			if ([child kind] == NSXMLElementKind) {
				reason = [child name];
				break;
			}
		}
		self.state = AIJingleCallStateEnded;
		[self.delegate machine:self endedWithReason:reason locally:NO];
	}
	//content-add, content-modify and friends: nothing yet; renegotiation is a later chapter
}

- (void)flushQueuedCandidates
{
	NSArray *queued = [queuedRemoteCandidates copy];
	[queuedRemoteCandidates removeAllObjects];
	for (NSArray<NSString *> *entry in queued)
		[self.delegate machine:self addRemoteCandidateLine:entry[0] mid:entry[1]];
}

//Trickling out ----------------------------------------------------------------------------------
#pragma mark Trickling out

- (void)addLocalCandidateLine:(NSString *)line mid:(NSString *)mid
{
	if (self.state == AIJingleCallStateEnded || self.state == AIJingleCallStateIdle)
		return;

	AIJingleCandidate *candidate = [AIJingleCandidate candidateFromSDPLine:line];
	if (!candidate)
		return;

	//A candidate travels inside a transport that names our ICE credentials for its content
	AIJingleContent *local = nil;
	for (AIJingleContent *content in localSession.contents)
		if ([content.name isEqualToString:mid])
			local = content;
	if (!local)
		return;

	AIJingleSession *info = [[AIJingleSession alloc] init];
	info.sid = self.sid;
	AIJingleContent *content = [[AIJingleContent alloc] init];
	content.name = mid;
	content.media = local.media;
	content.iceUfrag = local.iceUfrag;
	content.icePwd = local.icePwd;
	[content.candidates addObject:candidate];
	[info.contents addObject:content];

	/* transport-info carries no description; the engine writes one only when there are
	 * payload types, and this content has none, so the element comes out transport-only */
	[self.delegate machine:self
		 sendJingleElement:[info jingleElementForAction:@"transport-info"
											  initiator:nil
											  responder:nil
											asInitiator:self.isInitiator]];
}

//Ending -----------------------------------------------------------------------------------------
#pragma mark Ending

- (void)hangUpWithReason:(NSString *)reason
{
	if (self.state == AIJingleCallStateEnded)
		return;

	NSString *why = ([reason length] ? reason : @"success");

	//The sid can be the peer's words (responder side); it must not break out of the attribute
	NSMutableString *safeSid = [(self.sid ?: @"") mutableCopy];
	[safeSid replaceOccurrencesOfString:@"&" withString:@"&amp;" options:NSLiteralSearch range:NSMakeRange(0, [safeSid length])];
	[safeSid replaceOccurrencesOfString:@"<" withString:@"&lt;" options:NSLiteralSearch range:NSMakeRange(0, [safeSid length])];
	[safeSid replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:NSLiteralSearch range:NSMakeRange(0, [safeSid length])];

	NSString *terminate = [NSString stringWithFormat:
		@"<jingle xmlns=\"urn:xmpp:jingle:1\" action=\"session-terminate\" sid=\"%@\">"
		@"<reason><%@/></reason></jingle>", safeSid, why];

	self.state = AIJingleCallStateEnded;
	[self.delegate machine:self sendJingleElement:terminate];
	[self.delegate machine:self endedWithReason:why locally:YES];
}

- (void)terminateLocallyWithReason:(NSString *)reason
{
	self.state = AIJingleCallStateEnded;
	[self.delegate machine:self endedWithReason:reason locally:YES];
}

- (void)abandonWithReason:(NSString *)reason locally:(BOOL)locally
{
	if (self.state == AIJingleCallStateEnded)
		return;

	self.state = AIJingleCallStateEnded;
	[self.delegate machine:self endedWithReason:reason locally:locally];
}

@end
