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
@property (copy) NSString *endReason;
@property (atomic) BOOL endedLocally;
@property (atomic) NSInteger stanzas;
@end
@implementation Relay
- (void)callController:(AIJingleCallController *)controller sendJingleElement:(NSString *)jingleXML {
	self.stanzas++;
	AIJingleCallController *other = self.other;
	dispatch_async(dispatch_get_main_queue(), ^{
		[other handleRemoteJingleElement:jingleXML];
	});
}
- (void)callControllerConnected:(AIJingleCallController *)controller {
	printf("%s: verbunden\n", self.name.UTF8String);
	self.connected = YES;
}
- (void)callController:(AIJingleCallController *)controller endedWithReason:(NSString *)reason locally:(BOOL)locally {
	self.endReason = reason;
	self.endedLocally = locally;
}
@end

int main(void) { @autoreleasepool {
	Relay *forA = [Relay new]; forA.name = @"anrufer";
	Relay *forB = [Relay new]; forB.name = @"angerufener";

	AIJingleCallController *a = [[AIJingleCallController alloc] initAsInitiatorFrom:@"adium@localhost/a"
																				 to:@"peer@localhost/b"];
	AIJingleCallController *b = [[AIJingleCallController alloc] initAsResponderFrom:@"peer@localhost/b"
																				 to:@"adium@localhost/a"
																				 sid:@"testsid"];
	a.wantsAudio = NO; a.usesSyntheticVideo = YES; a.delegate = forA;
	b.wantsAudio = NO; b.usesSyntheticVideo = YES; b.delegate = forB;
	forA.other = b; forB.other = a;

	[a start];

	for (int i = 0; i < 200 && !(forA.connected && forB.connected); i++)
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	check(@"ICE beidseitig verbunden, nur ueber Jingle-Stanzas",
		  forA.connected && forB.connected,
		  [NSString stringWithFormat:@"a=%d b=%d stanzasA=%ld stanzasB=%ld",
		   forA.connected, forB.connected, (long)forA.stanzas, (long)forB.stanzas]);
	check(@"Es floss echtes Trickle (mehr als initiate und accept)",
		  forA.stanzas >= 2 && forB.stanzas >= 2, nil);

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
	check(@"Video dekodiert beim Angerufenen",
		  framesDecoded >= 15, [NSString stringWithFormat:@"framesDecoded=%ld", (long)framesDecoded]);

	//Hang up; the reason must arrive over the wire
	[a hangUpWithReason:@"success"];
	for (int i = 0; i < 50 && ![forB.endReason length]; i++)
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	check(@"Auflegen kommt drueben an", [forA.endReason isEqualToString:@"success"] && forA.endedLocally &&
		  [forB.endReason isEqualToString:@"success"] && !forB.endedLocally,
		  [NSString stringWithFormat:@"a=%@ b=%@", forA.endReason, forB.endReason]);

	printf("\n%s\n", failures ? "FEHLSCHLAEGE" : "ALLE PRUEFUNGEN BESTANDEN");
	return failures ? 1 : 0;
} }
