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
	BOOL weHaveARelay;				//did gathering give us an address a relay carries
	BOOL saidWeHaveNoRelay;
	BOOL holdingTheCameraBack;		//gathering early, but nobody is being looked at yet
	BOOL cameraRunning;
	BOOL restoreFollowing;			//we changed the camera's following and owe it back
	BOOL followingWasOn;
	AVCaptureCenterStageControlMode formerFollowingControl API_AVAILABLE(macos(12.3));
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

	/* Jingle's ice-udp carries UDP and nothing else, so a TCP candidate is a
	 * candidate nobody on the other end can read. Measured against a phone: two of
	 * the six addresses we offered were TCP, each cost its own stanza, and the
	 * peer's parser throws every one of them away unread. Conversations refuses
	 * them by name, and so does every other client that speaks XEP-0176. */
	configuration.tcpCandidatePolicy = RTCTcpCandidatePolicyDisabled;

	/* We trickle, so we keep looking. Gathering once is right for a client that
	 * sends its whole list at once and then stops talking; ours sends each address
	 * the moment it has it, and a network that changes mid-call, a phone leaving
	 * the flat, is exactly when a fresh address is worth having. */
	configuration.continualGatheringPolicy = RTCContinualGatheringPolicyGatherContinually;

	/* Look for addresses while it is still ringing, so the first sentence we send
	 * already says where we live.
	 *
	 * Measured, and the numbers are worth keeping because they are not obvious.
	 * A pool opens its ports two milliseconds after the connection is built, asks
	 * the STUN server and signs in at the relay, all within about fifty
	 * milliseconds, long before any offer exists. What it does NOT do is hand any
	 * of that over: the addresses appear only when the local description is set.
	 * Reading them inside that completion block gives nothing at all, every single
	 * time, with pool or without, even after waiting five seconds. Read one turn of
	 * the run loop later and they are all there.
	 *
	 * So three things have to be true together, and any one of them alone gives
	 * nothing: a pool, time before the offer, and reading a tick afterwards. With
	 * all three the session-initiate carries six addresses out of six instead of
	 * none, and the relay is already signed in when the other person picks up.
	 * Three rather than one, because one only covered one of this machine's two
	 * network interfaces. */
	configuration.iceCandidatePoolSize = 3;

	//Whatever XEP-0215 offered
	NSMutableArray<RTCIceServer *> *iceServers = [NSMutableArray array];
	for (NSDictionary *entry in self.iceServerDictionaries) {
		NSString *url = entry[@"urls"];
		if (![url length])
			continue;

		/* TRAP, and it takes the whole call with it: a relay address without a
		 * name and a password is one WebRTC refuses to read, and it does not
		 * refuse just that address, it refuses to build the connection at all and
		 * hands back nothing. Every later step then waits on a connection that was
		 * never made, so the call neither rings nor fails nor says why. A relay
		 * nobody gave us the keys to is no relay; it is left out here. */
		if ([url hasPrefix:@"turn"] && !([entry[@"username"] length] && [entry[@"credential"] length])) {
			AILogWithSignature(@"leaving out %@, it was announced without a name and a password", url);
			continue;
		}

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

	/* A relay of our own, when the account's host has none that works.
	 *
	 * A STUN server tells us our address; a relay carries the call when no pair of
	 * addresses can reach each other. Measured against a phone in the same flat:
	 * both sides sat behind one router, the short way between them carried nothing,
	 * this side had no relay at all because the host announces one that answers
	 * nothing, and so the whole call had to wait for the OTHER side's relay to be
	 * tried. That wait was nine seconds of a silent window.
	 *
	 * There is no public relay worth naming here, because carrying somebody else's
	 * call costs real money and every free one is either gone or a trap. So this
	 * stays empty unless somebody fills it: each entry is a dictionary with urls,
	 * username and credential, written into AIJingleTURNServers. */
	for (NSDictionary *entry in [[NSUserDefaults standardUserDefaults] arrayForKey:@"AIJingleTURNServers"]) {
		if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"urls"] length])
			continue;
		if (![entry[@"username"] length] || ![entry[@"credential"] length]) {
			AILogWithSignature(@"leaving out %@, it was written down without a name and a password",
							   entry[@"urls"]);
			continue;
		}
		[iceServers addObject:[[RTCIceServer alloc] initWithURLStrings:@[entry[@"urls"]]
															 username:entry[@"username"]
														   credential:entry[@"credential"]]];
	}

	AILogWithSignature(@"call %@ uses %lu ICE servers", self.machine.sid, (unsigned long)[iceServers count]);
	configuration.iceServers = iceServers;

	RTCMediaConstraints *none = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:@{}
																	  optionalConstraints:@{}];
	self.peerConnection = [[AIJingleCallController factory] peerConnectionWithConfiguration:configuration
																				constraints:none
																				   delegate:self];

	/* And if none was built, say so and end it. Everything below and after assumes
	 * a connection exists; without one the offer's completion block is never
	 * called, so the call would sit there forever, silent, with nothing in the log
	 * and no terminate for the other side either. */
	if (!self.peerConnection) {
		AILogWithSignature(@"call %@ got no connection out of WebRTC; one of the ICE servers "
						   @"cannot be read", self.machine.sid);
		[self failWith:@"failed-application"];
		return;
	}

	if (self.wantsAudio) {
		RTCAudioSource *audioSource = [[AIJingleCallController factory] audioSourceWithConstraints:none];
		RTCAudioTrack *audioTrack = [[AIJingleCallController factory] audioTrackWithSource:audioSource
																				   trackId:@"audio0"];
		/* Somebody may have pressed the switch while it was still ringing, before
		 * any of this existed. What they asked for then still counts now. */
		audioTrack.isEnabled = !self.microphoneMuted;
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
		self.localVideoTrack.isEnabled = !self.cameraOff;
		[self.peerConnection addTrack:self.localVideoTrack streamIds:@[@"adium"]];
		if (!holdingTheCameraBack)
			[self startCamera];
	}
}

