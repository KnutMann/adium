/* The whole stack in one process: two call controllers, each with a real
 * RTCPeerConnection, talk to each other purely through the Jingle strings
 * their machines emit. Synthetic video, no audio, so no device and no
 * permission prompt is touched. Proves that engine, machine and controller
 * together carry a call: ICE connects over trickled Jingle candidates,
 * frames arrive, the hangup travels. */
#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>
#import "AIJingleCallController.h"

static int failures = 0;
static void check(NSString *name, BOOL ok, NSString *detail)
{
	printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String,
		   (!ok && detail) ? "  " : "", (!ok && detail) ? detail.UTF8String : "");
	if (!ok) failures++;
}

@interface Relay : NSObject <AIJingleCallControllerDelegate>
@property (weak) AIJingleCallController *other;
@property (copy) NSString *name;
@property (atomic) BOOL connected;
@property (atomic) BOOL answered;
@property (atomic) BOOL answeredBeforeConnected;
@property (copy) NSString *endReason;
@property (atomic) BOOL endedLocally;
@property (atomic) NSInteger stanzas;
@property (atomic) NSInteger tcpCandidatesOffered;
@property (atomic) NSInteger addressesInTheFirstStanza;
@end
@implementation Relay
- (void)callController:(AIJingleCallController *)controller sendJingleElement:(NSString *)jingleXML {
	self.stanzas++;
	/* What stands in the first stanza the other side can use at once. What trickles
	 * in afterwards, some clients put in a drawer for the time being. */
	if (self.stanzas == 1)
		for (NSRange rest = NSMakeRange(0, jingleXML.length);;) {
			NSRange hit = [jingleXML rangeOfString:@"<candidate" options:0 range:rest];
			if (hit.location == NSNotFound) break;
			self.addressesInTheFirstStanza++;
			rest = NSMakeRange(NSMaxRange(hit), jingleXML.length - NSMaxRange(hit));
		}
	/* Jingle's ice-udp carries UDP and nothing else. A TCP address in here is one
	 * the other end throws away unread, and it costs a stanza of its own. */
	if ([jingleXML rangeOfString:@"protocol=\"tcp\""].location != NSNotFound ||
		[jingleXML rangeOfString:@"protocol='tcp'"].location != NSNotFound)
		self.tcpCandidatesOffered++;
	AIJingleCallController *other = self.other;
	dispatch_async(dispatch_get_main_queue(), ^{
		[other handleRemoteJingleElement:jingleXML];
	});
}
- (void)callControllerWasAnswered:(AIJingleCallController *)controller {
	self.answered = YES;
	if (!self.connected)
		self.answeredBeforeConnected = YES;
}
- (void)callControllerConnected:(AIJingleCallController *)controller {
	printf("%s: connected\n", self.name.UTF8String);
	self.connected = YES;
}
- (void)callController:(AIJingleCallController *)controller endedWithReason:(NSString *)reason locally:(BOOL)locally {
	self.endReason = reason;
	self.endedLocally = locally;
}
@end

