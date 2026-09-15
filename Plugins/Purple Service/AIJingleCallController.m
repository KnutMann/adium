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
	}
	return self;
}

- (id)initAsResponderFrom:(NSString *)localJid to:(NSString *)peerJid sid:(NSString *)sid
{
	if ((self = [super init])) {
		_machine = [[AIJingleSessionMachine alloc] initAsResponderFrom:localJid to:peerJid sid:sid];
		_machine.delegate = self;
		_wantsAudio = YES;
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
	 * from an address it was never told about, and our private address is not
	 * one anybody outside this flat can use, so the call has nowhere to go.
	 * One question to a STUN server answers what our address looks like from
	 * outside, and that is the address every other client offers.
	 *
	 * The servers the account's own XMPP host names come first; these stand in
	 * when it names none, which is the common case. Asking one tells its
	 * operator this machine is placing a call, no more, and the list can be
	 * replaced with the AIJingleSTUNServers default. */
	if (![iceServers count]) {
		NSArray *fallback = [[NSUserDefaults standardUserDefaults] arrayForKey:@"AIJingleSTUNServers"];

		if (![fallback count])
			fallback = @[@"stun:stun.conversations.im:3478", @"stun:stun.l.google.com:19302"];

		for (NSString *url in fallback)
			[iceServers addObject:[[RTCIceServer alloc] initWithURLStrings:@[url]]];
	}

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
			[self.delegate callControllerConnected:self];

			/* The peer's video track, if any, from the live receivers. Attaching a
			 * renderer earlier, in the transceiver callback, draws nothing; measured
			 * in the loopback spike and written down there. */
			if ([self.delegate respondsToSelector:@selector(callController:hasRemoteVideoTrack:)]) {
				for (RTCRtpReceiver *receiver in self.peerConnection.receivers) {
					if ([receiver.track isKindOfClass:[RTCVideoTrack class]]) {
						[self.delegate callController:self
								  hasRemoteVideoTrack:(RTCVideoTrack *)receiver.track];
						break;
					}
				}
			}
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
