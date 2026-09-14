/* Loopback probe for the XMPP calls spike: two RTCPeerConnections in one
 * process, synthetic video frames instead of a camera (no TCC prompts),
 * SDP and ICE exchanged directly. Proves the WebRTC.xcframework works on
 * this machine: ICE connects, DTLS-SRTP establishes, frames arrive. */
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <WebRTC/WebRTC.h>

@interface FrameCounter : NSObject <RTCVideoRenderer>
@property (atomic) NSInteger frames;
@end
@implementation FrameCounter
- (void)setSize:(CGSize)size {}
- (void)renderFrame:(RTCVideoFrame *)frame { self.frames++; }
@end

@interface Peer : NSObject <RTCPeerConnectionDelegate>
@property (strong) RTCPeerConnection *pc;
@property (weak) Peer *other;
@property (copy) NSString *name;
@property (strong) FrameCounter *counter;
@property (atomic) BOOL connected;
@end
@implementation Peer
- (void)peerConnection:(RTCPeerConnection *)pc didGenerateIceCandidate:(RTCIceCandidate *)candidate {
	[self.other.pc addIceCandidate:candidate completionHandler:^(NSError *e) {
		if (e) printf("%s: candidate error %s\n", self.other.name.UTF8String, e.description.UTF8String);
	}];
}
- (void)peerConnection:(RTCPeerConnection *)pc didChangeIceConnectionState:(RTCIceConnectionState)newState {
	printf("%s: ICE state %ld\n", self.name.UTF8String, (long)newState);
	if (newState == RTCIceConnectionStateConnected || newState == RTCIceConnectionStateCompleted)
		self.connected = YES;
}
/* Trap, measured: attaching the renderer HERE, in the early transceiver
 * callback during SDP handling, yields zero rendered frames although the
 * decoder runs; attach to pc.receivers once the connection stands instead
 * (see the wait loop in main). */
- (void)peerConnection:(RTCPeerConnection *)pc didStartReceivingOnTransceiver:(RTCRtpTransceiver *)transceiver {
	if ([transceiver.receiver.track isKindOfClass:[RTCVideoTrack class]])
		printf("%s: video transceiver announced\n", self.name.UTF8String);
}
//Required no-ops
- (void)peerConnection:(RTCPeerConnection *)pc didChangeSignalingState:(RTCSignalingState)stateChanged {}
- (void)peerConnection:(RTCPeerConnection *)pc didAddStream:(RTCMediaStream *)stream {}
- (void)peerConnection:(RTCPeerConnection *)pc didRemoveStream:(RTCMediaStream *)stream {}
- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)pc {}
- (void)peerConnection:(RTCPeerConnection *)pc didChangeIceGatheringState:(RTCIceGatheringState)newState {}
- (void)peerConnection:(RTCPeerConnection *)pc didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates {}
- (void)peerConnection:(RTCPeerConnection *)pc didOpenDataChannel:(RTCDataChannel *)dataChannel {}
@end

static RTCVideoFrame *makeFrame(int64_t timestampNs, int shade)
{
	CVPixelBufferRef buffer = NULL;
	CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA,
						(__bridge CFDictionaryRef)@{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}}, &buffer);
	if (!buffer) return nil;
	CVPixelBufferLockBaseAddress(buffer, 0);
	memset(CVPixelBufferGetBaseAddress(buffer), shade,
		   CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer));
	CVPixelBufferUnlockBaseAddress(buffer, 0);
	RTCCVPixelBuffer *wrapped = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:buffer];
	RTCVideoFrame *frame = [[RTCVideoFrame alloc] initWithBuffer:wrapped
														rotation:RTCVideoRotation_0
													 timeStampNs:timestampNs];
	CVPixelBufferRelease(buffer);
	return frame;
}

