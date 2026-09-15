/* Two session machines talk a whole call through in one process: initiate,
 * a candidate that outruns the accept (the way Conversations trickles), the
 * accept, a candidate the other way, the hangup. The test plays the wire and
 * the media layer; everything the machines say is asserted in order. */
#import <Foundation/Foundation.h>
#import "AIJingleEngine.h"
#import "AIJingleSessionMachine.h"

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

@interface Recorder : NSObject <AIJingleSessionMachineDelegate>
@property (strong) NSMutableArray<NSString *> *sentElements;
@property (strong) NSMutableArray<NSString *> *events;	//readable trace, in order
@property (copy) NSString *lastRemoteSDP;
@end
@implementation Recorder
- (id)init { if ((self = [super init])) { _sentElements = [NSMutableArray array]; _events = [NSMutableArray array]; } return self; }
- (void)machine:(AIJingleSessionMachine *)machine sendJingleElement:(NSString *)jingleXML {
	[self.sentElements addObject:jingleXML];
	[self.events addObject:@"send"];
}
- (void)machine:(AIJingleSessionMachine *)machine applyRemoteSDP:(NSString *)sdp isOffer:(BOOL)isOffer {
	self.lastRemoteSDP = sdp;
	[self.events addObject:(isOffer ? @"remote-offer" : @"remote-answer")];
}
- (void)machine:(AIJingleSessionMachine *)machine addRemoteCandidateLine:(NSString *)line mid:(NSString *)mid {
	[self.events addObject:[NSString stringWithFormat:@"candidate %@ %@", mid, line]];
}
- (void)machine:(AIJingleSessionMachine *)machine endedWithReason:(NSString *)reason locally:(BOOL)locally {
	[self.events addObject:[NSString stringWithFormat:@"ended %@ %@", reason, locally ? @"local" : @"remote"]];
}
@end

