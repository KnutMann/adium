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

#import "AIJingleCallController.h"

#import <Adium/ESDebugAILog.h>
#import <CoreVideo/CoreVideo.h>
#import <WebRTC/WebRTC.h>

@interface AIJingleCallController () <RTCPeerConnectionDelegate>
@property (nonatomic, strong) AIJingleSessionMachine *machine;
@property (nonatomic, strong) RTCPeerConnection *peerConnection;
@property (nonatomic, strong) RTCVideoTrack *localVideoTrack;
@end

@implementation AIJingleCallController {
	RTCVideoSource *syntheticSource;
	RTCVideoCapturer *syntheticCapturer;
	dispatch_source_t syntheticTimer;
	RTCCameraVideoCapturer *cameraCapturer;
	BOOL announcedConnected;
	NSMutableSet<NSString *> *offeredTrackIds;
	NSDate *startedAt;					//when this call began, for the timeline below
	NSMutableSet<NSString *> *milestonesSeen;
	BOOL closed;
	NSString *lastPairSnapshot;		//what the pairs looked like while they were still being tried
}

+ (RTCPeerConnectionFactory *)factory
{
	static RTCPeerConnectionFactory *factory = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		factory = [[RTCPeerConnectionFactory alloc]
			initWithEncoderFactory:[[RTCDefaultVideoEncoderFactory alloc] init]
					decoderFactory:[[RTCDefaultVideoDecoderFactory alloc] init]];
	});
	return factory;
}

- (id)initAsInitiatorFrom:(NSString *)localJid to:(NSString *)peerJid
{
	if ((self = [super init])) {
		_machine = [[AIJingleSessionMachine alloc] initAsInitiatorFrom:localJid to:peerJid sid:nil];
		_machine.delegate = self;
		_wantsAudio = YES;
		offeredTrackIds = [NSMutableSet set];
		milestonesSeen = [NSMutableSet set];
		startedAt = [NSDate date];
	}
	return self;
}

- (id)initAsResponderFrom:(NSString *)localJid to:(NSString *)peerJid sid:(NSString *)sid
{
	if ((self = [super init])) {
		_machine = [[AIJingleSessionMachine alloc] initAsResponderFrom:localJid to:peerJid sid:sid];
		_machine.delegate = self;
		_wantsAudio = YES;
		offeredTrackIds = [NSMutableSet set];
		milestonesSeen = [NSMutableSet set];
		startedAt = [NSDate date];
	}
	return self;
}

//The media half ---------------------------------------------------------------------------------
#pragma mark The media half

