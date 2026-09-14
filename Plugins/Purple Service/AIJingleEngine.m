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

#import "AIJingleEngine.h"

#define NS_JINGLE			@"urn:xmpp:jingle:1"
#define NS_RTP				@"urn:xmpp:jingle:apps:rtp:1"
#define NS_RTP_FB			@"urn:xmpp:jingle:apps:rtp:rtcp-fb:0"
#define NS_RTP_HDREXT		@"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0"
#define NS_RTP_SSMA			@"urn:xmpp:jingle:apps:rtp:ssma:0"
#define NS_ICE_UDP			@"urn:xmpp:jingle:transports:ice-udp:1"
#define NS_DTLS				@"urn:xmpp:jingle:apps:dtls:0"
#define NS_GROUPING			@"urn:xmpp:jingle:apps:grouping:0"

@implementation AIJinglePayloadType
- (id)init { if ((self = [super init])) { _parameters = [NSMutableArray array]; _feedback = [NSMutableArray array]; } return self; }
@end

@implementation AIJingleHeaderExtension
@end

@implementation AIJingleSource
- (id)init { if ((self = [super init])) { _parameters = [NSMutableArray array]; } return self; }
@end

@implementation AIJingleSsrcGroup
- (id)init { if ((self = [super init])) { _ssrcs = [NSMutableArray array]; } return self; }
@end

@implementation AIJingleCandidate

+ (instancetype)candidateFromSDPLine:(NSString *)line
{
	if ([line hasPrefix:@"a="])
		line = [line substringFromIndex:2];
	if (![line hasPrefix:@"candidate:"])
		return nil;

	NSArray<NSString *> *parts = [[line substringFromIndex:[@"candidate:" length]]
								  componentsSeparatedByString:@" "];
	if ([parts count] < 8)
		return nil;

	AIJingleCandidate *candidate = [[AIJingleCandidate alloc] init];
	candidate.foundation = parts[0];
	candidate.component = [parts[1] integerValue];
	candidate.protocol = [parts[2] lowercaseString];
	candidate.priority = [parts[3] longLongValue];
	candidate.ip = parts[4];
	candidate.port = [parts[5] integerValue];
	//parts[6] is the literal "typ"
	candidate.type = parts[7];

	for (NSUInteger index = 8; index + 1 < [parts count]; index += 2) {
		NSString *key = parts[index], *value = parts[index + 1];

		if ([key isEqualToString:@"raddr"])
			candidate.relAddr = value;
		else if ([key isEqualToString:@"rport"])
			candidate.relPort = [value integerValue];
		else if ([key isEqualToString:@"tcptype"])
			candidate.tcpType = value;
		else if ([key isEqualToString:@"generation"])
			candidate.generation = [value integerValue];
		//ufrag, network-id, network-cost: nothing Jingle can say; dropped knowingly
	}

	/* Jingle requires an id and SDP has none. Minted deterministically, so the same
	 * candidate gets the same id whichever road it took into the model. */
	candidate.candidateId = [NSString stringWithFormat:@"adium%@c%ldp%ld",
							 candidate.foundation, (long)candidate.component, (long)candidate.port];
	return candidate;
}

- (NSString *)sdpLine
{
	NSMutableString *line = [NSMutableString stringWithFormat:
		@"candidate:%@ %ld %@ %lld %@ %ld typ %@",
		self.foundation, (long)self.component, self.protocol, self.priority,
		self.ip, (long)self.port, self.type];

	if ([self.relAddr length])
		[line appendFormat:@" raddr %@ rport %ld", self.relAddr, (long)self.relPort];
	if ([self.tcpType length])
		[line appendFormat:@" tcptype %@", self.tcpType];
	[line appendFormat:@" generation %ld", (long)self.generation];

	return line;
}

@end

@implementation AIJingleContent
- (id)init
{
	if ((self = [super init])) {
		_senders = @"both";
		_payloadTypes = [NSMutableArray array];
		_headerExtensions = [NSMutableArray array];
		_sources = [NSMutableArray array];
		_ssrcGroups = [NSMutableArray array];
		_candidates = [NSMutableArray array];
	}
	return self;
}
@end