int main(int argc, char **argv) { @autoreleasepool {
	NSString *fixturePath = (argc > 1) ? [NSString stringWithUTF8String:argv[1]] : @"fixtures/offer.sdp";
	NSString *offerSDP = [NSString stringWithContentsOfFile:fixturePath
												   encoding:NSUTF8StringEncoding error:NULL];
	if (![offerSDP length]) { printf("FAIL  Fixture fehlt\n"); return 1; }

	Recorder *forA = [Recorder new], *forB = [Recorder new];
	AIJingleSessionMachine *a = [[AIJingleSessionMachine alloc] initAsInitiatorFrom:@"adium@localhost/a"
																				 to:@"peer@localhost/b"
																				sid:@"testsid"];
	AIJingleSessionMachine *b = [[AIJingleSessionMachine alloc] initAsResponderFrom:@"peer@localhost/b"
																				 to:@"adium@localhost/a"
																				 sid:@"testsid"];
	a.delegate = forA;
	b.delegate = forB;

	//A calls: the initiate goes out
	[a startWithLocalOfferSDP:offerSDP];
	check(@"Initiator wartet auf die Annahme", a.state == AIJingleCallStatePendingOutgoing, nil);
	check(@"session-initiate gesendet", [forA.sentElements count] == 1 &&
		  [[forA.sentElements firstObject] containsString:@"session-initiate"], nil);

	//The wire carries it to B
	[b handleRemoteJingleElement:[forA.sentElements firstObject]];
	check(@"Responder hat das Angebot als SDP", b.state == AIJingleCallStatePendingIncoming &&
		  [forB.lastRemoteSDP containsString:@"opus/48000/2"] &&
		  [forB.lastRemoteSDP containsString:@"a=fingerprint:sha-256"], nil);
	check(@"sid uebernommen", [b.sid isEqualToString:@"testsid"], b.sid);

	//B's media side builds its answer from the offer it saw
	AIJingleSession *answer = [AIJingleSession sessionFromSDP:forB.lastRemoteSDP];
	for (AIJingleContent *content in answer.contents) {
		content.dtlsSetup = @"active";
		content.iceUfrag = @"bUfrag";
		content.icePwd = @"bPwdbPwdbPwdbPwdbPwdbb";
	}

	//B already trickles a candidate before accepting; it must reach A only after the answer
	[b acceptWithLocalAnswerSDP:[answer sdpString]];
	NSString *acceptXML = [forB.sentElements lastObject];
	check(@"session-accept gesendet, Responder aktiv", b.state == AIJingleCallStateActive &&
		  [acceptXML containsString:@"session-accept"], nil);

	[b addLocalCandidateLine:@"candidate:1 1 udp 2122260223 192.168.0.50 40000 typ host generation 0" mid:@"0"];
	NSString *transportInfoFromB = [forB.sentElements lastObject];
	check(@"transport-info nennt Bs ICE-Zugangsdaten",
		  [transportInfoFromB containsString:@"transport-info"] &&
		  [transportInfoFromB containsString:@"ufrag=\"bUfrag\""] &&
		  ![transportInfoFromB containsString:@"<description"], transportInfoFromB);

	//The wire delivers out of order: candidate first, then the accept
	[a handleRemoteJingleElement:transportInfoFromB];
	BOOL queuedSilently = YES;
	for (NSString *event in forA.events)
		if ([event hasPrefix:@"candidate"]) queuedSilently = NO;
	check(@"Vorauseilender Kandidat wird zurueckgehalten", queuedSilently, [forA.events description]);

	[a handleRemoteJingleElement:acceptXML];
	check(@"Initiator aktiv, Antwort-SDP sagt active/bUfrag",
		  a.state == AIJingleCallStateActive &&
		  [forA.lastRemoteSDP containsString:@"a=setup:active"] &&
		  [forA.lastRemoteSDP containsString:@"a=ice-ufrag:bUfrag"], nil);

	NSInteger answerIndex = [forA.events indexOfObject:@"remote-answer"];
	NSInteger candidateIndex = -1;
	for (NSUInteger index = 0; index < [forA.events count]; index++)
		if ([forA.events[index] hasPrefix:@"candidate 0 "]) candidateIndex = index;
	check(@"Kandidat kommt nach der Antwort frei, mit mid",
		  answerIndex != NSNotFound && candidateIndex > answerIndex &&
		  [forA.events[candidateIndex] containsString:@"192.168.0.50 40000"], [forA.events description]);

	//A candidate the other way arrives at once: B's description already stands
	[a addLocalCandidateLine:@"candidate:2 1 udp 2122260223 192.168.0.60 40002 typ host generation 0" mid:@"1"];
	[b handleRemoteJingleElement:[forA.sentElements lastObject]];
	check(@"Rueckweg-Kandidat sofort da, mit mid 1",
		  [[forB.events lastObject] hasPrefix:@"candidate 1 "] &&
		  [[forB.events lastObject] containsString:@"40002"], [forB.events lastObject]);

	/* The wire speaks in single quotes. Everything above was fed our own
	 * double-quoted spelling, and that is exactly how a machine that read its
	 * attributes by searching text passed every test here while answering
	 * nothing a real peer ever sent. */
	Recorder *forC = [Recorder new], *forD = [Recorder new];
	AIJingleSessionMachine *c = [[AIJingleSessionMachine alloc] initAsInitiatorFrom:@"a@x/1" to:@"b@x/2" sid:@"wiresid"];
	AIJingleSessionMachine *d = [[AIJingleSessionMachine alloc] initAsResponderFrom:@"b@x/2" to:@"a@x/1" sid:@"wiresid"];
	c.delegate = forC; d.delegate = forD;
	[c startWithLocalOfferSDP:offerSDP];

	NSString *(^asWireSpelling)(NSString *) = ^(NSString *xml) {
		return [xml stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
	};

	[d handleRemoteJingleElement:asWireSpelling([forC.sentElements firstObject])];
	check(@"Einfache Anfuehrungszeichen: initiate verstanden",
		  d.state == AIJingleCallStatePendingIncoming && [d.sid isEqualToString:@"wiresid"],
		  [NSString stringWithFormat:@"state=%ld sid=%@", (long)d.state, d.sid]);

	AIJingleSession *wireAnswer = [AIJingleSession sessionFromSDP:forD.lastRemoteSDP];
	for (AIJingleContent *content in wireAnswer.contents) content.dtlsSetup = @"active";
	[d acceptWithLocalAnswerSDP:[wireAnswer sdpString]];
	[c handleRemoteJingleElement:asWireSpelling([forD.sentElements lastObject])];
	check(@"Einfache Anfuehrungszeichen: accept verstanden", c.state == AIJingleCallStateActive, nil);

	[c handleRemoteJingleElement:@"<jingle xmlns='urn:xmpp:jingle:1' action='session-terminate' sid='wiresid'>"
						  @"<reason><busy/></reason></jingle>"];
	check(@"Einfache Anfuehrungszeichen: terminate samt Grund verstanden",
		  c.state == AIJingleCallStateEnded && [[forC.events lastObject] isEqualToString:@"ended busy remote"],
		  [forC.events lastObject]);

	//A hangs up; B learns why
	[a hangUpWithReason:@"success"];
	check(@"Aufleger endet lokal", a.state == AIJingleCallStateEnded &&
		  [[forA.events lastObject] isEqualToString:@"ended success local"], [forA.events lastObject]);
	[b handleRemoteJingleElement:[forA.sentElements lastObject]];
	check(@"Gegenseite endet mit Grund", b.state == AIJingleCallStateEnded &&
		  [[forB.events lastObject] isEqualToString:@"ended success remote"], [forB.events lastObject]);

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