- (void)ensurePeerConnection
{
	if (self.peerConnection)
		return;

	RTCConfiguration *configuration = [[RTCConfiguration alloc] init];
	configuration.sdpSemantics = RTCSdpSemanticsUnifiedPlan;

	//Whatever XEP-0215 offered
	NSMutableArray<RTCIceServer *> *iceServers = [NSMutableArray array];
	for (NSDictionary *entry in self.iceServerDictionaries) {
		NSString *url = entry[@"urls"];
		if (![url length])
			continue;
		[iceServers addObject:[[RTCIceServer alloc] initWithURLStrings:@[url]
															  username:(entry[@"username"] ?: @"")
															credential:(entry[@"credential"] ?: @"")]];
	}

	/* A public address of our own, or nobody behind a router can reach us.
	 *
	 * Measured against a phone: this side offered two private addresses and
	 * nothing else, the other side offered its own, a public one and a relay,
	 * and not one pair could carry anything. A peer's relay refuses packets
	 * from an address it was never told about, and a private address is not one
	 * anybody outside this flat can use, so the call had nowhere to go. One
	 * question to a STUN server answers what this machine looks like from
	 * outside, and that is the address every other client offers as a matter of
	 * course.
	 *
	 * These are added ALONGSIDE whatever the account's own host named, never
	 * instead of them, and that distinction was the whole bug: the host in the
	 * measurement above did name a server, and that server answers nothing at
	 * all, which left every call blind while looking perfectly configured. A
	 * server that does answer costs a question nobody misses; one that does not
	 * must not be the only one asked. Asking tells its operator this machine is
	 * placing a call, no more, and the list can be replaced with the
	 * AIJingleSTUNServers default. */
	NSArray *fallback = [[NSUserDefaults standardUserDefaults] arrayForKey:@"AIJingleSTUNServers"];

	if (![fallback count])
		fallback = @[@"stun:stun.conversations.im:3478", @"stun:stun.l.google.com:19302"];

	for (NSString *url in fallback)
		[iceServers addObject:[[RTCIceServer alloc] initWithURLStrings:@[url]]];

	AILogWithSignature(@"call %@ uses %lu ICE servers", self.machine.sid, (unsigned long)[iceServers count]);
	configuration.iceServers = iceServers;

	RTCMediaConstraints *none = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@{}
																	  optionalConstraints:@{}];
	self.peerConnection = [[AIJingleCallController factory] peerConnectionWithConfiguration:configuration
																				constraints:none
																				   delegate:self];

	if (self.wantsAudio) {
		RTCAudioSource *audioSource = [[AIJingleCallController factory] audioSourceWithConstraints:none];
		RTCAudioTrack *audioTrack = [[AIJingleCallController factory] audioTrackWithSource:audioSource
																				   trackId:@"audio0"];
		[self.peerConnection addTrack:audioTrack streamIds:@[@"adium"]];
	}

	if (self.usesSyntheticVideo) {
		syntheticSource = [[AIJingleCallController factory] videoSource];
		syntheticCapturer = [[RTCVideoCapturer alloc] initWithDelegate:syntheticSource];
		RTCVideoTrack *videoTrack = [[AIJingleCallController factory] videoTrackWithSource:syntheticSource
																				   trackId:@"video0"];
		[self.peerConnection addTrack:videoTrack streamIds:@[@"adium"]];
		[self startSyntheticFrames];
	} else if (self.wantsVideo) {
		RTCVideoSource *cameraSource = [[AIJingleCallController factory] videoSource];
		cameraCapturer = [[RTCCameraVideoCapturer alloc] initWithDelegate:cameraSource];
		self.localVideoTrack = [[AIJingleCallController factory] videoTrackWithSource:cameraSource
																			  trackId:@"video0"];
		[self.peerConnection addTrack:self.localVideoTrack streamIds:@[@"adium"]];
		[self startCamera];
	}
}

/*!
 * @brief Start the default camera at a modest format
 *
 * 640x480 around 30 frames is what a chat window needs; the closest format the
 * device offers wins. macOS asks the person for the camera the first time.
 */
- (void)startCamera
{
	AVCaptureDevice *device = [[RTCCameraVideoCapturer captureDevices] firstObject];
	if (!device)
		return;

	AVCaptureDeviceFormat *chosenFormat = nil;
	int32_t chosenDelta = INT32_MAX;
	for (AVCaptureDeviceFormat *format in [RTCCameraVideoCapturer supportedFormatsForDevice:device]) {
		CMVideoDimensions size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
		int32_t delta = abs(size.width - 640) + abs(size.height - 480);
		if (delta < chosenDelta) {
			chosenDelta = delta;
			chosenFormat = format;
		}
	}
	if (!chosenFormat)
		return;

	Float64 fps = 30;
	for (AVFrameRateRange *range in chosenFormat.videoSupportedFrameRateRanges)
		fps = MIN(30, MAX(fps, range.maxFrameRate));

	[cameraCapturer startCaptureWithDevice:device format:chosenFormat fps:(NSInteger)fps];
	[self noteMilestone:@"camera asked to start"];
}

- (void)startSyntheticFrames
{
	dispatch_queue_t queue = dispatch_queue_create("adium.jingle.synthetic", DISPATCH_QUEUE_SERIAL);
	syntheticTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
	dispatch_source_set_timer(syntheticTimer, DISPATCH_TIME_NOW, 66 * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);

	__block int64_t timestamp = 0;
	__weak AIJingleCallController *weakSelf = self;
	dispatch_source_set_event_handler(syntheticTimer, ^{
		AIJingleCallController *self = weakSelf;
		if (!self)
			return;

		CVPixelBufferRef buffer = NULL;
		CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA,
							(__bridge CFDictionaryRef)@{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}}, &buffer);
		if (!buffer)
			return;
		CVPixelBufferLockBaseAddress(buffer, 0);
		memset(CVPixelBufferGetBaseAddress(buffer), (int)((timestamp / 66000000) & 0xFF),
			   CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer));
		CVPixelBufferUnlockBaseAddress(buffer, 0);

		RTCCVPixelBuffer *wrapped = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:buffer];
		RTCVideoFrame *frame = [[RTCVideoFrame alloc] initWithBuffer:wrapped
															rotation:RTCVideoRotation_0
														 timeStampNs:timestamp];
		CVPixelBufferRelease(buffer);
		[self->syntheticSource capturer:self->syntheticCapturer didCaptureVideoFrame:frame];
		timestamp += 66 * 1000000;
	});
	dispatch_resume(syntheticTimer);
}