/*!
 * @brief Build everything the call needs, but do not look at anybody yet
 *
 * Called while it still rings over there. The connection comes up and starts
 * looking for addresses, which is the whole point, but the camera stays dark: a
 * light that goes on before the other person has even answered is a promise
 * nobody made.
 */
- (void)prepare
{
	holdingTheCameraBack = YES;
	[self ensurePeerConnection];
	holdingTheCameraBack = NO;
}

/*!
 * @brief Start the default camera at a modest format
 *
 * 640x480 around 30 frames is what a chat window needs; the closest format the
 * device offers wins, and among equally close ones a format that can follow the
 * person wins. macOS asks the person for the camera the first time.
 */
- (void)startCamera
{
	if (cameraRunning)
		return;

	AVCaptureDevice *device = [[RTCCameraVideoCapturer captureDevices] firstObject];
	if (!device)
		return;

	BOOL wantsFollowing = [self shouldFollowThePerson];

	AVCaptureDeviceFormat *chosenFormat = nil;
	int32_t chosenDelta = INT32_MAX;
	BOOL chosenCanFollow = NO;
	for (AVCaptureDeviceFormat *format in [RTCCameraVideoCapturer supportedFormatsForDevice:device]) {
		CMVideoDimensions size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
		int32_t delta = abs(size.width - 640) + abs(size.height - 480);
		BOOL canFollow = NO;
		if (@available(macOS 12.3, *))
			canFollow = [format isCenterStageSupported];

		/* Closest to what a chat window needs, and among ties the one that can
		 * follow: turning the following on over a format that cannot do it is an
		 * exception, not a refusal. */
		BOOL better = (delta < chosenDelta) ||
					  (delta == chosenDelta && wantsFollowing && canFollow && !chosenCanFollow);
		if (better) {
			chosenDelta = delta;
			chosenFormat = format;
			chosenCanFollow = canFollow;
		}
	}
	if (!chosenFormat)
		return;

	[self letTheCameraFollow:(wantsFollowing && chosenCanFollow)];

	Float64 fps = 30;
	for (AVFrameRateRange *range in chosenFormat.videoSupportedFrameRateRanges)
		fps = MIN(30, MAX(fps, range.maxFrameRate));

	cameraRunning = YES;
	[cameraCapturer startCaptureWithDevice:device format:chosenFormat fps:(NSInteger)fps];
	[self noteMilestone:@"camera asked to start"];
}

