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

#import <CoreVideo/CoreVideo.h>
#import <WebRTC/WebRTC.h>

@interface AIJingleCallController () <RTCPeerConnectionDelegate>
@property (nonatomic, strong) AIJingleSessionMachine *machine;
@property (nonatomic, strong) RTCPeerConnection *peerConnection;
@end

@implementation AIJingleCallController {
	RTCVideoSource *syntheticSource;
	RTCVideoCapturer *syntheticCapturer;
	dispatch_source_t syntheticTimer;
	BOOL announcedConnected;
	BOOL closed;
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

- (id)initAsResponderFrom:(NSString *)localJid to:(NSString *)peerJid
{
	if ((self = [super init])) {
		_machine = [[AIJingleSessionMachine alloc] initAsResponderFrom:localJid to:peerJid];
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
	//STUN and TURN arrive with XEP-0215 in a later chapter; hosts on one network meet without them

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

- (void)close
{
	if (closed)
		return;
	closed = YES;

	if (syntheticTimer) {
		dispatch_source_cancel(syntheticTimer);
		syntheticTimer = nil;
	}
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
	RTCIceCandidate *candidate = [[RTCIceCandidate alloc] initWithSdp:line
														sdpMLineIndex:0
															   sdpMid:mid];
	[self.peerConnection addIceCandidate:candidate completionHandler:^(NSError *error) {
		//A candidate that does not fit is no reason to end a call; ICE keeps trying with the rest
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
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.machine addLocalCandidateLine:candidate.sdp mid:(candidate.sdpMid ?: @"0")];
	});
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState
{
	dispatch_async(dispatch_get_main_queue(), ^{
		if ((newState == RTCIceConnectionStateConnected || newState == RTCIceConnectionStateCompleted) &&
			!self->announcedConnected) {
			self->announcedConnected = YES;
			[self.delegate callControllerConnected:self];
		}
		if (newState == RTCIceConnectionStateFailed)
			[self failWith:@"connectivity-error"];
	});
}

//Required by the protocol, nothing to do
- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeSignalingState:(RTCSignalingState)stateChanged {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream {}
- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)peerConnection {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)newState {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didOpenDataChannel:(RTCDataChannel *)dataChannel {}

@end