- (void)close
{
	if (closed)
		return;
	closed = YES;

	if (syntheticTimer) {
		dispatch_source_cancel(syntheticTimer);
		syntheticTimer = nil;
	}
	[cameraCapturer stopCapture];
	cameraCapturer = nil;
	[self.peerConnection close];
}

//Driving ----------------------------------------------------------------------------------------
#pragma mark Driving

- (void)start
{
	[self ensurePeerConnection];

	RTCMediaConstraints *none = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@{}
																	  optionalConstraints:@{}];
	__weak AIJingleCallController *weakSelf = self;
	[self.peerConnection offerForConstraints:none completionHandler:^(RTCSessionDescription *offer, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			AIJingleCallController *self = weakSelf;
			if (!self)
				return;
			if (!offer) {
				[self failWith:@"failed-application"];
				return;
			}
			[self.peerConnection setLocalDescription:offer completionHandler:^(NSError *localError) {
				dispatch_async(dispatch_get_main_queue(), ^{
					if (localError)
						[weakSelf failWith:@"failed-application"];
					else
						[weakSelf.machine startWithLocalOfferSDP:offer.sdp];
				});
			}];
		});
	}];
}

- (void)handleRemoteJingleElement:(NSString *)jingleXML
{
	[self.machine handleRemoteJingleElement:jingleXML];
}

- (void)hangUpWithReason:(NSString *)reason
{
	[self.machine hangUpWithReason:reason];
}

- (void)failWith:(NSString *)reason
{
	[self.machine hangUpWithReason:reason];
}

//What the machine asks --------------------------------------------------------------------------
#pragma mark What the machine asks

- (void)machine:(AIJingleSessionMachine *)machine sendJingleElement:(NSString *)jingleXML
{
	[self.delegate callController:self sendJingleElement:jingleXML];
}

- (void)machine:(AIJingleSessionMachine *)machine applyRemoteSDP:(NSString *)sdp isOffer:(BOOL)isOffer
{
	[self ensurePeerConnection];

	RTCSessionDescription *description =
		[[RTCSessionDescription alloc] initWithType:(isOffer ? RTCSdpTypeOffer : RTCSdpTypeAnswer)
												sdp:sdp];
	__weak AIJingleCallController *weakSelf = self;
	[self.peerConnection setRemoteDescription:description completionHandler:^(NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			AIJingleCallController *self = weakSelf;
			if (!self)
				return;
			if (error) {
				[self failWith:@"failed-application"];
				return;
			}

			/* The peer's tracks exist the moment its description is applied, long
			 * before ICE finishes, and a renderer attached now shows the very first
			 * frame that decodes instead of the first one after ten seconds. */
			[self offerRemoteVideoTrackWithTriesLeft:120];

			/* An answer is somebody picking up, and whoever is watching a window
			 * should be told now rather than when the connection finally stands,
			 * which is seconds later and reads as a phone that rings too long. */
			if (!isOffer)
				[self.delegate callControllerWasAnswered:self];

			if (!isOffer)
				return;	//the answer needs nothing more; ICE takes it from here

			//An offer wants our answer: create, set, and hand it to the machine to say
			RTCMediaConstraints *none = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@{}
																			  optionalConstraints:@{}];
			[self.peerConnection answerForConstraints:none
									completionHandler:^(RTCSessionDescription *answer, NSError *answerError) {
				dispatch_async(dispatch_get_main_queue(), ^{
					if (!answer) {
						[weakSelf failWith:@"failed-application"];
						return;
					}
					[weakSelf.peerConnection setLocalDescription:answer completionHandler:^(NSError *localError) {
						dispatch_async(dispatch_get_main_queue(), ^{
							if (localError)
								[weakSelf failWith:@"failed-application"];
							else
								[weakSelf.machine acceptWithLocalAnswerSDP:answer.sdp];
						});
					}];
				});
			}];
		});
	}];
}

