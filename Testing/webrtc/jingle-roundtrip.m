/* Round-trip checks for the Jingle engine, against the SDP this WebRTC build
 * really produces (fixtures/offer.sdp, regenerate with sdp-dump.m).
 *
 * The engine is Foundation only, so this compiles it straight from the source
 * tree with no Adium or libpurple anywhere near it:
 *
 *   SDP -> model -> SDP -> model        the two models must agree
 *   model -> Jingle XML -> model        must agree with the first model
 *   candidate line -> model -> XML -> back
 */
#import <Foundation/Foundation.h>
#import "AIJingleEngine.h"

static int failures = 0;

static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

/* Name the first place two nested structures part ways, for humans */
static NSString *firstDifference(id a, id b, NSString *path)
{
	if ([a isEqual:b]) return nil;
	if ([a isKindOfClass:[NSDictionary class]] && [b isKindOfClass:[NSDictionary class]]) {
		for (id key in (NSDictionary *)a) {
			NSString *found = firstDifference(((NSDictionary *)a)[key], ((NSDictionary *)b)[key],
											  [path stringByAppendingFormat:@".%@", key]);
			if (found) return found;
		}
		return [path stringByAppendingString:@" (keys differ)"];
	}
	if ([a isKindOfClass:[NSArray class]] && [b isKindOfClass:[NSArray class]]) {
		if ([(NSArray *)a count] != [(NSArray *)b count])
			return [path stringByAppendingFormat:@" (count %lu vs %lu)",
					[(NSArray *)a count], [(NSArray *)b count]];
		for (NSUInteger index = 0; index < [(NSArray *)a count]; index++) {
			NSString *found = firstDifference(((NSArray *)a)[index], ((NSArray *)b)[index],
											  [path stringByAppendingFormat:@"[%lu]", index]);
			if (found) return found;
		}
	}
	return [path stringByAppendingFormat:@": %@ vs %@", a, b];
}

int main(int argc, char **argv) { @autoreleasepool {
	NSString *fixturePath = (argc > 1) ? [NSString stringWithUTF8String:argv[1]] : @"fixtures/offer.sdp";
	NSString *sdp = [NSString stringWithContentsOfFile:fixturePath
											  encoding:NSUTF8StringEncoding error:NULL];
	if (![sdp length]) { printf("FAIL  Fixture %s fehlt\n", fixturePath.UTF8String); return 1; }

	//SDP -> model
	AIJingleSession *first = [AIJingleSession sessionFromSDP:sdp];
	first.sid = @"testsid";
	check(@"SDP geparst: zwei Inhalte, Gruppe BUNDLE",
		  [first.contents count] == 2 && [first.groupSemantics isEqualToString:@"BUNDLE"], nil);
	check(@"Audio traegt Opus samt fmtp und rtcp-fb", ({
		AIJinglePayloadType *opus = [[[first.contents firstObject] payloadTypes] firstObject];
		opus.payloadId == 111 && [opus.name isEqualToString:@"opus"] && opus.channels == 2 &&
			[opus.parameters count] == 2 && [opus.feedback count] == 1;
	}), nil);
	check(@"Video traegt H264 mit profile-level-id", ({
		AIJinglePayloadType *h264 = [[first.contents[1] payloadTypes] firstObject];
		BOOL found = NO;
		for (NSArray *p in h264.parameters) found |= [p[0] isEqualToString:@"profile-level-id"];
		[h264.name isEqualToString:@"H264"] && found;
	}), nil);
	check(@"Fingerprint und ICE-Zugangsdaten da", ({
		AIJingleContent *audio = [first.contents firstObject];
		[audio.fingerprintHash isEqualToString:@"sha-256"] && [audio.fingerprintValue length] == 95 &&
			[audio.iceUfrag length] && [audio.icePwd length];
	}), nil);

	//SDP -> model -> SDP -> model
	AIJingleSession *second = [AIJingleSession sessionFromSDP:[first sdpString]];
	second.sid = first.sid;
	NSString *difference = firstDifference([first dictionaryRepresentation],
										   [second dictionaryRepresentation], @"sdp");
	check(@"SDP-Kreis: Modell bleibt identisch", difference == nil, difference);

	//model -> Jingle -> model
	NSString *jingleXML = [first jingleElementForAction:@"session-initiate"
											  initiator:@"adium@localhost/test"
											  responder:nil
											asInitiator:YES];
	check(@"Jingle-XML entsteht und nennt die Namespaces",
		  [jingleXML containsString:@"urn:xmpp:jingle:apps:rtp:1"] &&
		  [jingleXML containsString:@"urn:xmpp:jingle:transports:ice-udp:1"] &&
		  [jingleXML containsString:@"urn:xmpp:jingle:apps:dtls:0"], nil);

	AIJingleSession *third = [AIJingleSession sessionFromJingleElementString:jingleXML asInitiator:YES];
	difference = firstDifference([first dictionaryRepresentation],
								 [third dictionaryRepresentation], @"jingle");
	check(@"Jingle-Kreis: Modell bleibt identisch", difference == nil, difference);
	check(@"Session-id ueberlebt den Kreis", [third.sid isEqualToString:@"testsid"], third.sid);

	//A candidate line, there and back
	NSString *line = @"candidate:1467250027 1 udp 2122260223 192.168.0.196 46243 typ host generation 0";
	AIJingleCandidate *candidate = [AIJingleCandidate candidateFromSDPLine:line];
	check(@"Kandidat gelesen", candidate && candidate.port == 46243 &&
		  [candidate.type isEqualToString:@"host"], nil);
	check(@"Kandidatenzeile kehrt woertlich zurueck", [[candidate sdpLine] isEqualToString:line],
		  [candidate sdpLine]);
	NSString *srflx = @"candidate:842163049 1 udp 1686052607 203.0.113.7 46243 typ srflx raddr 192.168.0.196 rport 46243 generation 0";
	AIJingleCandidate *reflexive = [AIJingleCandidate candidateFromSDPLine:srflx];
	check(@"Reflexiver Kandidat samt raddr/rport", [[reflexive sdpLine] isEqualToString:srflx],
		  [reflexive sdpLine]);

	//The senders words, seen from both chairs
	check(@"Richtungswoerter aus beiden Rollen", ({
		AIJingleSession *session = [[AIJingleSession alloc] init];
		AIJingleContent *content = [[AIJingleContent alloc] init];
		content.name = @"0"; content.media = @"audio"; content.senders = @"sendonly";
		[session.contents addObject:content];
		NSString *asInit = [session jingleElementForAction:@"x" initiator:nil responder:nil asInitiator:YES];
		NSString *asResp = [session jingleElementForAction:@"x" initiator:nil responder:nil asInitiator:NO];
		[asInit containsString:@"senders=\"initiator\""] && [asResp containsString:@"senders=\"responder\""];
	}), nil);

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