int main(void) { @autoreleasepool {
	RTCPeerConnectionFactory *factory = [[RTCPeerConnectionFactory alloc]
		initWithEncoderFactory:[[RTCDefaultVideoEncoderFactory alloc] init]
				decoderFactory:[[RTCDefaultVideoDecoderFactory alloc] init]];

	RTCConfiguration *config = [[RTCConfiguration alloc] init];
	config.sdpSemantics = RTCSdpSemanticsUnifiedPlan;
	RTCMediaConstraints *none = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@{}
																	  optionalConstraints:@{}];

	Peer *caller = [Peer new]; caller.name = @"caller";
	Peer *callee = [Peer new]; callee.name = @"callee"; callee.counter = [FrameCounter new];
	caller.pc = [factory peerConnectionWithConfiguration:config constraints:none delegate:caller];
	callee.pc = [factory peerConnectionWithConfiguration:config constraints:none delegate:callee];
	caller.other = callee; callee.other = caller;

	RTCVideoSource *source = [factory videoSource];
	RTCVideoCapturer *capturer = [[RTCVideoCapturer alloc] initWithDelegate:source];
	RTCVideoTrack *track = [factory videoTrackWithSource:source trackId:@"video0"];
	[caller.pc addTrack:track streamIds:@[@"stream0"]];

	//Does the source deliver at all? Count what the local track sees, too
	FrameCounter *localCounter = [FrameCounter new];
	[track addRenderer:localCounter];

	//Feed synthetic frames at ~15 fps from a background queue
	dispatch_queue_t feed = dispatch_queue_create("frames", DISPATCH_QUEUE_SERIAL);
	__block BOOL feeding = YES;
	dispatch_async(feed, ^{
		int64_t ns = 0; int shade = 0;
		while (feeding) {
			RTCVideoFrame *frame = makeFrame(ns, shade++ & 0xFF);
			if (frame) [source capturer:capturer didCaptureVideoFrame:frame];
			ns += 66 * 1000000;
			usleep(66000);
		}
	});

	//Classic offer/answer dance, everything in-process
	[caller.pc offerForConstraints:none completionHandler:^(RTCSessionDescription *offer, NSError *e1) {
		[caller.pc setLocalDescription:offer completionHandler:^(NSError *e2) {
			[callee.pc setRemoteDescription:offer completionHandler:^(NSError *e3) {
				[callee.pc answerForConstraints:none completionHandler:^(RTCSessionDescription *answer, NSError *e4) {
					[callee.pc setLocalDescription:answer completionHandler:^(NSError *e5) {
						[caller.pc setRemoteDescription:answer completionHandler:^(NSError *e6) {
							printf("offer/answer exchanged (errors: %s)\n",
								   (e1||e2||e3||e4||e5||e6) ? "YES" : "none");
						}];
					}];
				}];
			}];
		}];
	}];

	//Give it up to 15 seconds; attach the renderer to the live receiver track
	//once the connection stands, instead of trusting the early delegate moment
	BOOL rendererAttached = NO;
	for (int i = 0; i < 150; i++) {
		[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
		if (!rendererAttached && callee.connected) {
			for (RTCRtpReceiver *receiver in callee.pc.receivers) {
				if ([receiver.track isKindOfClass:[RTCVideoTrack class]]) {
					printf("renderer haengt jetzt am Live-Track %s\n", receiver.track.trackId.UTF8String);
					[(RTCVideoTrack *)receiver.track addRenderer:callee.counter];
					rendererAttached = YES;
				}
			}
		}
		if (caller.connected && callee.connected && callee.counter.frames >= 30) break;
	}
	feeding = NO;

	__block NSString *senderStats = @"?";
	dispatch_semaphore_t statsDone = dispatch_semaphore_create(0);
	[caller.pc statisticsWithCompletionHandler:^(RTCStatisticsReport *report) {
		NSMutableString *out = [NSMutableString string];
		for (NSString *key in report.statistics) {
			RTCStatistics *stat = report.statistics[key];
			if ([stat.type isEqualToString:@"outbound-rtp"] || [stat.type isEqualToString:@"media-source"])
				[out appendFormat:@"%@: %@\n", stat.type, stat.values];
		}
		senderStats = out;
		dispatch_semaphore_signal(statsDone);
	}];
	dispatch_semaphore_wait(statsDone, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
	printf("Sender-Statistik:\n%s\n", senderStats.UTF8String);

	__block NSString *receiverStats = @"?";
	dispatch_semaphore_t rstatsDone = dispatch_semaphore_create(0);
	[callee.pc statisticsWithCompletionHandler:^(RTCStatisticsReport *report) {
		NSMutableString *out = [NSMutableString string];
		for (NSString *key in report.statistics) {
			RTCStatistics *stat = report.statistics[key];
			if ([stat.type isEqualToString:@"inbound-rtp"])
				[out appendFormat:@"%@: %@\n", stat.type, stat.values];
		}
		receiverStats = out;
		dispatch_semaphore_signal(rstatsDone);
	}];
	dispatch_semaphore_wait(rstatsDone, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
	printf("Empfaenger-Statistik:\n%s\n", receiverStats.UTF8String);
	printf("Lokal gesehene Frames: %ld\n", (long)localCounter.frames);

	printf("\nICE verbunden: caller=%s callee=%s\n",
		   caller.connected ? "JA" : "NEIN", callee.connected ? "JA" : "NEIN");
	printf("Empfangene Videoframes beim Callee: %ld\n", (long)callee.counter.frames);
	BOOL ok = caller.connected && callee.connected && callee.counter.frames > 0;
	printf("%s\n", ok ? "SPIKE BESTANDEN" : "SPIKE FEHLGESCHLAGEN");
	return ok ? 0 : 1;
} }