- (void)machine:(AIJingleSessionMachine *)machine addRemoteCandidateLine:(NSString *)line mid:(NSString *)mid
{
	AILogWithSignature(@"remote candidate (%@): %@", mid, line);

	RTCIceCandidate *candidate = [[RTCIceCandidate alloc] initWithSdp:line
														sdpMLineIndex:0
															   sdpMid:mid];
	[self.peerConnection addIceCandidate:candidate completionHandler:^(NSError *error) {
		//A candidate that does not fit is no reason to end a call, but it is worth saying
		if (error)
			AILogWithSignature(@"remote candidate refused (%@): %@", mid, error);
	}];
}

- (void)machine:(AIJingleSessionMachine *)machine endedWithReason:(NSString *)reason locally:(BOOL)locally
{
	[self close];
	[self.delegate callController:self endedWithReason:reason locally:locally];
}

//What the connection says -----------------------------------------------------------------------
#pragma mark What the connection says

- (void)peerConnection:(RTCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate
{
	AILogWithSignature(@"local candidate (%@): %@", candidate.sdpMid, candidate.sdp);
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.machine addLocalCandidateLine:candidate.sdp mid:(candidate.sdpMid ?: @"0")];
	});
}

static NSString *nameOfIceState(RTCIceConnectionState state)
{
	switch (state) {
		case RTCIceConnectionStateNew:			return @"new";
		case RTCIceConnectionStateChecking:		return @"checking";
		case RTCIceConnectionStateConnected:	return @"connected";
		case RTCIceConnectionStateCompleted:	return @"completed";
		case RTCIceConnectionStateFailed:		return @"failed";
		case RTCIceConnectionStateDisconnected:	return @"disconnected";
		case RTCIceConnectionStateClosed:		return @"closed";
		default:								return @"?";
	}
}

/*!
 * @brief Say what the connection tried, once it has given up
 *
 * A call that fails to connect says nothing by itself; the pairs it checked do.
 * Each one names the two addresses, what came back, and how far it got.
 */
/*! @brief Keep a picture of the pairs, taken every second while the checking lasts */
- (void)samplePairsWhileChecking
{
	if (closed || self.peerConnection.iceConnectionState != RTCIceConnectionStateChecking)
		return;

	[self describePairsInto:^(NSString *description) {
		if ([description length])
			self->lastPairSnapshot = description;

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
					   dispatch_get_main_queue(), ^{
			[self samplePairsWhileChecking];
		});
	}];
}