/*! @brief Does the person want the camera to follow them? Yes, unless they said otherwise */
- (BOOL)shouldFollowThePerson
{
	NSNumber *asked = [[NSUserDefaults standardUserDefaults] objectForKey:@"AIJingleFollowThePerson"];
	return (asked ? [asked boolValue] : YES);
}

/*!
 * @brief Keep the person in the middle of their own picture
 *
 * macOS can crop and pan the camera's picture so that whoever is in front of it
 * stays centred while they move, which is the thing everyone else's video calls
 * do and ours did not. Whether the hardware can do it at all is a question of the
 * camera and of the format, so it is asked rather than assumed.
 *
 * TRAP: the enabling flag belongs to the person, not to us, and setting it while
 * the control is theirs alone throws rather than refuses. So the control is moved
 * to shared first, which leaves them the switch in the control centre, and what
 * we found is put back when the call ends unless they changed it meanwhile.
 */
- (void)letTheCameraFollow:(BOOL)following
{
	if (@available(macOS 12.3, *)) {
		if (!following)
			return;

		if (!restoreFollowing) {
			followingWasOn = [AVCaptureDevice isCenterStageEnabled];
			formerFollowingControl = [AVCaptureDevice centerStageControlMode];
			restoreFollowing = YES;
		}

		[AVCaptureDevice setCenterStageControlMode:AVCaptureCenterStageControlModeCooperative];
		[AVCaptureDevice setCenterStageEnabled:YES];
		AILogWithSignature(@"the camera will follow the person (it was %@ before)",
						   followingWasOn ? @"already on" : @"off");
	}
}

