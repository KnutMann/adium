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
	/* Was in der ersten Stanza steht, kann die Gegenseite sofort benutzen. Was
	 * hinterhertroepfelt, legen manche Clients erst einmal in eine Schublade. */
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

	/* Wie ein echter Anruf: erst sammeln, waehrend es drueben klingelt, dann
	 * anbieten. Ohne diese Pause traegt die erste Stanza keine einzige Adresse. */
	[a prepare];
	[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
	[a start];

	for (int i = 0; i < 200 && !(forA.connected && forB.connected); i++)
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	check(@"ICE beidseitig verbunden, nur ueber Jingle-Stanzas",
		  forA.connected && forB.connected,
		  [NSString stringWithFormat:@"a=%d b=%d stanzasA=%ld stanzasB=%ld",
		   forA.connected, forB.connected, (long)forA.stanzas, (long)forB.stanzas]);
	/* The caller must hear the yes before the connection stands: the window says
	 * "ringing" until it does, and that lie lasted seconds in a real call. */
	check(@"Anrufer erfaehrt die Annahme vor der Verbindung",
		  forA.answeredBeforeConnected,
		  [NSString stringWithFormat:@"angenommen=%d", forA.answered]);
	/* Vorgesammelt heisst, dass die Gegenseite schon aus dem ersten Satz weiss, wo
	 * wir wohnen, statt auf ein transport-info warten zu muessen. Ein Client, der
	 * Nachzuegler bis zum Ende seiner eigenen Antwort in eine Schublade legt, und
	 * Conversations tut genau das, kann damit sofort loslegen. */
	check(@"Das session-initiate traegt schon Adressen",
		  forA.addressesInTheFirstStanza > 0,
		  [NSString stringWithFormat:@"Adressen=%ld", (long)forA.addressesInTheFirstStanza]);
	check(@"Auch die Antwort traegt schon Adressen",
		  forB.addressesInTheFirstStanza > 0,
		  [NSString stringWithFormat:@"Adressen=%ld", (long)forB.addressesInTheFirstStanza]);
	/* Nachzuegler tröpfeln weiterhin, nur hat dieser Lauf keine: hier ist alles nach
	 * 300 ms Vorsammeln beisammen. Der Weg selbst wird in jingle-session-test
	 * geprueft, wo die Maschine einzeln an ihm entlanggefuehrt wird. */
	check(@"Keine TCP-Adressen angeboten, die ice-udp nicht traegt",
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
	check(@"Video dekodiert beim Angerufenen",
		  framesDecoded >= 15, [NSString stringWithFormat:@"framesDecoded=%ld", (long)framesDecoded]);

	/* Stummschalten muss drueben ankommen, sonst sieht die Gegenseite nur jemanden,
	 * der ploetzlich nichts mehr sagt, und sucht den Fehler bei sich. */
	a.cameraOff = YES;
	for (int i = 0; i < 30 && !b.peerCameraOff; i++)
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	check(@"Kamera aus kommt drueben an", b.peerCameraOff,
		  [NSString stringWithFormat:@"drueben=%d hier=%d", b.peerCameraOff, a.cameraOff]);
	check(@"und der eigene Track ist wirklich aus", !a.localVideoTrack.isEnabled, nil);

	a.cameraOff = NO;
	for (int i = 0; i < 30 && b.peerCameraOff; i++)
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	check(@"Kamera wieder an kommt auch an", !b.peerCameraOff, nil);

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