- (void)describePairsInto:(void (^)(NSString *))afterwards
{
	[self.peerConnection statisticsWithCompletionHandler:^(RTCStatisticsReport *report) {
		NSMutableArray *lines = [NSMutableArray array];
		NSMutableDictionary *candidates = [NSMutableDictionary dictionary];

		for (NSString *key in report.statistics) {
			RTCStatistics *stat = report.statistics[key];
			if ([stat.type isEqualToString:@"local-candidate"] || [stat.type isEqualToString:@"remote-candidate"])
				candidates[stat.id] = stat.values;
		}
		for (NSString *key in report.statistics) {
			RTCStatistics *stat = report.statistics[key];
			if (![stat.type isEqualToString:@"candidate-pair"])
				continue;

			NSDictionary *local = candidates[stat.values[@"localCandidateId"]];
			NSDictionary *remote = candidates[stat.values[@"remoteCandidateId"]];
			[lines addObject:[NSString stringWithFormat:@"%@ %@:%@ (%@) -> %@:%@ (%@) sent=%@ recv=%@",
				stat.values[@"state"] ?: @"?",
				local[@"address"] ?: @"?", local[@"port"] ?: @"?", local[@"candidateType"] ?: @"?",
				remote[@"address"] ?: @"?", remote[@"port"] ?: @"?", remote[@"candidateType"] ?: @"?",
				stat.values[@"requestsSent"] ?: @0, stat.values[@"responsesReceived"] ?: @0]];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			afterwards([lines componentsJoinedByString:@"\n"]);
		});
	}];
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState
{
	AILogWithSignature(@"ICE %@ for call %@", nameOfIceState(newState), self.machine.sid);

	/* Sample while it still tries: a connection that has given up has pruned its
	 * pairs, and asking then reads exactly like a call that never tried one. */
	if (newState == RTCIceConnectionStateChecking)
		[self samplePairsWhileChecking];

	dispatch_async(dispatch_get_main_queue(), ^{
		if ((newState == RTCIceConnectionStateConnected || newState == RTCIceConnectionStateCompleted) &&
			!self->announcedConnected) {
			self->announcedConnected = YES;
			[self noteMilestone:@"ICE connected"];
			[self.delegate callControllerConnected:self];

			/* The peer's video track, if any, from the live receivers. Attaching a
			 * renderer earlier, in the transceiver callback, draws nothing; measured
			 * in the loopback spike and written down there. */
			[self offerRemoteVideoTrackWithTriesLeft:90];
			[self logMediaFlowWithTriesLeft:10];
			[self watchForFirstFramesWithTriesLeft:120];
		}
		if (newState == RTCIceConnectionStateFailed) {
			/* Measure before giving up: ending the call closes the connection, and a
			 * closed connection reports no pairs at all, which reads as if none were
			 * ever tried. */
			AILogWithSignature(@"ICE gave up; last seen pairs:\n%@",
							   ([lastPairSnapshot length] ? lastPairSnapshot : @"(keine)"));
			[self failWith:@"connectivity-error"];
		}
	});
}

/*!
 * @brief Hand the peer's video to whoever draws it, once there is one
 *
 * A receiver does not always carry its track yet, so this looks again for a
 * while rather than once. It may look as early as it likes: the loopback spike
 * once concluded that a renderer attached early draws nothing, and that was a
 * misreading of the very fault fixed in the window controller, where the track
 * wrapper was let go and took the renderer with it. Early is now simply early.
 */
- (void)offerRemoteVideoTrackWithTriesLeft:(NSInteger)triesLeft
{
	if (closed || triesLeft <= 0 || ![self.delegate respondsToSelector:@selector(callController:hasRemoteVideoTrack:)])
		return;

	NSMutableArray *kinds = [NSMutableArray array];
	NSMutableArray<RTCVideoTrack *> *videos = [NSMutableArray array];

	for (RTCRtpReceiver *receiver in self.peerConnection.receivers) {
		[kinds addObject:(receiver.track.kind ?: @"(none)")];
		if ([receiver.track isKindOfClass:[RTCVideoTrack class]])
			[videos addObject:(RTCVideoTrack *)receiver.track];
	}

	if ([videos count]) {
		/* Every one of them, and every one only once: which receiver actually
		 * carries the pictures is not a thing worth guessing at, and a renderer
		 * on a silent track costs nothing. */
		BOOL handedOverAny = NO;

		for (RTCVideoTrack *video in videos) {
			if ([offeredTrackIds containsObject:video.trackId])
				continue;
			[offeredTrackIds addObject:video.trackId];
			handedOverAny = YES;

			AILogWithSignature(@"remote video track %@ handed over (receivers: %@)",
							   video.trackId, [kinds componentsJoinedByString:@", "]);
			[self.delegate callController:self hasRemoteVideoTrack:video];
		}

		/* Keep looking a little longer even after the first one: a peer that adds
		 * its camera later brings a track nobody has seen yet. */
		if (handedOverAny && triesLeft > 20)
			triesLeft = 20;
	}

	//Quietly, once a second; saying so every time would fill the log for a minute
	if ((triesLeft % 10) == 0)
		AILogWithSignature(@"no remote video track yet (receivers: %@), looking again",
						   [kinds componentsJoinedByString:@", "]);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		[self offerRemoteVideoTrackWithTriesLeft:(triesLeft - 1)];
	});
}

/*! @brief Say how long after the call began something first happened */
- (void)noteMilestone:(NSString *)what
{
	if ([milestonesSeen containsObject:what])
		return;
	[milestonesSeen addObject:what];

	AILogWithSignature(@"timeline %+.2fs: %@", -[startedAt timeIntervalSinceNow], what);
}