@implementation AIJingleSession

- (id)init
{
	if ((self = [super init])) {
		_groupContents = [NSMutableArray array];
		_contents = [NSMutableArray array];
	}
	return self;
}

//SDP parsing ------------------------------------------------------------------------------------
#pragma mark SDP parsing

+ (instancetype)sessionFromSDP:(NSString *)sdp
{
	AIJingleSession *session = [[AIJingleSession alloc] init];
	AIJingleContent *content = nil;
	AIJinglePayloadType *(^payloadFor)(AIJingleContent *, NSInteger) = ^(AIJingleContent *inContent, NSInteger payloadId) {
		for (AIJinglePayloadType *payload in inContent.payloadTypes)
			if (payload.payloadId == payloadId)
				return payload;
		return (AIJinglePayloadType *)nil;
	};

	for (NSString *rawLine in [sdp componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
		NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (![line length])
			continue;

		if ([line hasPrefix:@"m="]) {
			NSArray<NSString *> *parts = [[line substringFromIndex:2] componentsSeparatedByString:@" "];
			content = [[AIJingleContent alloc] init];
			content.media = [parts firstObject];

			//The payload ids come in the m-line's order; rtpmap lines fill in their names
			for (NSUInteger index = 3; index < [parts count]; index++) {
				AIJinglePayloadType *payload = [[AIJinglePayloadType alloc] init];
				payload.payloadId = [parts[index] integerValue];
				[content.payloadTypes addObject:payload];
			}
			[session.contents addObject:content];
			continue;
		}

		if (![line hasPrefix:@"a="])
			continue;	//v=, o=, s=, t=, c= say nothing Jingle wants to hear

		NSString *attribute = [line substringFromIndex:2];
		NSRange colon = [attribute rangeOfString:@":"];
		NSString *attributeName = (colon.location == NSNotFound ? attribute : [attribute substringToIndex:colon.location]);
		NSString *value = (colon.location == NSNotFound ? @"" : [attribute substringFromIndex:colon.location + 1]);

		if (!content) {
			//Session level
			if ([attributeName isEqualToString:@"group"]) {
				NSArray<NSString *> *parts = [value componentsSeparatedByString:@" "];
				session.groupSemantics = [parts firstObject];
				[session.groupContents addObjectsFromArray:
					[parts subarrayWithRange:NSMakeRange(1, [parts count] - 1)]];
			} else if ([attributeName isEqualToString:@"extmap-allow-mixed"]) {
				session.extmapAllowMixed = YES;
			}
			continue;
		}

		if ([attributeName isEqualToString:@"mid"]) {
			content.name = value;
		} else if ([attributeName isEqualToString:@"ice-ufrag"]) {
			content.iceUfrag = value;
		} else if ([attributeName isEqualToString:@"ice-pwd"]) {
			content.icePwd = value;
		} else if ([attributeName isEqualToString:@"fingerprint"]) {
			NSArray<NSString *> *parts = [value componentsSeparatedByString:@" "];
			if ([parts count] == 2) {
				content.fingerprintHash = parts[0];
				content.fingerprintValue = parts[1];
			}
		} else if ([attributeName isEqualToString:@"setup"]) {
			content.dtlsSetup = value;
		} else if ([attributeName isEqualToString:@"msid"]) {
			content.msid = value;
		} else if ([attributeName isEqualToString:@"rtcp-mux"]) {
			content.rtcpMux = YES;
		} else if ([attributeName isEqualToString:@"sendrecv"] || [attributeName isEqualToString:@"sendonly"] ||
				   [attributeName isEqualToString:@"recvonly"] || [attributeName isEqualToString:@"inactive"]) {
			content.senders = attributeName;	//translated into Jingle words at emit time
		} else if ([attributeName isEqualToString:@"extmap"]) {
			NSArray<NSString *> *parts = [value componentsSeparatedByString:@" "];
			if ([parts count] >= 2) {
				AIJingleHeaderExtension *extension = [[AIJingleHeaderExtension alloc] init];
				//A direction suffix ("14/recvonly") has no Jingle spelling; the id alone survives
				extension.extensionId = [parts[0] integerValue];
				extension.uri = parts[1];
				[content.headerExtensions addObject:extension];
			}
		} else if ([attributeName isEqualToString:@"rtpmap"]) {
			NSArray<NSString *> *parts = [value componentsSeparatedByString:@" "];
			AIJinglePayloadType *payload = payloadFor(content, [parts[0] integerValue]);
			if (payload && [parts count] >= 2) {
				NSArray<NSString *> *pieces = [parts[1] componentsSeparatedByString:@"/"];
				payload.name = [pieces firstObject];
				if ([pieces count] > 1) payload.clockrate = [pieces[1] integerValue];
				if ([pieces count] > 2) payload.channels = [pieces[2] integerValue];
			}
		} else if ([attributeName isEqualToString:@"rtcp-fb"]) {
			NSArray<NSString *> *parts = [value componentsSeparatedByString:@" "];
			AIJinglePayloadType *payload = payloadFor(content, [parts[0] integerValue]);
			if (payload && [parts count] >= 2)
				[payload.feedback addObject:@[parts[1], ([parts count] > 2 ? parts[2] : @"")]];
		} else if ([attributeName isEqualToString:@"fmtp"]) {
			NSRange space = [value rangeOfString:@" "];
			AIJinglePayloadType *payload = payloadFor(content, [value integerValue]);
			if (payload && space.location != NSNotFound) {
				for (NSString *token in [[value substringFromIndex:space.location + 1]
										 componentsSeparatedByString:@";"]) {
					NSRange equals = [token rangeOfString:@"="];
					if (equals.location != NSNotFound)
						[payload.parameters addObject:@[[token substringToIndex:equals.location],
														[token substringFromIndex:equals.location + 1]]];
					else
						[payload.parameters addObject:@[@"", token]];	//red says "111/111", no pair
				}
			}
		} else if ([attributeName isEqualToString:@"ssrc-group"]) {
			NSArray<NSString *> *parts = [value componentsSeparatedByString:@" "];
			AIJingleSsrcGroup *group = [[AIJingleSsrcGroup alloc] init];
			group.semantics = [parts firstObject];
			[group.ssrcs addObjectsFromArray:[parts subarrayWithRange:NSMakeRange(1, [parts count] - 1)]];
			[content.ssrcGroups addObject:group];
		} else if ([attributeName isEqualToString:@"ssrc"]) {
			NSRange space = [value rangeOfString:@" "];
			if (space.location == NSNotFound)
				continue;
			NSString *ssrc = [value substringToIndex:space.location];
			NSString *pair = [value substringFromIndex:space.location + 1];
			NSRange pairColon = [pair rangeOfString:@":"];
			NSString *pairName = (pairColon.location == NSNotFound ? pair : [pair substringToIndex:pairColon.location]);
			NSString *pairValue = (pairColon.location == NSNotFound ? @"" : [pair substringFromIndex:pairColon.location + 1]);

			AIJingleSource *source = nil;
			for (AIJingleSource *existing in content.sources)
				if ([existing.ssrc isEqualToString:ssrc])
					source = existing;
			if (!source) {
				source = [[AIJingleSource alloc] init];
				source.ssrc = ssrc;
				[content.sources addObject:source];
			}
			[source.parameters addObject:@[pairName, pairValue]];
		} else if ([attributeName isEqualToString:@"candidate"]) {
			AIJingleCandidate *candidate = [AIJingleCandidate candidateFromSDPLine:attribute];
			if (candidate)
				[content.candidates addObject:candidate];
		}
		//Everything else (rtcp, rtcp-rsize, rtcp-xr, ice-options, msid-semantic) has no Jingle ear
	}

	return session;
}

//SDP writing ------------------------------------------------------------------------------------
#pragma mark SDP writing

- (NSString *)sdpString
{
	NSMutableString *sdp = [NSMutableString string];

	[sdp appendString:@"v=0\r\n"];
	[sdp appendString:@"o=- 3735928559 2 IN IP4 127.0.0.1\r\n"];
	[sdp appendString:@"s=-\r\n"];
	[sdp appendString:@"t=0 0\r\n"];
	if ([self.groupSemantics length])
		[sdp appendFormat:@"a=group:%@ %@\r\n", self.groupSemantics,
			[self.groupContents componentsJoinedByString:@" "]];
	if (self.extmapAllowMixed)
		[sdp appendString:@"a=extmap-allow-mixed\r\n"];
	[sdp appendString:@"a=msid-semantic: WMS\r\n"];

	for (AIJingleContent *content in self.contents) {
		NSMutableArray *payloadIds = [NSMutableArray array];
		for (AIJinglePayloadType *payload in content.payloadTypes)
			[payloadIds addObject:[NSString stringWithFormat:@"%ld", (long)payload.payloadId]];

		[sdp appendFormat:@"m=%@ 9 UDP/TLS/RTP/SAVPF %@\r\n", content.media,
			[payloadIds componentsJoinedByString:@" "]];
		[sdp appendString:@"c=IN IP4 0.0.0.0\r\n"];
		[sdp appendString:@"a=rtcp:9 IN IP4 0.0.0.0\r\n"];
		if ([content.iceUfrag length])
			[sdp appendFormat:@"a=ice-ufrag:%@\r\n", content.iceUfrag];
		if ([content.icePwd length])
			[sdp appendFormat:@"a=ice-pwd:%@\r\n", content.icePwd];
		[sdp appendString:@"a=ice-options:trickle\r\n"];
		if ([content.fingerprintValue length])
			[sdp appendFormat:@"a=fingerprint:%@ %@\r\n", content.fingerprintHash, content.fingerprintValue];
		if ([content.dtlsSetup length])
			[sdp appendFormat:@"a=setup:%@\r\n", content.dtlsSetup];
		[sdp appendFormat:@"a=mid:%@\r\n", content.name];
		for (AIJingleHeaderExtension *extension in content.headerExtensions)
			[sdp appendFormat:@"a=extmap:%ld %@\r\n", (long)extension.extensionId, extension.uri];
		[sdp appendFormat:@"a=%@\r\n", content.senders];
		if ([content.msid length])
			[sdp appendFormat:@"a=msid:%@\r\n", content.msid];
		if (content.rtcpMux)
			[sdp appendString:@"a=rtcp-mux\r\n"];

		for (AIJinglePayloadType *payload in content.payloadTypes) {
			if ([payload.name length]) {
				[sdp appendFormat:@"a=rtpmap:%ld %@/%ld", (long)payload.payloadId, payload.name,
					(long)payload.clockrate];
				if (payload.channels > 0)
					[sdp appendFormat:@"/%ld", (long)payload.channels];
				[sdp appendString:@"\r\n"];
			}
			for (NSArray<NSString *> *feedback in payload.feedback) {
				[sdp appendFormat:@"a=rtcp-fb:%ld %@", (long)payload.payloadId, feedback[0]];
				if ([feedback[1] length])
					[sdp appendFormat:@" %@", feedback[1]];
				[sdp appendString:@"\r\n"];
			}
			if ([payload.parameters count]) {
				NSMutableArray *tokens = [NSMutableArray array];
				for (NSArray<NSString *> *parameter in payload.parameters)
					[tokens addObject:([parameter[0] length] ?
						[NSString stringWithFormat:@"%@=%@", parameter[0], parameter[1]] : parameter[1])];
				[sdp appendFormat:@"a=fmtp:%ld %@\r\n", (long)payload.payloadId,
					[tokens componentsJoinedByString:@";"]];
			}
		}

		for (AIJingleSsrcGroup *group in content.ssrcGroups)
			[sdp appendFormat:@"a=ssrc-group:%@ %@\r\n", group.semantics,
				[group.ssrcs componentsJoinedByString:@" "]];
		for (AIJingleSource *source in content.sources)
			for (NSArray<NSString *> *parameter in source.parameters)
				[sdp appendFormat:@"a=ssrc:%@ %@%@%@\r\n", source.ssrc, parameter[0],
					([parameter[1] length] ? @":" : @""), parameter[1]];
		for (AIJingleCandidate *candidate in content.candidates)
			[sdp appendFormat:@"a=%@\r\n", [candidate sdpLine]];
	}

	return sdp;
}

//Jingle writing ---------------------------------------------------------------------------------
#pragma mark Jingle writing

static NSXMLElement *element(NSString *name, NSString *xmlns)
{
	NSXMLElement *node = [NSXMLElement elementWithName:name];
	if (xmlns)
		[node addAttribute:[NSXMLNode attributeWithName:@"xmlns" stringValue:xmlns]];
	return node;
}

static void attribute(NSXMLElement *node, NSString *name, NSString *value)
{
	if ([value length])
		[node addAttribute:[NSXMLNode attributeWithName:name stringValue:value]];
}

/*! The direction words of SDP are written from the speaker's chair; Jingle's name the parties */
static NSString *sendersFromDirection(NSString *direction, BOOL asInitiator)
{
	if ([direction isEqualToString:@"sendonly"]) return asInitiator ? @"initiator" : @"responder";
	if ([direction isEqualToString:@"recvonly"]) return asInitiator ? @"responder" : @"initiator";
	if ([direction isEqualToString:@"inactive"]) return @"none";
	return @"both";
}

static NSString *directionFromSenders(NSString *senders, BOOL asInitiator)
{
	if ([senders isEqualToString:@"initiator"]) return asInitiator ? @"sendonly" : @"recvonly";
	if ([senders isEqualToString:@"responder"]) return asInitiator ? @"recvonly" : @"sendonly";
	if ([senders isEqualToString:@"none"]) return @"inactive";
	return @"sendrecv";
}

- (NSString *)jingleElementForAction:(NSString *)action
						   initiator:(NSString *)initiator
						 responder:(NSString *)responder
						 asInitiator:(BOOL)asInitiator
{
	NSXMLElement *jingle = element(@"jingle", NS_JINGLE);
	attribute(jingle, @"action", action);
	attribute(jingle, @"sid", self.sid);
	attribute(jingle, @"initiator", initiator);
	attribute(jingle, @"responder", responder);

	if ([self.groupSemantics length]) {
		NSXMLElement *group = element(@"group", NS_GROUPING);
		attribute(group, @"semantics", self.groupSemantics);
		for (NSString *name in self.groupContents) {
			NSXMLElement *entry = element(@"content", nil);
			attribute(entry, @"name", name);
			[group addChild:entry];
		}
		[jingle addChild:group];
	}

	for (AIJingleContent *content in self.contents) {
		NSXMLElement *contentElement = element(@"content", nil);
		attribute(contentElement, @"creator", @"initiator");
		attribute(contentElement, @"name", content.name);
		attribute(contentElement, @"senders", sendersFromDirection(content.senders, asInitiator));

		NSXMLElement *description = element(@"description", NS_RTP);
		attribute(description, @"media", content.media);

		for (AIJinglePayloadType *payload in content.payloadTypes) {
			NSXMLElement *payloadElement = element(@"payload-type", nil);
			attribute(payloadElement, @"id", [NSString stringWithFormat:@"%ld", (long)payload.payloadId]);
			attribute(payloadElement, @"name", payload.name);
			if (payload.clockrate)
				attribute(payloadElement, @"clockrate", [NSString stringWithFormat:@"%ld", (long)payload.clockrate]);
			if (payload.channels)
				attribute(payloadElement, @"channels", [NSString stringWithFormat:@"%ld", (long)payload.channels]);
			for (NSArray<NSString *> *parameter in payload.parameters) {
				NSXMLElement *parameterElement = element(@"parameter", nil);
				[parameterElement addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:parameter[0]]];
				attribute(parameterElement, @"value", parameter[1]);
				[payloadElement addChild:parameterElement];
			}
			for (NSArray<NSString *> *feedback in payload.feedback) {
				NSXMLElement *feedbackElement = element(@"rtcp-fb", NS_RTP_FB);
				attribute(feedbackElement, @"type", feedback[0]);
				attribute(feedbackElement, @"subtype", feedback[1]);
				[payloadElement addChild:feedbackElement];
			}
			[description addChild:payloadElement];
		}

		for (AIJingleHeaderExtension *extension in content.headerExtensions) {
			NSXMLElement *extensionElement = element(@"rtp-hdrext", NS_RTP_HDREXT);
			attribute(extensionElement, @"id", [NSString stringWithFormat:@"%ld", (long)extension.extensionId]);
			attribute(extensionElement, @"uri", extension.uri);
			[description addChild:extensionElement];
		}
		if (self.extmapAllowMixed)
			[description addChild:element(@"extmap-allow-mixed", NS_RTP_HDREXT)];

		for (AIJingleSsrcGroup *group in content.ssrcGroups) {
			NSXMLElement *groupElement = element(@"ssrc-group", NS_RTP_SSMA);
			attribute(groupElement, @"semantics", group.semantics);
			for (NSString *ssrc in group.ssrcs) {
				NSXMLElement *sourceElement = element(@"source", nil);
				attribute(sourceElement, @"ssrc", ssrc);
				[groupElement addChild:sourceElement];
			}
			[description addChild:groupElement];
		}
		for (AIJingleSource *source in content.sources) {
			NSXMLElement *sourceElement = element(@"source", NS_RTP_SSMA);
			attribute(sourceElement, @"ssrc", source.ssrc);
			for (NSArray<NSString *> *parameter in source.parameters) {
				NSXMLElement *parameterElement = element(@"parameter", nil);
				attribute(parameterElement, @"name", parameter[0]);
				attribute(parameterElement, @"value", parameter[1]);
				[sourceElement addChild:parameterElement];
			}
			[description addChild:sourceElement];
		}
		if (content.rtcpMux)
			[description addChild:element(@"rtcp-mux", nil)];
		[contentElement addChild:description];

		NSXMLElement *transport = element(@"transport", NS_ICE_UDP);
		attribute(transport, @"ufrag", content.iceUfrag);
		attribute(transport, @"pwd", content.icePwd);
		if ([content.fingerprintValue length]) {
			NSXMLElement *fingerprint = element(@"fingerprint", NS_DTLS);
			attribute(fingerprint, @"hash", content.fingerprintHash);
			attribute(fingerprint, @"setup", content.dtlsSetup);
			[fingerprint setStringValue:content.fingerprintValue];
			[transport addChild:fingerprint];
		}
		for (AIJingleCandidate *candidate in content.candidates)
			[transport addChild:[AIJingleSession candidateElement:candidate]];
		[contentElement addChild:transport];

		[jingle addChild:contentElement];
	}

	return [jingle XMLString];
}