/*! @brief Give the following back to the person as we found it */
- (void)stopFollowing
{
	if (@available(macOS 12.3, *)) {
		if (!restoreFollowing)
			return;
		restoreFollowing = NO;

		//Only if it is still ours to give back; they may have changed it themselves
		if ([AVCaptureDevice isCenterStageEnabled] && !followingWasOn)
			[AVCaptureDevice setCenterStageEnabled:NO];
		[AVCaptureDevice setCenterStageControlMode:formerFollowingControl];
	}
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

//Turning our own things off ---------------------------------------------------------------------
#pragma mark Turning our own things off

/*!
 * @brief Which of our streams carries a kind of media, in the words the session uses
 *
 * The mid of the transceiver that sends it, which is what the peer's session knows
 * this content by. Found rather than assumed, because a session with only video
 * does not put video second.
 *
 * TRAP, the same one that once cost an evening of black pictures: asking a sender
 * or a receiver for its track hands back a NEW wrapper around the same native
 * track every single time, so comparing two of them by identity is always false.
 * The kind of media is asked of the transceiver instead, which knows it directly.
 */
- (NSString *)contentNameCarrying:(RTCRtpMediaType)kind
{
	for (RTCRtpTransceiver *transceiver in self.peerConnection.transceivers)
		if (transceiver.mediaType == kind && [transceiver.mid length])
			return transceiver.mid;
	return nil;
}

- (void)setMicrophoneMuted:(BOOL)muted
{
	if (_microphoneMuted == muted)
		return;
	_microphoneMuted = muted;

	for (RTCRtpSender *sender in self.peerConnection.senders)
		if ([sender.track isKindOfClass:[RTCAudioTrack class]])
			sender.track.isEnabled = !muted;

	[self.machine tellPeerMuted:muted content:[self contentNameCarrying:RTCRtpMediaTypeAudio]];
	AILogWithSignature(@"microphone %@", muted ? @"off" : @"on");
}

- (void)setCameraOff:(BOOL)off
{
	if (_cameraOff == off)
		return;
	_cameraOff = off;

	/* The track is silenced rather than the camera stopped: stopping would give the
	 * light back but also tear down the capture, and turning it on again takes long
	 * enough to be noticed. A disabled track sends black, and the light stays on,
	 * which is honest about the camera still being open. */
	self.localVideoTrack.isEnabled = !off;
	[self.machine tellPeerMuted:off content:[self contentNameCarrying:RTCRtpMediaTypeVideo]];

	AILogWithSignature(@"camera %@", off ? @"off" : @"on");
}

- (void)machine:(AIJingleSessionMachine *)machine peerMuted:(BOOL)muted content:(NSString *)name
{
	/* The content's name says which of the two it is. A peer that names neither is
	 * talking about its only stream, and a call with a camera has two. */
	BOOL aboutVideo = ([name rangeOfString:@"video" options:NSCaseInsensitiveSearch].location != NSNotFound);
	BOOL aboutAudio = ([name rangeOfString:@"audio" options:NSCaseInsensitiveSearch].location != NSNotFound);

	if (!aboutVideo && !aboutAudio) {
		//Numbered contents (0, 1) carry no meaning in their name; ask the session
		for (RTCRtpTransceiver *transceiver in self.peerConnection.transceivers) {
			if (![transceiver.mid isEqualToString:name])
				continue;
			aboutVideo = (transceiver.mediaType == RTCRtpMediaTypeVideo);
			aboutAudio = (transceiver.mediaType == RTCRtpMediaTypeAudio);
		}
	}

	if (aboutVideo)
		_peerCameraOff = muted;
	if (aboutAudio)
		_peerMicrophoneMuted = muted;

	AILogWithSignature(@"the peer's %@ is %@", name, muted ? @"off" : @"on");

	if ([self.delegate respondsToSelector:@selector(callControllerPeerChangedWhatItSends:)])
		[self.delegate callControllerPeerChangedWhatItSends:self];
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
	[self stopFollowing];
	[self.peerConnection close];
}

//Driving ----------------------------------------------------------------------------------------
#pragma mark Driving

- (void)start
{
	[self ensurePeerConnection];

	//Whatever was held back while it rang happens now
	if (self.wantsVideo && !self.usesSyntheticVideo)
		[self startCamera];

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
						[weakSelf withSettledSDP:offer then:^(NSString *sdp) {
							[weakSelf.machine startWithLocalOfferSDP:sdp];
						}];
				});
			}];
		});
	}];
}

/*!
 * @brief The description once the addresses are in it, or after a short moment
 *
 * The text handed to the completion block was written before any address was
 * known, and the connection needs a moment more to put them in, even when they
 * were all found long ago: the handing over happens on another thread and is
 * measurably not instant. Waiting for it is worth a few milliseconds, because
 * everything named in the first sentence is something the other side can use at
 * once, while everything sent afterwards may sit in a drawer until it has finished
 * answering.
 *
 * So we look every few milliseconds and give up after a tenth of a second, which
 * is both far longer than it takes when there is something to find and far too
 * short for anybody to notice when there is not.
 */