/*! @brief The same, for whoever draws the pictures */
- (void)noteMilestoneFromView:(NSString *)what
{
	[self noteMilestone:what];
}

/*!
 * @brief Watch closely for the moments a person notices
 *
 * When the first picture of ours goes out and when the first of theirs comes
 * in are the two numbers a call is judged by, so they are taken at a quarter of
 * a second rather than sampled every few seconds.
 */
- (void)watchForFirstFramesWithTriesLeft:(NSInteger)triesLeft
{
	if (closed || triesLeft <= 0)
		return;

	[self.peerConnection statisticsWithCompletionHandler:^(RTCStatisticsReport *report) {
		for (NSString *key in report.statistics) {
			RTCStatistics *stat = report.statistics[key];
			NSDictionary *values = stat.values;
			BOOL video = [values[@"kind"] isEqualToString:@"video"];

			if (!video)
				continue;

			if ([stat.type isEqualToString:@"outbound-rtp"]) {
				if ([values[@"framesEncoded"] integerValue] > 0)
					[self noteMilestone:@"our first picture encoded"];
				if ([values[@"packetsSent"] integerValue] > 0)
					[self noteMilestone:@"our first picture sent"];
			} else if ([stat.type isEqualToString:@"inbound-rtp"]) {
				if ([values[@"packetsReceived"] integerValue] > 0)
					[self noteMilestone:@"their first packet arrived"];
				if ([values[@"framesDecoded"] integerValue] > 0)
					[self noteMilestone:@"their first picture decoded"];
			}
		}

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
					   dispatch_get_main_queue(), ^{
			[self watchForFirstFramesWithTriesLeft:(triesLeft - 1)];
		});
	}];
}

/*!
 * @brief Write down what is actually flowing, both ways
 *
 * A black picture has three possible reasons, and they look alike from the
 * outside: nothing is sent, nothing arrives, or nothing is drawn. The counters
 * tell them apart.
 */
- (void)logMediaFlowWithTriesLeft:(NSInteger)triesLeft
{
	if (closed || triesLeft <= 0)
		return;

	[self.peerConnection statisticsWithCompletionHandler:^(RTCStatisticsReport *report) {
		NSMutableArray *lines = [NSMutableArray array];

		for (NSString *key in report.statistics) {
			RTCStatistics *stat = report.statistics[key];
			NSDictionary *values = stat.values;

			if ([stat.type isEqualToString:@"inbound-rtp"])
				[lines addObject:[NSString stringWithFormat:@"in %@: packets=%@ bytes=%@ frames=%@ decoded=%@ dropped=%@",
					values[@"kind"] ?: @"?", values[@"packetsReceived"] ?: @0, values[@"bytesReceived"] ?: @0,
					values[@"framesReceived"] ?: @0, values[@"framesDecoded"] ?: @0, values[@"framesDropped"] ?: @0]];
			else if ([stat.type isEqualToString:@"outbound-rtp"])
				[lines addObject:[NSString stringWithFormat:@"out %@: packets=%@ bytes=%@ encoded=%@",
					values[@"kind"] ?: @"?", values[@"packetsSent"] ?: @0, values[@"bytesSent"] ?: @0,
					values[@"framesEncoded"] ?: @0]];
		}

		AILogWithSignature(@"media flow: %@", [lines componentsJoinedByString:@" | "]);

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
					   dispatch_get_main_queue(), ^{
			[self logMediaFlowWithTriesLeft:(triesLeft - 1)];
		});
	}];
}

/*! @brief The peer has started sending on something; look for its picture again */
- (void)peerConnection:(RTCPeerConnection *)peerConnection didStartReceivingOnTransceiver:(RTCRtpTransceiver *)transceiver
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self offerRemoteVideoTrackWithTriesLeft:90];
	});
}

//Required by the protocol, nothing to do
- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeSignalingState:(RTCSignalingState)stateChanged {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream {}
- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)peerConnection {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)newState
{
	AILogWithSignature(@"ICE gathering state %ld for call %@", (long)newState, self.machine.sid);
}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didOpenDataChannel:(RTCDataChannel *)dataChannel {}

@end