+ (NSXMLElement *)candidateElement:(AIJingleCandidate *)candidate
{
	NSXMLElement *candidateElement = element(@"candidate", nil);
	attribute(candidateElement, @"component", [NSString stringWithFormat:@"%ld", (long)candidate.component]);
	attribute(candidateElement, @"foundation", candidate.foundation);
	attribute(candidateElement, @"generation", [NSString stringWithFormat:@"%ld", (long)candidate.generation]);
	attribute(candidateElement, @"id", candidate.candidateId);
	attribute(candidateElement, @"ip", candidate.ip);
	attribute(candidateElement, @"network", @"0");
	attribute(candidateElement, @"port", [NSString stringWithFormat:@"%ld", (long)candidate.port]);
	attribute(candidateElement, @"priority", [NSString stringWithFormat:@"%lld", candidate.priority]);
	attribute(candidateElement, @"protocol", candidate.protocol);
	attribute(candidateElement, @"type", candidate.type);
	if ([candidate.relAddr length]) {
		attribute(candidateElement, @"rel-addr", candidate.relAddr);
		attribute(candidateElement, @"rel-port", [NSString stringWithFormat:@"%ld", (long)candidate.relPort]);
	}
	return candidateElement;
}

//Jingle parsing ---------------------------------------------------------------------------------
#pragma mark Jingle parsing