int main(void) { @autoreleasepool {
	Relay *forA = [Relay new]; forA.name = @"caller";
	Relay *forB = [Relay new]; forB.name = @"callee";

	AIJingleCallController *a = [[AIJingleCallController alloc] initAsInitiatorFrom:@"adium@localhost/a"
																				 to:@"peer@localhost/b"];
	AIJingleCallController *b = [[AIJingleCallController alloc] initAsResponderFrom:@"peer@localhost/b"
																				 to:@"adium@localhost/a"
																				 sid:@"testsid"];
	a.wantsAudio = NO; a.usesSyntheticVideo = YES; a.delegate = forA;
	b.wantsAudio = NO; b.usesSyntheticVideo = YES; b.delegate = forB;
	forA.other = b; forB.other = a;

	/* As in a real call: gather first, while it rings at the other end, then offer.
	 * Without that pause the first stanza carries not one single address. */
	[a prepare];
	[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
	[a start];

	for (int i = 0; i < 200 && !(forA.connected && forB.connected); i++)
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	check(@"ICE connected on both sides, over Jingle stanzas alone",
		  forA.connected && forB.connected,
		  [NSString stringWithFormat:@"a=%d b=%d stanzasA=%ld stanzasB=%ld",
		   forA.connected, forB.connected, (long)forA.stanzas, (long)forB.stanzas]);
	/* The caller must hear the yes before the connection stands: the window says
	 * "ringing" until it does, and that lie lasted seconds in a real call. */
	check(@"The caller learns of the answer before the connection",
		  forA.answeredBeforeConnected,
		  [NSString stringWithFormat:@"answered=%d", forA.answered]);
	/* Gathering in advance means the other side already knows from the first
	 * sentence where we live, instead of having to wait for a transport-info. A
	 * client that puts latecomers in a drawer until its own answer is finished, and
	 * Conversations does exactly that, can get going straight away. */
	check(@"The session-initiate already carries addresses",
		  forA.addressesInTheFirstStanza > 0,
		  [NSString stringWithFormat:@"addresses=%ld", (long)forA.addressesInTheFirstStanza]);
	check(@"The answer already carries addresses too",
		  forB.addressesInTheFirstStanza > 0,
		  [NSString stringWithFormat:@"addresses=%ld", (long)forB.addressesInTheFirstStanza]);
	/* Latecomers still trickle in, this run just has none: everything is together
	 * here after 300 ms of gathering. The path itself is checked in
	 * jingle-session-test, where the machine is walked along it on its own. */
	check(@"No TCP addresses offered that ice-udp does not carry",
		  forA.tcpCandidatesOffered == 0 && forB.tcpCandidatesOffered == 0,
		  [NSString stringWithFormat:@"a=%ld b=%ld",
		   (long)forA.tcpCandidatesOffered, (long)forB.tcpCandidatesOffered]);

	//Frames must arrive at the callee's decoder
	__block NSInteger framesDecoded = 0;
	for (int i = 0; i < 100 && framesDecoded < 15; i++) {
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		[b.peerConnection statisticsWithCompletionHandler:^(RTCStatisticsReport *report) {
			for (NSString *key in report.statistics) {
				RTCStatistics *stat = report.statistics[key];
				if ([stat.type isEqualToString:@"inbound-rtp"]) {
					NSNumber *frames = stat.values[@"framesDecoded"];
					if (frames) framesDecoded = [frames integerValue];
				}
			}
			dispatch_semaphore_signal(done);
		}];
		dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
	}
	check(@"Video decoded at the callee",
		  framesDecoded >= 15, [NSString stringWithFormat:@"framesDecoded=%ld", (long)framesDecoded]);

	/* Muting has to arrive at the other end, or the other side only sees somebody
	 * who has suddenly gone quiet, and looks for the fault at their end. */
	a.cameraOff = YES;
	for (int i = 0; i < 30 && !b.peerCameraOff; i++)
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	check(@"Camera off arrives at the other end", b.peerCameraOff,
		  [NSString stringWithFormat:@"there=%d here=%d", b.peerCameraOff, a.cameraOff]);
	check(@"and our own track really is off", !a.localVideoTrack.isEnabled, nil);

	a.cameraOff = NO;
	for (int i = 0; i < 30 && b.peerCameraOff; i++)
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	check(@"Camera back on arrives too", !b.peerCameraOff, nil);

	//Hang up; the reason must arrive over the wire
	[a hangUpWithReason:@"success"];
	for (int i = 0; i < 50 && ![forB.endReason length]; i++)
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	check(@"The hangup arrives at the other end", [forA.endReason isEqualToString:@"success"] && forA.endedLocally &&
		  [forB.endReason isEqualToString:@"success"] && !forB.endedLocally,
		  [NSString stringWithFormat:@"a=%@ b=%@", forA.endReason, forB.endReason]);

	printf("\n%s\n", failures ? "FAILURES" : "ALL CHECKS PASSED");
	return failures ? 1 : 0;
} }