- (void)withSettledSDP:(RTCSessionDescription *)given then:(void (^)(NSString *sdp))then
{
	NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.1];
	__block __weak void (^lookAgain)(void) = nil;
	void (^look)(void) = ^{
		NSString *settled = self.peerConnection.localDescription.sdp;
		BOOL anyAddresses = ([settled rangeOfString:@"a=candidate"].location != NSNotFound);

		if (anyAddresses || [until timeIntervalSinceNow] <= 0) {
			then([settled length] ? settled : given.sdp);
			return;
		}
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_MSEC)),
					   dispatch_get_main_queue(), lookAgain);
	};
	void (^keptAlive)(void) = [look copy];
	lookAgain = keptAlive;
	keptAlive();
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
								[weakSelf withSettledSDP:answer then:^(NSString *sdp) {
									[weakSelf.machine acceptWithLocalAnswerSDP:sdp];
								}];
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
	if ([candidate.sdp containsString:@" typ relay"])
		weHaveARelay = YES;
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

		/* Written down every second, not just kept: the end picture says who won
		 * but never when the other side woke up, and that is the whole question
		 * when a call takes eight seconds to find a path it had all along. */
		AILogWithSignature(@"checking %+.2fs:\n%@", -[self->startedAt timeIntervalSinceNow],
						   ([description length] ? description : @"(keine Paare)"));

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
			/* Both directions, because they fail differently: nothing answered means
			 * our packets never arrive, nothing asked means theirs never do, and a
			 * path silent in both is a path the network refuses either way. */
			[lines addObject:[NSString stringWithFormat:@"%@ %@:%@ (%@) -> %@:%@ (%@) sent=%@ recv=%@ asked=%@ answered=%@",
				stat.values[@"state"] ?: @"?",
				local[@"address"] ?: @"?", local[@"port"] ?: @"?", local[@"candidateType"] ?: @"?",
				remote[@"address"] ?: @"?", remote[@"port"] ?: @"?", remote[@"candidateType"] ?: @"?",
				stat.values[@"requestsSent"] ?: @0, stat.values[@"responsesReceived"] ?: @0,
				stat.values[@"requestsReceived"] ?: @0, stat.values[@"responsesSent"] ?: @0]];
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

			/* And say what is already switched off. A session-info before the
			 * session stands has nowhere to go, so anything switched off while it
			 * was still ringing has to be said again now. */
			if (self.microphoneMuted)
				[self.machine tellPeerMuted:YES content:[self contentNameCarrying:RTCRtpMediaTypeAudio]];
			if (self.cameraOff)
				[self.machine tellPeerMuted:YES content:[self contentNameCarrying:RTCRtpMediaTypeVideo]];

			/* Which way won, and how often it had to ask. A path that answers the
			 * first request but only after seconds means the waiting happened
			 * somewhere else; one that answers the eighth means the path itself was
			 * the cost. The difference decides where to look next time. */
			[self describePairsInto:^(NSString *description) {
				AILogWithSignature(@"pairs at the moment of connecting:\n%@",
								   ([description length] ? description : @"(keine)"));
			}];

			//The peer's video track, if any, from the live receivers
			[self offerRemoteVideoTrackWithTriesLeft:90];
			[self logMediaFlowWithTriesLeft:10];
			[self watchForFirstFramesWithTriesLeft:120];
		}
		if (newState == RTCIceConnectionStateFailed) {
			/* Measure before giving up: ending the call closes the connection, and a
			 * closed connection reports no pairs at all, which reads as if none were
			 * ever tried. */
			AILogWithSignature(@"ICE gave up; last seen pairs:\n%@",
							   ([self->lastPairSnapshot length] ? self->lastPairSnapshot : @"(keine)"));
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

	/* Whether we ended up with a relay is the one fact that explains a slow call
	 * afterwards, and it is nowhere in the log unless it is written down. Without
	 * one, every path this call can take has to be offered by the other side, and
	 * a peer reaches its own relay late. Said once; gathering that carries on
	 * finishes more than once. */
	if (newState == RTCIceGatheringStateComplete && !weHaveARelay && !saidWeHaveNoRelay) {
		saidWeHaveNoRelay = YES;
		AILogWithSignature(@"call %@ gathered no relay of its own; if the direct ways fail, "
						   @"this call waits for the peer to offer one", self.machine.sid);
	}
}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didOpenDataChannel:(RTCDataChannel *)dataChannel {}

@end