static NSString *attributeValue(NSXMLElement *node, NSString *name)
{
	return [[node attributeForName:name] stringValue];
}

static NSArray<NSXMLElement *> *children(NSXMLElement *node, NSString *name)
{
	NSMutableArray *result = [NSMutableArray array];
	for (NSXMLNode *child in [node children])
		if ([child kind] == NSXMLElementKind && [[child name] isEqualToString:name])
			[result addObject:(NSXMLElement *)child];
	return result;
}

+ (instancetype)sessionFromJingleElementString:(NSString *)jingleXML asInitiator:(BOOL)asInitiator
{
	NSError *error = nil;
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:jingleXML options:0 error:&error];
	NSXMLElement *jingle = [document rootElement];

	if (!jingle || ![[jingle name] isEqualToString:@"jingle"])
		return nil;

	AIJingleSession *session = [[AIJingleSession alloc] init];
	session.sid = attributeValue(jingle, @"sid");

	for (NSXMLElement *group in children(jingle, @"group")) {
		session.groupSemantics = attributeValue(group, @"semantics");
		for (NSXMLElement *entry in children(group, @"content"))
			[session.groupContents addObject:attributeValue(entry, @"name")];
	}

	for (NSXMLElement *contentElement in children(jingle, @"content")) {
		AIJingleContent *content = [[AIJingleContent alloc] init];
		content.name = attributeValue(contentElement, @"name");
		NSString *senders = attributeValue(contentElement, @"senders");
		content.senders = directionFromSenders(([senders length] ? senders : @"both"), asInitiator);

		NSXMLElement *description = [children(contentElement, @"description") firstObject];
		if (description) {
			content.media = attributeValue(description, @"media");

			for (NSXMLElement *payloadElement in children(description, @"payload-type")) {
				AIJinglePayloadType *payload = [[AIJinglePayloadType alloc] init];
				payload.payloadId = [attributeValue(payloadElement, @"id") integerValue];
				payload.name = attributeValue(payloadElement, @"name");
				payload.clockrate = [attributeValue(payloadElement, @"clockrate") integerValue];
				payload.channels = [attributeValue(payloadElement, @"channels") integerValue];
				for (NSXMLElement *parameterElement in children(payloadElement, @"parameter"))
					[payload.parameters addObject:@[attributeValue(parameterElement, @"name") ?: @"",
													attributeValue(parameterElement, @"value") ?: @""]];
				for (NSXMLElement *feedbackElement in children(payloadElement, @"rtcp-fb"))
					[payload.feedback addObject:@[attributeValue(feedbackElement, @"type") ?: @"",
												  attributeValue(feedbackElement, @"subtype") ?: @""]];
				[content.payloadTypes addObject:payload];
			}

			for (NSXMLElement *extensionElement in children(description, @"rtp-hdrext")) {
				AIJingleHeaderExtension *extension = [[AIJingleHeaderExtension alloc] init];
				extension.extensionId = [attributeValue(extensionElement, @"id") integerValue];
				extension.uri = attributeValue(extensionElement, @"uri");
				[content.headerExtensions addObject:extension];
			}
			if ([children(description, @"extmap-allow-mixed") count])
				session.extmapAllowMixed = YES;

			for (NSXMLElement *groupElement in children(description, @"ssrc-group")) {
				AIJingleSsrcGroup *group = [[AIJingleSsrcGroup alloc] init];
				group.semantics = attributeValue(groupElement, @"semantics");
				for (NSXMLElement *sourceElement in children(groupElement, @"source"))
					[group.ssrcs addObject:attributeValue(sourceElement, @"ssrc")];
				[content.ssrcGroups addObject:group];
			}
			for (NSXMLElement *sourceElement in children(description, @"source")) {
				AIJingleSource *source = [[AIJingleSource alloc] init];
				source.ssrc = attributeValue(sourceElement, @"ssrc");
				for (NSXMLElement *parameterElement in children(sourceElement, @"parameter"))
					[source.parameters addObject:@[attributeValue(parameterElement, @"name") ?: @"",
												   attributeValue(parameterElement, @"value") ?: @""]];
				[content.sources addObject:source];

				//The msid rides on the source; the m-section attribute is rebuilt from it
				for (NSArray<NSString *> *parameter in source.parameters)
					if ([parameter[0] isEqualToString:@"msid"] && ![content.msid length])
						content.msid = parameter[1];
			}
			if ([children(description, @"rtcp-mux") count])
				content.rtcpMux = YES;
		}

		NSXMLElement *transport = [children(contentElement, @"transport") firstObject];
		if (transport) {
			content.iceUfrag = attributeValue(transport, @"ufrag");
			content.icePwd = attributeValue(transport, @"pwd");

			NSXMLElement *fingerprint = [children(transport, @"fingerprint") firstObject];
			if (fingerprint) {
				content.fingerprintHash = attributeValue(fingerprint, @"hash");
				content.dtlsSetup = attributeValue(fingerprint, @"setup");
				content.fingerprintValue = [fingerprint stringValue];
			}

			for (NSXMLElement *candidateElement in children(transport, @"candidate")) {
				AIJingleCandidate *candidate = [[AIJingleCandidate alloc] init];
				candidate.foundation = attributeValue(candidateElement, @"foundation");
				candidate.component = [attributeValue(candidateElement, @"component") integerValue];
				candidate.protocol = [attributeValue(candidateElement, @"protocol") lowercaseString];
				candidate.priority = [attributeValue(candidateElement, @"priority") longLongValue];
				candidate.ip = attributeValue(candidateElement, @"ip");
				candidate.port = [attributeValue(candidateElement, @"port") integerValue];
				candidate.type = attributeValue(candidateElement, @"type");
				candidate.relAddr = attributeValue(candidateElement, @"rel-addr");
				candidate.relPort = [attributeValue(candidateElement, @"rel-port") integerValue];
				candidate.generation = [attributeValue(candidateElement, @"generation") integerValue];
				candidate.candidateId = attributeValue(candidateElement, @"id");
				[content.candidates addObject:candidate];
			}
		}

		[session.contents addObject:content];
	}

	return session;
}

//Comparison -------------------------------------------------------------------------------------
#pragma mark Comparison

- (NSDictionary *)dictionaryRepresentation
{
	NSMutableArray *contents = [NSMutableArray array];

	for (AIJingleContent *content in self.contents) {
		NSMutableArray *payloads = [NSMutableArray array];
		for (AIJinglePayloadType *payload in content.payloadTypes)
			[payloads addObject:@{@"id": @(payload.payloadId), @"name": payload.name ?: @"",
								  @"clockrate": @(payload.clockrate), @"channels": @(payload.channels),
								  @"parameters": payload.parameters, @"feedback": payload.feedback}];
		NSMutableArray *extensions = [NSMutableArray array];
		for (AIJingleHeaderExtension *extension in content.headerExtensions)
			[extensions addObject:@{@"id": @(extension.extensionId), @"uri": extension.uri ?: @""}];
		NSMutableArray *sources = [NSMutableArray array];
		for (AIJingleSource *source in content.sources)
			[sources addObject:@{@"ssrc": source.ssrc ?: @"", @"parameters": source.parameters}];
		NSMutableArray *groups = [NSMutableArray array];
		for (AIJingleSsrcGroup *group in content.ssrcGroups)
			[groups addObject:@{@"semantics": group.semantics ?: @"", @"ssrcs": group.ssrcs}];
		NSMutableArray *candidates = [NSMutableArray array];
		for (AIJingleCandidate *candidate in content.candidates)
			[candidates addObject:[candidate sdpLine]];

		[contents addObject:@{@"name": content.name ?: @"", @"media": content.media ?: @"",
							  @"senders": content.senders ?: @"", @"msid": content.msid ?: @"",
							  @"rtcpMux": @(content.rtcpMux),
							  @"iceUfrag": content.iceUfrag ?: @"", @"icePwd": content.icePwd ?: @"",
							  @"fingerprintHash": content.fingerprintHash ?: @"",
							  @"fingerprintValue": content.fingerprintValue ?: @"",
							  @"dtlsSetup": content.dtlsSetup ?: @"",
							  @"payloadTypes": payloads, @"headerExtensions": extensions,
							  @"sources": sources, @"ssrcGroups": groups, @"candidates": candidates}];
	}

	return @{@"groupSemantics": self.groupSemantics ?: @"",
			 @"groupContents": self.groupContents,
			 @"extmapAllowMixed": @(self.extmapAllowMixed),
			 @"contents": contents};
}

@end
